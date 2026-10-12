//! Mock human reply endpoint.
//!
//! Phase 4: simulates the human endpoint responding. In production,
//! the human replies via the Flutter client over WebSocket.
//!
//! `POST /v1/mock/human-reply`
//! Body: { "conversation_id": "cnv_xxx", "text": "the reply" }
//! OR
//! Body: { "agent_id": "agt_xxx", "text": "the reply" }
//!
//! Phase 7.3: Tool call mock endpoint for validation harness.
//!
//! `POST /v1/mock/tool-call`
//! Body: { "conversation_id": "cnv_xxx", "tool_name": "Bash", "arguments": {"command":"echo hello"} }
//! OR
//! Body: { "agent_id": "agt_xxx", "tool_name": "Bash", "arguments": {...} }
//!
//! # Availability
//!
//! These endpoints impersonate the human: anyone who can reach them can
//! forge replies, tool calls, and turn closures. They are therefore
//! **disabled unless explicitly enabled** — either at compile time via
//! the `mock_endpoints` cargo feature, or at runtime via
//! `OPENHUMAN_MOCK_ENDPOINTS=1`. When disabled the routes are not even
//! registered, so probes get a `404` rather than an error that confirms
//! the endpoints exist.

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json, Response};
use serde::Deserialize;
use serde_json::json;

use crate::storage::AppState;

/// Whether the `/v1/mock/*` harness endpoints are enabled.
///
/// Compile-time `mock_endpoints` feature **or** runtime
/// `OPENHUMAN_MOCK_ENDPOINTS=1` — either one turns them on. Both default to
/// off, so a production build serves no mock routes at all.
///
/// The env var exists for e2e probes against a deployed instance, where
/// rebuilding with the feature is impractical.
pub fn mock_enabled() -> bool {
    #[cfg(feature = "mock_endpoints")]
    {
        return true;
    }

    #[cfg(not(feature = "mock_endpoints"))]
    {
        std::env::var("OPENHUMAN_MOCK_ENDPOINTS")
            .map(|v| {
                let v = v.trim();
                v == "1" || v.eq_ignore_ascii_case("true")
            })
            .unwrap_or(false)
    }
}

#[derive(Debug, Deserialize)]
pub struct HumanReplyRequest {
    pub conversation_id: Option<String>,
    pub agent_id: Option<String>,
    pub text: String,
}

/// Handler for `POST /v1/mock/human-reply`.
pub async fn human_reply(
    State(app): State<AppState>,
    Json(req): Json<HumanReplyRequest>,
) -> Response {
    let conversation_id = match (&req.conversation_id, &req.agent_id) {
        (Some(id), _) => id.clone(),
        (None, Some(agent_id)) => app
            .conversation
            .get_by_agent(agent_id)
            .await
            .map(|c| c.id)
            .unwrap_or_default(),
        (None, None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": {
                        "message": "Either conversation_id or agent_id is required.",
                        "type": "invalid_request_error"
                    }
                })),
            )
                .into_response();
        }
    };

    if conversation_id.is_empty() {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": {
                    "message": "No conversation found for the given parameters.",
                    "type": "conversation_not_found"
                }
            })),
        )
            .into_response();
    }

    // A blocking request is normally waiting on the reply channel. In async
    // mode there is no channel, so also try to complete a parked invocation
    // — otherwise this harness could never drive an async turn.
    let channel_delivered = app.reply.deliver(&conversation_id, &req.text).await;
    let delivered = channel_delivered
        || app
            .async_reply
            .complete_latest_for_conversation(&conversation_id, &req.text)
            .await;

    if delivered {
        Json(json!({
            "ok": true,
            "conversation_id": conversation_id,
            "delivered": true
        }))
        .into_response()
    } else {
        (
            StatusCode::CONFLICT,
            Json(json!({
                "error": {
                    "message": "No active SSE connection waiting for this conversation.",
                    "type": "no_pending_connection",
                    "conversation_id": conversation_id
                }
            })),
        )
            .into_response()
    }
}

// ── End-of-turn mock ──

/// Request body for `POST /v1/mock/end-turn`.
#[derive(Debug, Deserialize)]
pub struct EndTurnRequest {
    pub conversation_id: Option<String>,
    pub agent_id: Option<String>,
}

/// Handler for `POST /v1/mock/end-turn`.
///
/// Closes a streaming turn so the SSE stream emits its final chunk and
/// `[DONE]`. Needed because multi-turn streaming deliberately stays open
/// after a text reply — the human may have more to say — and only an
/// explicit end-of-turn (or a tool call) terminates it. A test harness
/// that only posts text would otherwise hang forever.
pub async fn end_turn(State(app): State<AppState>, Json(req): Json<EndTurnRequest>) -> Response {
    let conversation_id = match (&req.conversation_id, &req.agent_id) {
        (Some(id), _) => id.clone(),
        (None, Some(agent_id)) => app
            .conversation
            .get_by_agent(agent_id)
            .await
            .map(|c| c.id)
            .unwrap_or_default(),
        (None, None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": {
                        "message": "Either conversation_id or agent_id is required.",
                        "type": "invalid_request_error"
                    }
                })),
            )
                .into_response();
        }
    };

    if conversation_id.is_empty() {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": {
                    "message": "No conversation found for the given parameters.",
                    "type": "conversation_not_found"
                }
            })),
        )
            .into_response();
    }

    const END_TURN_SIGNAL: &str = "__END_TURN__";
    let channel_delivered = app.reply.deliver(&conversation_id, END_TURN_SIGNAL).await;
    let delivered = channel_delivered
        || app
            .async_reply
            .complete_latest_for_conversation(&conversation_id, END_TURN_SIGNAL)
            .await;

    if delivered {
        Json(json!({
            "ok": true,
            "conversation_id": conversation_id,
            "delivered": true
        }))
        .into_response()
    } else {
        (
            StatusCode::CONFLICT,
            Json(json!({
                "error": {
                    "message": "No active SSE connection waiting for this conversation.",
                    "type": "no_pending_connection",
                    "conversation_id": conversation_id
                }
            })),
        )
            .into_response()
    }
}

// ── Phase 7.3: Tool Call Mock Endpoint ──

/// Request body for `POST /v1/mock/tool-call`.
///
/// Allows a human tester to trigger a standard OpenAI `tool_calls`
/// response without needing the WebSocket Console UI.
#[derive(Debug, Deserialize)]
pub struct ToolCallRequest {
    pub conversation_id: Option<String>,
    pub agent_id: Option<String>,
    pub tool_name: String,
    pub arguments: serde_json::Value,
}

/// Handler for `POST /v1/mock/tool-call`.
///
/// Delivers a `__tool_call__` payload to the waiting SSE/HTTP handler.
/// The handler detects the marker and converts it to a standard
/// OpenAI `tool_calls` response.
pub async fn tool_call(State(app): State<AppState>, Json(req): Json<ToolCallRequest>) -> Response {
    let conversation_id = match (&req.conversation_id, &req.agent_id) {
        (Some(id), _) => id.clone(),
        (None, Some(agent_id)) => app
            .conversation
            .get_by_agent(agent_id)
            .await
            .map(|c| c.id)
            .unwrap_or_default(),
        (None, None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": {
                        "message": "Either conversation_id or agent_id is required.",
                        "type": "invalid_request_error"
                    }
                })),
            )
                .into_response();
        }
    };

    if conversation_id.is_empty() {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": {
                    "message": "No conversation found for the given parameters.",
                    "type": "conversation_not_found"
                }
            })),
        )
            .into_response();
    }

    // Build the internal tool_call payload — this is what
    // `parse_reply()` in the handler will detect.
    let payload = json!({
        "__tool_call__": true,
        "tool_name": req.tool_name,
        "arguments": req.arguments,
    })
    .to_string();

    tracing::info!(
        conversation_id = %conversation_id,
        tool_name = %req.tool_name,
        "[tool_call] mock endpoint triggered"
    );

    let channel_delivered = app.reply.deliver(&conversation_id, &payload).await;
    let delivered = channel_delivered
        || app
            .async_reply
            .complete_latest_for_conversation(&conversation_id, &payload)
            .await;

    if delivered {
        Json(json!({
            "ok": true,
            "conversation_id": conversation_id,
            "tool_name": req.tool_name,
            "delivered": true,
            "note": "Tool call delivered to waiting handler. Agent will receive standard OpenAI tool_calls response."
        }))
        .into_response()
    } else {
        (
            StatusCode::CONFLICT,
            Json(json!({
                "error": {
                    "message": "No active SSE/HTTP connection waiting for this conversation.",
                    "type": "no_pending_connection",
                    "conversation_id": conversation_id
                }
            })),
        )
            .into_response()
    }
}
