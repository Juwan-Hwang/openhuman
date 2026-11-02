//! `/v1/batches`: a JSONL file of requests run through this server's own
//! endpoints (each line a normal request the seat answers), results
//! collected into an output file and an error file.
//!
//! Batches are tasks (api = "batches") on the TaskRepository: they
//! survive restarts as records, and a batch still running when the
//! process stops is failed by the boot sweep like any other in-flight
//! task. Only the abort handles are process-local.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};

use crate::auth::AuthPrincipal;
use crate::model::task::{TaskRecord, TaskStatus};
use crate::storage::AppState;

const ENDPOINTS: &[&str] = &["/v1/chat/completions", "/v1/responses", "/v1/completions"];

/// How many lines of a batch run at once.
const PARALLEL: usize = 4;

/// Abort handles for the batches this process is running.
fn running() -> &'static Mutex<HashMap<String, tokio::task::AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<String, tokio::task::AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

fn err(status: StatusCode, msg: &str) -> Response {
    (
        status,
        Json(json!({"error": {"message": msg, "type": "invalid_request_error", "code": null, "param": null}})),
    )
        .into_response()
}

/// Run one request line through the endpoint it names.
async fn dispatch(
    app: AppState,
    principal: AuthPrincipal,
    headers: HeaderMap,
    url: &str,
    mut body: Value,
) -> (u16, Value) {
    body["stream"] = json!(false);
    let resp = match url {
        "/v1/chat/completions" => {
            match serde_json::from_value::<crate::openai_compat::ChatCompletionRequest>(
                body.clone(),
            ) {
                Ok(req) => {
                    crate::api::openai::chat_completions(State(app), principal, headers, Json(req))
                        .await
                }
                Err(e) => {
                    return (
                        400,
                        json!({"error": {"message": format!("invalid chat completion request: {e}")}}),
                    )
                }
            }
        }
        "/v1/responses" => {
            crate::api::adapters::responses(State(app), principal, headers, Json(body)).await
        }
        "/v1/completions" => {
            crate::api::completions::completions(State(app), principal, headers, Json(body)).await
        }
        other => {
            return (
                400,
                json!({"error": {"message": format!("unsupported url {other}")}}),
            )
        }
    };
    let status = resp.status().as_u16();
    let bytes = axum::body::to_bytes(resp.into_body(), 256 * 1024 * 1024)
        .await
        .unwrap_or_default();
    let text = String::from_utf8_lossy(&bytes);
    let v = serde_json::from_str(text.trim()).unwrap_or_else(|_| json!({"raw": text.trim()}));
    // A body that carries an error after padding started is still a failure.
    let status = if status == 200 && v.get("error").is_some_and(|e| !e.is_null()) {
        500
    } else {
        status
    };
    (status, v)
}

async fn jsonl_file(
    app: &AppState,
    owner: &str,
    name: &str,
    purpose: &str,
    lines: &[Value],
) -> Option<String> {
    if lines.is_empty() {
        return None;
    }
    let mut bytes = Vec::new();
    for l in lines {
        bytes.extend_from_slice(l.to_string().as_bytes());
        bytes.push(b'\n');
    }
    Some(
        crate::api::files::put(
            app,
            crate::api::files::StoredFile {
                owner: owner.to_string(),
                filename: name.to_string(),
                mime: "application/jsonl".into(),
                purpose: purpose.to_string(),
                bytes,
                created_at: chrono::Utc::now().timestamp(),
            },
        )
        .await,
    )
}

/// `POST /v1/batches`
pub async fn create(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(b): Json<Value>,
) -> Response {
    let Some(file_id) = b.get("input_file_id").and_then(|v| v.as_str()) else {
        return err(StatusCode::BAD_REQUEST, "input_file_id is required");
    };
    let Some(endpoint) = b
        .get("endpoint")
        .and_then(|v| v.as_str())
        .filter(|e| ENDPOINTS.contains(e))
    else {
        return err(
            StatusCode::BAD_REQUEST,
            &format!("endpoint must be one of {}", ENDPOINTS.join(", ")),
        );
    };
    let Some(file) = crate::api::files::get(&app, file_id)
        .await
        .filter(|f| f.owner == principal.agent.id)
    else {
        return err(
            StatusCode::NOT_FOUND,
            &format!("No file found with id '{file_id}'."),
        );
    };
    let text = String::from_utf8_lossy(&file.bytes).to_string();
    let mut lines = Vec::new();
    for (i, l) in text
        .lines()
        .enumerate()
        .filter(|(_, l)| !l.trim().is_empty())
    {
        let v: Value = match serde_json::from_str(l) {
            Ok(v) => v,
            Err(e) => return err(StatusCode::BAD_REQUEST, &format!("line {}: {e}", i + 1)),
        };
        let url = v.get("url").and_then(|u| u.as_str()).unwrap_or("");
        if url != endpoint {
            return err(
                StatusCode::BAD_REQUEST,
                &format!(
                    "line {}: url {url} differs from the batch endpoint {endpoint}",
                    i + 1
                ),
            );
        }
        if v.get("custom_id").and_then(|c| c.as_str()).is_none() {
            return err(
                StatusCode::BAD_REQUEST,
                &format!("line {}: custom_id is required", i + 1),
            );
        }
        lines.push(v);
    }
    if lines.is_empty() {
        return err(StatusCode::BAD_REQUEST, "the input file has no requests");
    }
    let id = format!("batch_{}", uuid::Uuid::now_v7().simple());
    let now = chrono::Utc::now().timestamp();
    let total = lines.len();
    let obj = json!({
        "id": id,
        "object": "batch",
        "endpoint": endpoint,
        "errors": null,
        "input_file_id": file_id,
        "completion_window": b.get("completion_window").cloned().unwrap_or(json!("24h")),
        "status": "in_progress",
        "output_file_id": null,
        "error_file_id": null,
        "created_at": now,
        "in_progress_at": now,
        "expires_at": now + 86400,
        "finalizing_at": null,
        "completed_at": null,
        "failed_at": null,
        "expired_at": null,
        "cancelling_at": null,
        "cancelled_at": null,
        "request_counts": {"total": total, "completed": 0, "failed": 0},
        "metadata": b.get("metadata").cloned().unwrap_or(Value::Null),
    });
    let owner = principal.agent.id.clone();
    app.task
        .create_task(TaskRecord {
            id: id.clone(),
            owner: owner.clone(),
            api: "batches".to_string(),
            status: TaskStatus::Running,
            conversation_id: None,
            request: obj.clone(),
            answer: None,
            error: None,
            created_at: now,
            updated_at: now,
        })
        .await;
    let bid = id.clone();
    let runner_app = app.clone();
    let task = tokio::spawn(async move {
        use futures::StreamExt;
        let results: Vec<(Value, u16, Value)> = futures::stream::iter(lines)
            .map(|line| {
                let (app, principal, headers, bid) = (
                    runner_app.clone(),
                    principal.clone(),
                    headers.clone(),
                    bid.clone(),
                );
                async move {
                    // Each line its own conversation, even when two lines
                    // start with the same words.
                    let mut headers = headers;
                    let key = format!("batch:{bid}:{}", line["custom_id"].as_str().unwrap_or(""));
                    if let Ok(v) = axum::http::HeaderValue::from_str(&key) {
                        headers.insert("x-openhuman-session-id", v);
                    }
                    let url = line["url"].as_str().unwrap_or("").to_string();
                    let body = line.get("body").cloned().unwrap_or(json!({}));
                    let (status, v) = dispatch(app, principal, headers, &url, body).await;
                    (line, status, v)
                }
            })
            .buffered(PARALLEL)
            .collect()
            .await;
        let (mut out, mut errs) = (Vec::new(), Vec::new());
        for (line, status, v) in results {
            let custom_id = line["custom_id"].clone();
            let rid = format!("batch_req_{}", uuid::Uuid::now_v7().simple());
            if status < 400 {
                out.push(json!({"id": rid, "custom_id": custom_id,
                    "response": {"status_code": status, "request_id": rid, "body": v}, "error": null}));
            } else {
                errs.push(json!({"id": rid, "custom_id": custom_id,
                    "response": {"status_code": status, "request_id": rid, "body": v},
                    "error": {"code": "request_failed", "message": v.pointer("/error/message").cloned().unwrap_or(Value::Null)}}));
            }
        }
        let of = jsonl_file(
            &app,
            &owner,
            &format!("{bid}_output.jsonl"),
            "batch_output",
            &out,
        )
        .await;
        let ef = jsonl_file(
            &app,
            &owner,
            &format!("{bid}_error.jsonl"),
            "batch_output",
            &errs,
        )
        .await;
        let now = chrono::Utc::now().timestamp();
        app.task
            .finish_task(
                &bid,
                Some(json!({
                    "output_file_id": of,
                    "error_file_id": ef,
                    "finalizing_at": now,
                    "completed_at": now,
                    "request_counts": {
                        "total": out.len() + errs.len(),
                        "completed": out.len(),
                        "failed": errs.len(),
                    },
                })),
                None,
            )
            .await;
        running().lock().unwrap().remove(&bid);
    });
    running().lock().unwrap().insert(id, task.abort_handle());
    Json(obj).into_response()
}

/// The batch object as the API returns it, rebuilt from the task record.
fn batch_obj(t: &TaskRecord) -> Value {
    let mut o = t.request.clone();
    match t.status {
        TaskStatus::Queued | TaskStatus::Running => {}
        TaskStatus::Completed => {
            o["status"] = json!("completed");
            if let Some(a) = &t.answer {
                for k in [
                    "output_file_id",
                    "error_file_id",
                    "finalizing_at",
                    "completed_at",
                    "request_counts",
                ] {
                    o[k] = a.get(k).cloned().unwrap_or(Value::Null);
                }
            }
        }
        TaskStatus::Failed => {
            if t.error.as_deref() == Some("cancelled") {
                o["status"] = json!("cancelled");
                o["cancelling_at"] = json!(t.updated_at);
                o["cancelled_at"] = json!(t.updated_at);
            } else {
                o["status"] = json!("failed");
                o["failed_at"] = json!(t.updated_at);
                if let Some(e) = &t.error {
                    o["errors"] =
                        json!({"object": "list", "data": [{"code": "batch_failed", "message": e}]});
                }
            }
        }
    }
    o
}

/// `GET /v1/batches/:id`
pub async fn retrieve(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match app.task.get_task(&principal.agent.id, &id).await {
        Some(t) if t.api == "batches" => Json(batch_obj(&t)).into_response(),
        _ => err(
            StatusCode::NOT_FOUND,
            &format!("No batch found with id '{id}'."),
        ),
    }
}

/// `POST /v1/batches/:id/cancel`: lines not answered yet are dropped.
pub async fn cancel(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    let Some(t) = app
        .task
        .get_task(&principal.agent.id, &id)
        .await
        .filter(|t| t.api == "batches")
    else {
        return err(
            StatusCode::NOT_FOUND,
            &format!("No batch found with id '{id}'."),
        );
    };
    if !t.status.finished() {
        if let Some(h) = running().lock().unwrap().remove(&id) {
            h.abort();
        }
        app.task
            .finish_task(&id, None, Some("cancelled".to_string()))
            .await;
    }
    retrieve(State(app), principal, Path(id)).await
}

#[derive(Debug, serde::Deserialize, Default)]
pub struct ListQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    after: Option<String>,
}

/// `GET /v1/batches`, newest first.
pub async fn list(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    let limit = q.limit.unwrap_or(20).clamp(1, 100);
    // Fetch past the page so `after` can find its anchor.
    let tasks = app.task.list_tasks(&principal.agent.id, 500).await;
    let mut items: Vec<Value> = tasks
        .iter()
        .filter(|t| t.api == "batches")
        .map(batch_obj)
        .collect();
    if let Some(a) = &q.after {
        if let Some(i) = items.iter().position(|x| x["id"] == json!(a)) {
            items.drain(..=i);
        }
    }
    let has_more = items.len() > limit;
    items.truncate(limit);
    let id_of = |x: Option<&Value>| x.and_then(|v| v.get("id")).cloned().unwrap_or(Value::Null);
    Json(json!({"object": "list", "first_id": id_of(items.first()), "last_id": id_of(items.last()), "has_more": has_more, "data": items}))
        .into_response()
}
