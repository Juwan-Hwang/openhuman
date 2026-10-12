//! `GET /v1/replies/{invocation_id}` — asynchronous reply polling.
//!
//! Companion to async mode on `/v1/chat/completions`: the agent submits a
//! turn with `x-openhuman-mode: async`, receives an `invocation_id` right
//! away, and polls here until the human answers.
//!
//! Supports long-polling via `?wait=<secs>` so a well-behaved client holds
//! one connection instead of hammering the endpoint.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json};
use serde::Deserialize;
use serde_json::json;

use crate::api::openai::{parse_turn, HumanReply};
use crate::async_reply::{AsyncStatus, DEFAULT_WAIT_SECS};
use crate::storage::AppState;

/// Query parameters accepted by the polling endpoint.
#[derive(Debug, Deserialize)]
pub struct PollQuery {
    /// Seconds to hold the connection waiting for the reply.
    ///
    /// Capped server-side: an unbounded wait would let a client pin a
    /// connection indefinitely.
    #[serde(default)]
    pub wait: Option<u64>,
}

/// Upper bound on `?wait=`, so a client cannot pin a connection forever.
const MAX_WAIT_SECS: u64 = 300;

/// Poll an async invocation.
///
/// Returns `200` with `status: "pending"` while the human has not answered,
/// and `200` with a populated `choices` array once they have — matching the
/// shape of a normal chat completion so agents can reuse their parsing.
///
/// `404` means the invocation is unknown or was evicted (older than the TTL),
/// which for a client means "resubmit the turn".
pub async fn get_reply(
    State(app): State<AppState>,
    Path(invocation_id): Path<String>,
    Query(query): Query<PollQuery>,
) -> impl IntoResponse {
    let snapshot = match app.async_reply.get(&invocation_id).await {
        Some(s) => s,
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(json!({
                    "error": {
                        "message": "Unknown invocation_id. It may have expired — resubmit the request.",
                        "type": "invalid_request_error",
                        "code": "invocation_not_found"
                    }
                })),
            )
                .into_response();
        }
    };

    // Completed — answer immediately, no waiting.
    if snapshot.status == AsyncStatus::Completed {
        return completed_response(
            &invocation_id,
            snapshot.payload.as_deref(),
            snapshot.age_secs,
        );
    }

    // Expired — the turn is gone; the client must resubmit.
    if snapshot.status == AsyncStatus::Expired {
        return (
            StatusCode::GONE,
            Json(json!({
                "id": invocation_id,
                "object": "chat.completion.async",
                "status": AsyncStatus::Expired.as_str(),
            })),
        )
            .into_response();
    }

    // Still pending. Honour ?wait= as a long-poll.
    let wait = query.wait.unwrap_or(DEFAULT_WAIT_SECS).min(MAX_WAIT_SECS);
    if let Some(payload) = app
        .async_reply
        .wait(&invocation_id, std::time::Duration::from_secs(wait))
        .await
    {
        return completed_response(&invocation_id, Some(&payload), snapshot.age_secs);
    }

    (
        StatusCode::OK,
        Json(json!({
            "id": invocation_id,
            "object": "chat.completion.async",
            "status": AsyncStatus::Pending.as_str(),
            "age_secs": snapshot.age_secs,
            "waited_secs": wait,
        })),
    )
        .into_response()
}

/// Shape a completed invocation as an OpenAI-style completion.
///
/// Tool-call payloads are handled here too — otherwise async mode would
/// silently downgrade a human tool invocation into plain text, the same
/// defect that affected the blocking path.
fn completed_response(
    invocation_id: &str,
    payload: Option<&str>,
    age_secs: i64,
) -> axum::response::Response {
    let payload = payload.unwrap_or("");

    let message = match parse_turn(payload) {
        HumanReply::Text { text, .. } => json!({
            "role": "assistant",
            "content": text,
        }),
        HumanReply::ToolCalls { calls, text } => json!({
            "role": "assistant",
            // Companion prose rides alongside the calls rather than being
            // dropped — see `HumanReply::ToolCalls`.
            "content": text.filter(|t| !t.trim().is_empty()),
            "tool_calls": calls.iter().map(|c| json!({
                "id": c.invocation_id.clone().unwrap_or_else(
                    || format!("call_{}", uuid::Uuid::now_v7().simple())),
                "type": "function",
                "function": {
                    "name": c.tool_name,
                    "arguments": c.arguments.to_string(),
                }
            })).collect::<Vec<_>>()
        }),
        HumanReply::EndTurn => json!({
            "role": "assistant",
            "content": "(turn ended)",
        }),
    };

    let finish_reason = if message.get("tool_calls").is_some() {
        "tool_calls"
    } else {
        "stop"
    };

    (
        StatusCode::OK,
        Json(json!({
            "id": invocation_id,
            "object": "chat.completion.async",
            "status": AsyncStatus::Completed.as_str(),
            "age_secs": age_secs,
            "choices": [{
                "index": 0,
                "message": message,
                "finish_reason": finish_reason,
            }]
        })),
    )
        .into_response()
}
