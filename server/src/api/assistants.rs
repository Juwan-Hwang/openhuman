//! Assistants, Threads, Messages and Runs (the Assistants API) over the
//! chat pipeline. A thread is one seat conversation (its id is the
//! session key); a run sends the thread's messages with the assistant's
//! instructions and function tools; text becomes an assistant message,
//! tool calls put the run in `requires_action` until the caller submits
//! the outputs, which continue the same turn. Runs poll, or stream
//! `thread.*` events.
//!
//! All objects persist through the ObjectRepository (migration 010);
//! only run abort handles are process-local (a run in flight at restart
//! stays `in_progress` until the caller cancels or re-runs it — its
//! record is never lost).

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use axum::body::{Body, Bytes};
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};

use crate::auth::AuthPrincipal;
use crate::storage::traits::StoredObject;
use crate::storage::AppState;

/// Abort handles for the runs this process is executing.
fn running() -> &'static Mutex<HashMap<String, tokio::task::AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<String, tokio::task::AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

fn now() -> i64 {
    chrono::Utc::now().timestamp()
}

fn uid(p: &str) -> String {
    format!("{p}_{}", uuid::Uuid::now_v7().simple())
}

fn err(status: StatusCode, msg: &str) -> Response {
    (
        status,
        Json(json!({"error": {"message": msg, "type": "invalid_request_error", "code": null, "param": null}})),
    )
        .into_response()
}

fn not_found(kind: &str, id: &str) -> Response {
    err(
        StatusCode::NOT_FOUND,
        &format!("No {kind} found with id '{id}'."),
    )
}

async fn of(app: &AppState, owner: &str, id: &str, object: &str) -> Option<StoredObject> {
    app.object
        .get_object(owner, id)
        .await
        .filter(|s| s.obj["object"] == object)
}

#[derive(Debug, serde::Deserialize, Default)]
pub struct ListQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    before: Option<String>,
    #[serde(default)]
    order: Option<String>,
    #[serde(default)]
    run_id: Option<String>,
}

fn page(mut items: Vec<Value>, q: &ListQuery) -> Value {
    if q.order.as_deref().unwrap_or("desc") == "desc" {
        items.reverse();
    }
    if let Some(a) = &q.after {
        if let Some(i) = items.iter().position(|x| x["id"] == json!(a)) {
            items.drain(..=i);
        }
    }
    if let Some(b) = &q.before {
        if let Some(i) = items.iter().position(|x| x["id"] == json!(b)) {
            items.truncate(i);
        }
    }
    let limit = q.limit.unwrap_or(20).clamp(1, 100);
    let has_more = items.len() > limit;
    items.truncate(limit);
    let id_of = |x: Option<&Value>| x.and_then(|v| v.get("id")).cloned().unwrap_or(Value::Null);
    json!({"object": "list", "data": items, "first_id": id_of(items.first()), "last_id": id_of(items.last()), "has_more": has_more})
}

// ── assistants ──

pub async fn create_assistant(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<Value>,
) -> Response {
    let Some(model) = b.get("model").and_then(|v| v.as_str()) else {
        return err(StatusCode::BAD_REQUEST, "model is required");
    };
    let id = uid("asst");
    let g = |k: &str, d: Value| b.get(k).cloned().unwrap_or(d);
    let obj = json!({
        "id": id, "object": "assistant", "created_at": now(), "model": model,
        "name": g("name", Value::Null), "description": g("description", Value::Null),
        "instructions": g("instructions", Value::Null), "tools": g("tools", json!([])),
        "tool_resources": g("tool_resources", json!({})), "metadata": g("metadata", json!({})),
        "temperature": g("temperature", json!(1.0)), "top_p": g("top_p", json!(1.0)),
        "response_format": g("response_format", json!("auto")),
    });
    app.object
        .put_object(
            &id,
            &principal.agent.id,
            StoredObject {
                obj: obj.clone(),
                input: Vec::new(),
                history: Vec::new(),
            },
        )
        .await;
    Json(obj).into_response()
}

pub async fn list_assistants(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    let items = app
        .object
        .list_objects(&principal.agent.id, "assistant")
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .collect();
    Json(page(items, &q)).into_response()
}

pub async fn get_assistant(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "assistant").await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("assistant", &id),
    }
}

pub async fn update_assistant(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "assistant")
        .await
        .is_none()
    {
        return not_found("assistant", &id);
    }
    app.object
        .update_object(&id, &|s| {
            if let Some(o) = b.as_object() {
                for (k, v) in o {
                    if !crate::api::stored::IMMUTABLE_KEYS.contains(&k.as_str()) {
                        s.obj[k] = v.clone();
                    }
                }
            }
        })
        .await;
    get_assistant(State(app), principal, Path(id)).await
}

pub async fn delete_assistant(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "assistant")
        .await
        .is_some()
        && app.object.delete_object(&principal.agent.id, &id).await
    {
        Json(json!({"id": id, "object": "assistant.deleted", "deleted": true})).into_response()
    } else {
        not_found("assistant", &id)
    }
}

// ── threads and messages ──

/// A message object from a create body (`content` text or parts).
fn message_obj(thread: &str, role: &str, content: &Value, extra: &Value) -> Value {
    let parts: Vec<Value> = match content {
        Value::String(s) => vec![json!({"type": "text", "text": {"value": s, "annotations": []}})],
        Value::Array(a) => a
            .iter()
            .map(|p| match p["type"].as_str() {
                Some("text") => json!({"type": "text", "text": {"value": p["text"].as_str().unwrap_or(""), "annotations": []}}),
                _ => p.clone(),
            })
            .collect(),
        _ => Vec::new(),
    };
    json!({
        "id": uid("msg"), "object": "thread.message", "created_at": now(), "thread_id": thread,
        "role": role, "content": parts, "assistant_id": extra.get("assistant_id").cloned().unwrap_or(Value::Null),
        "run_id": extra.get("run_id").cloned().unwrap_or(Value::Null),
        "attachments": extra.get("attachments").cloned().unwrap_or(json!([])),
        "metadata": extra.get("metadata").cloned().unwrap_or(json!({})),
        "status": "completed", "completed_at": now(), "incomplete_at": null, "incomplete_details": null,
    })
}

async fn new_thread(app: &AppState, owner: &str, b: &Value) -> Value {
    let id = uid("thread");
    let obj = json!({"id": id, "object": "thread", "created_at": now(),
        "metadata": b.get("metadata").cloned().unwrap_or(json!({})),
        "tool_resources": b.get("tool_resources").cloned().unwrap_or(json!({}))});
    let msgs: Vec<Value> = b
        .get("messages")
        .and_then(|m| m.as_array())
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|m| message_obj(&id, m["role"].as_str().unwrap_or("user"), &m["content"], m))
        .collect();
    app.object
        .put_object(
            &id,
            owner,
            StoredObject {
                obj: obj.clone(),
                input: msgs,
                history: Vec::new(),
            },
        )
        .await;
    obj
}

pub async fn create_thread(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    body: Option<Json<Value>>,
) -> Response {
    let b = body.map(|Json(b)| b).unwrap_or(json!({}));
    Json(new_thread(&app, &principal.agent.id, &b).await).into_response()
}

pub async fn get_thread(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "thread").await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("thread", &id),
    }
}

pub async fn update_thread(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "thread").await.is_none() {
        return not_found("thread", &id);
    }
    app.object
        .update_object(&id, &|s| {
            for k in ["metadata", "tool_resources"] {
                if let Some(v) = b.get(k) {
                    s.obj[k] = v.clone();
                }
            }
        })
        .await;
    get_thread(State(app), principal, Path(id)).await
}

pub async fn delete_thread(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "thread").await.is_some()
        && app.object.delete_object(&principal.agent.id, &id).await
    {
        Json(json!({"id": id, "object": "thread.deleted", "deleted": true})).into_response()
    } else {
        not_found("thread", &id)
    }
}

pub async fn create_message(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "thread").await.is_none() {
        return not_found("thread", &id);
    }
    let m = message_obj(&id, b["role"].as_str().unwrap_or("user"), &b["content"], &b);
    let mc = m.clone();
    app.object
        .update_object(&id, &|s| s.input.push(mc.clone()))
        .await;
    Json(m).into_response()
}

pub async fn list_messages(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "thread").await {
        Some(s) => {
            let items = s
                .input
                .into_iter()
                .filter(|m| q.run_id.as_ref().is_none_or(|r| m["run_id"] == json!(r)))
                .collect();
            Json(page(items, &q)).into_response()
        }
        None => not_found("thread", &id),
    }
}

pub async fn get_message(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, mid)): Path<(String, String)>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "thread")
        .await
        .and_then(|s| s.input.into_iter().find(|m| m["id"] == json!(mid)))
    {
        Some(m) => Json(m).into_response(),
        None => not_found("message", &mid),
    }
}

pub async fn update_message(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, mid)): Path<(String, String)>,
    Json(b): Json<Value>,
) -> Response {
    let found = of(&app, &principal.agent.id, &id, "thread")
        .await
        .is_some_and(|s| s.input.iter().any(|m| m["id"] == json!(mid)));
    if !found {
        return not_found("message", &mid);
    }
    let md = b.get("metadata").cloned().unwrap_or(json!({}));
    app.object
        .update_object(&id, &|s| {
            for m in s.input.iter_mut().filter(|m| m["id"] == json!(mid)) {
                m["metadata"] = md.clone();
            }
        })
        .await;
    get_message(State(app), principal, Path((id, mid))).await
}

pub async fn delete_message(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, mid)): Path<(String, String)>,
) -> Response {
    let found = of(&app, &principal.agent.id, &id, "thread")
        .await
        .is_some_and(|s| s.input.iter().any(|m| m["id"] == json!(mid)));
    if !found {
        return not_found("message", &mid);
    }
    app.object
        .update_object(&id, &|s| s.input.retain(|m| m["id"] != json!(mid)))
        .await;
    Json(json!({"id": mid, "object": "thread.message.deleted", "deleted": true})).into_response()
}

// ── runs ──

/// The text of a thread message.
fn message_text(m: &Value) -> String {
    m["content"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|p| p.pointer("/text/value").and_then(|v| v.as_str()))
                .collect::<Vec<_>>()
                .join("\n")
        })
        .unwrap_or_default()
}

/// The chat request for a run: instructions, thread messages, then the
/// tool round trips the run has made so far.
fn chat_body(run: &Value, thread: &StoredObject, extra: &[Value]) -> Value {
    let mut messages = Vec::new();
    let ins = run["instructions"].as_str().unwrap_or("");
    if !ins.trim().is_empty() {
        messages.push(json!({"role": "system", "content": ins}));
    }
    for m in &thread.input {
        if m["run_id"] == run["id"] && m["role"] == "assistant" {
            continue;
        }
        let role = if m["role"] == "assistant" {
            "assistant"
        } else {
            "user"
        };
        let mut content = vec![json!({"type": "text", "text": message_text(m)})];
        for p in m["content"].as_array().cloned().unwrap_or_default() {
            if p["type"] == "image_url" {
                content.push(
                    json!({"type": "image_url", "image_url": {"url": p.pointer("/image_url/url")}}),
                );
            }
        }
        if role == "assistant" {
            messages.push(json!({"role": role, "content": message_text(m)}));
        } else {
            messages.push(json!({"role": role, "content": content}));
        }
    }
    messages.extend(extra.iter().cloned());
    let tools: Vec<Value> = run["tools"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|t| t["type"] == "function")
        .map(|t| json!({"type": "function", "function": t["function"]}))
        .collect();
    let mut body = json!({"model": run["model"], "messages": messages, "stream": false});
    if !tools.is_empty() {
        body["tools"] = json!(tools);
    }
    if let Some(rf) = run.get("response_format").filter(|r| r.is_object()) {
        body["response_format"] = rf.clone();
    }
    body
}

async fn fail(app: &AppState, run_id: &str, msg: &str) {
    app.object
        .update_object(run_id, &|s| {
            s.obj["status"] = json!("failed");
            s.obj["failed_at"] = json!(now());
            s.obj["last_error"] = json!({"code": "server_error", "message": msg});
        })
        .await;
}

/// Run one model step: updates the run as it stands after it.
async fn step(app: AppState, principal: AuthPrincipal, headers: HeaderMap, run_id: String) {
    let owner = principal.agent.id.clone();
    let Some(run) = of(&app, &owner, &run_id, "thread.run").await else {
        return;
    };
    let thread_id = run.obj["thread_id"].as_str().unwrap_or("").to_string();
    let Some(thread) = of(&app, &owner, &thread_id, "thread").await else {
        return;
    };
    app.object
        .update_object(&run_id, &|s| {
            s.obj["status"] = json!("in_progress");
            s.obj["started_at"] = json!(now());
        })
        .await;
    let body = chat_body(&run.obj, &thread, &run.history);
    let mut h = headers;
    if let Ok(v) = axum::http::HeaderValue::from_str(&format!("thread:{thread_id}")) {
        h.insert("x-openhuman-session-id", v);
    }
    h.remove("x-openhuman-mode");
    let req = match serde_json::from_value(body) {
        Ok(r) => r,
        Err(e) => return fail(&app, &run_id, &e.to_string()).await,
    };
    let resp =
        crate::api::openai::chat_completions(State(app.clone()), principal, h, Json(req)).await;
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap_or_default();
    let v: Value =
        serde_json::from_str(String::from_utf8_lossy(&bytes).trim()).unwrap_or(Value::Null);
    if v["object"] == "chat.completion.async" {
        return fail(&app, &run_id, "the seat did not answer in time").await;
    }
    let Some(msg) = v.pointer("/choices/0/message").cloned() else {
        return fail(
            &app,
            &run_id,
            v.pointer("/error/message")
                .and_then(|m| m.as_str())
                .unwrap_or("no answer"),
        )
        .await;
    };
    let usage = json!({
        "prompt_tokens": v.pointer("/usage/prompt_tokens").cloned().unwrap_or(json!(0)),
        "completion_tokens": v.pointer("/usage/completion_tokens").cloned().unwrap_or(json!(0)),
        "total_tokens": v.pointer("/usage/total_tokens").cloned().unwrap_or(json!(0)),
    });
    let text = msg["content"].as_str().unwrap_or("").to_string();
    let calls = msg["tool_calls"].as_array().cloned().unwrap_or_default();
    let assistant_id = run.obj["assistant_id"].clone();
    if !text.is_empty() {
        let m = message_obj(
            &thread_id,
            "assistant",
            &json!(text),
            &json!({"assistant_id": assistant_id, "run_id": run_id}),
        );
        let mid = m["id"].clone();
        app.object
            .update_object(&thread_id, &|s| s.input.push(m.clone()))
            .await;
        app.object
            .update_object(&run_id, &|s| {
                s.input.push(json!({"id": uid("step"), "object": "thread.run.step", "created_at": now(), "run_id": run_id,
                    "assistant_id": assistant_id, "thread_id": thread_id, "type": "message_creation", "status": "completed",
                    "completed_at": now(), "step_details": {"type": "message_creation", "message_creation": {"message_id": mid}},
                    "usage": usage.clone(), "last_error": null, "metadata": {}}));
            })
            .await;
    }
    if !calls.is_empty() {
        let tcs: Vec<Value> = calls
            .iter()
            .map(|c| json!({"id": c["id"], "type": "function", "function": c["function"]}))
            .collect();
        app.object
            .update_object(&run_id, &|s| {
                s.history.push(json!({"role": "assistant", "content": if text.is_empty() { Value::Null } else { json!(text) }, "tool_calls": calls.clone()}));
                s.obj["status"] = json!("requires_action");
                s.obj["required_action"] =
                    json!({"type": "submit_tool_outputs", "submit_tool_outputs": {"tool_calls": tcs.clone()}});
                s.obj["usage"] = usage.clone();
                s.input.push(json!({"id": uid("step"), "object": "thread.run.step", "created_at": now(), "run_id": run_id,
                    "assistant_id": assistant_id, "thread_id": thread_id, "type": "tool_calls", "status": "in_progress",
                    "step_details": {"type": "tool_calls", "tool_calls": tcs}, "usage": null, "last_error": null, "metadata": {}}));
            })
            .await;
        return;
    }
    app.object
        .update_object(&run_id, &|s| {
            s.obj["status"] = json!("completed");
            s.obj["completed_at"] = json!(now());
            s.obj["required_action"] = Value::Null;
            s.obj["usage"] = usage.clone();
        })
        .await;
}

#[allow(clippy::result_large_err)] // the error is the HTTP response itself
async fn new_run(
    app: &AppState,
    owner: &str,
    thread_id: &str,
    b: &Value,
) -> Result<Value, Response> {
    let Some(aid) = b.get("assistant_id").and_then(|v| v.as_str()) else {
        return Err(err(StatusCode::BAD_REQUEST, "assistant_id is required"));
    };
    let Some(asst) = of(app, owner, aid, "assistant").await else {
        return Err(not_found("assistant", aid));
    };
    let a = &asst.obj;
    let mut instructions = b
        .get("instructions")
        .and_then(|v| v.as_str())
        .map(String::from)
        .unwrap_or_else(|| a["instructions"].as_str().unwrap_or("").to_string());
    if let Some(add) = b.get("additional_instructions").and_then(|v| v.as_str()) {
        instructions.push_str("\n\n");
        instructions.push_str(add);
    }
    let pick = |k: &str| {
        b.get(k)
            .filter(|v| !v.is_null())
            .cloned()
            .unwrap_or_else(|| a[k].clone())
    };
    let id = uid("run");
    let obj = json!({
        "id": id, "object": "thread.run", "created_at": now(), "thread_id": thread_id, "assistant_id": aid,
        "status": "queued", "required_action": null, "last_error": null, "expires_at": now() + 600,
        "started_at": null, "cancelled_at": null, "failed_at": null, "completed_at": null, "incomplete_details": null,
        "model": pick("model"), "instructions": instructions, "tools": pick("tools"),
        "metadata": b.get("metadata").cloned().unwrap_or(json!({})), "usage": null,
        "temperature": pick("temperature"), "top_p": pick("top_p"), "response_format": pick("response_format"),
        "tool_choice": b.get("tool_choice").cloned().unwrap_or(json!("auto")), "parallel_tool_calls": true,
        "truncation_strategy": {"type": "auto", "last_messages": null},
        "max_prompt_tokens": null, "max_completion_tokens": null,
    });
    app.object
        .put_object(
            &id,
            owner,
            StoredObject {
                obj: obj.clone(),
                input: Vec::new(),
                history: Vec::new(),
            },
        )
        .await;
    if let Some(extra) = b.get("additional_messages").and_then(|m| m.as_array()) {
        let msgs: Vec<Value> = extra
            .iter()
            .map(|m| {
                message_obj(
                    thread_id,
                    m["role"].as_str().unwrap_or("user"),
                    &m["content"],
                    m,
                )
            })
            .collect();
        app.object
            .update_object(thread_id, &|s| s.input.extend(msgs.clone()))
            .await;
    }
    Ok(obj)
}

/// Start the run's next step, in the background or streamed.
async fn go(
    app: AppState,
    principal: AuthPrincipal,
    headers: HeaderMap,
    run_id: String,
    stream: bool,
) -> Response {
    let owner = principal.agent.id.clone();
    if !stream {
        let app2 = app.clone();
        let rid = run_id.clone();
        let task = tokio::spawn(async move {
            step(app2, principal, headers, rid.clone()).await;
            running().lock().unwrap().remove(&rid);
        });
        running()
            .lock()
            .unwrap()
            .insert(run_id.clone(), task.abort_handle());
        let mut o = of(&app, &owner, &run_id, "thread.run")
            .await
            .map(|s| s.obj)
            .unwrap_or(Value::Null);
        if o["status"] == "requires_action" {
            o["status"] = json!("queued");
        }
        return Json(o).into_response();
    }
    let out = async_stream::stream! {
        let ev = |e: &str, d: &Value| Ok::<Bytes, std::convert::Infallible>(Bytes::from(format!("event: {e}\ndata: {d}\n\n")));
        let Some(r) = of(&app, &owner, &run_id, "thread.run").await else { return };
        let thread_id = r.obj["thread_id"].as_str().unwrap_or("").to_string();
        let seen = of(&app, &owner, &thread_id, "thread").await.map(|t| t.input.len()).unwrap_or(0);
        let steps_seen = r.input.len();
        if r.obj["status"] == "queued" {
            yield ev("thread.run.created", &r.obj);
            yield ev("thread.run.queued", &r.obj);
        }
        let mut o = r.obj.clone();
        o["status"] = json!("in_progress");
        yield ev("thread.run.in_progress", &o);
        let rid = run_id.clone();
        let task = tokio::spawn(step(app.clone(), principal, headers, rid));
        let mut tick = tokio::time::interval(std::time::Duration::from_secs(5));
        tick.tick().await;
        tokio::pin!(task);
        loop {
            tokio::select! {
                _ = tick.tick() => yield Ok(Bytes::from_static(b": keepalive\n\n")),
                _ = &mut task => break,
            }
        }
        let Some(r) = of(&app, &owner, &run_id, "thread.run").await else { return };
        for s in r.input.iter().skip(steps_seen) {
            yield ev("thread.run.step.created", s);
            if s["status"] == "completed" {
                yield ev("thread.run.step.completed", s);
            }
        }
        if let Some(t) = of(&app, &owner, &thread_id, "thread").await {
            for m in t.input.iter().skip(seen).filter(|m| m["run_id"] == json!(run_id)) {
                let mut first = m.clone();
                first["status"] = json!("in_progress");
                first["content"] = json!([]);
                yield ev("thread.message.created", &first);
                yield ev("thread.message.in_progress", &first);
                yield ev("thread.message.delta", &json!({"id": m["id"], "object": "thread.message.delta",
                    "delta": {"content": [{"index": 0, "type": "text", "text": {"value": message_text(m), "annotations": []}}]}}));
                yield ev("thread.message.completed", m);
            }
        }
        let kind = match r.obj["status"].as_str().unwrap_or("") {
            "requires_action" => "thread.run.requires_action",
            "failed" => "thread.run.failed",
            "cancelled" => "thread.run.cancelled",
            _ => "thread.run.completed",
        };
        yield ev(kind, &r.obj);
        yield Ok(Bytes::from_static(b"event: done\ndata: [DONE]\n\n"));
    };
    Response::builder()
        .header("Content-Type", "text/event-stream")
        .header("Cache-Control", "no-cache")
        .body(Body::from_stream(out))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

pub async fn create_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Path(thread_id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    if of(&app, &owner, &thread_id, "thread").await.is_none() {
        return not_found("thread", &thread_id);
    }
    let busy = app
        .object
        .list_objects(&owner, "thread.run")
        .await
        .into_iter()
        .any(|(_, s)| {
            s.obj["thread_id"] == json!(thread_id)
                && matches!(
                    s.obj["status"].as_str(),
                    Some("queued" | "in_progress" | "requires_action")
                )
        });
    if busy {
        return err(
            StatusCode::BAD_REQUEST,
            &format!("Thread {thread_id} already has an active run."),
        );
    }
    let run = match new_run(&app, &owner, &thread_id, &b).await {
        Ok(r) => r,
        Err(r) => return r,
    };
    let stream = b.get("stream").and_then(|v| v.as_bool()).unwrap_or(false);
    go(
        app,
        principal,
        headers,
        run["id"].as_str().unwrap_or("").to_string(),
        stream,
    )
    .await
}

/// `POST /v1/threads/runs`: a new thread and its first run.
pub async fn create_thread_and_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let t = new_thread(&app, &owner, b.get("thread").unwrap_or(&json!({}))).await;
    let tid = t["id"].as_str().unwrap_or("").to_string();
    let run = match new_run(&app, &owner, &tid, &b).await {
        Ok(r) => r,
        Err(r) => {
            app.object.delete_object(&owner, &tid).await;
            return r;
        }
    };
    let stream = b.get("stream").and_then(|v| v.as_bool()).unwrap_or(false);
    go(
        app,
        principal,
        headers,
        run["id"].as_str().unwrap_or("").to_string(),
        stream,
    )
    .await
}

async fn get_run(app: &AppState, owner: &str, tid: &str, rid: &str) -> Option<StoredObject> {
    of(app, owner, rid, "thread.run")
        .await
        .filter(|s| s.obj["thread_id"] == json!(tid))
}

pub async fn get_run_route(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((tid, rid)): Path<(String, String)>,
) -> Response {
    match get_run(&app, &principal.agent.id, &tid, &rid).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("run", &rid),
    }
}

pub async fn update_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((tid, rid)): Path<(String, String)>,
    Json(b): Json<Value>,
) -> Response {
    if get_run(&app, &principal.agent.id, &tid, &rid)
        .await
        .is_none()
    {
        return not_found("run", &rid);
    }
    let md = b.get("metadata").cloned().unwrap_or(json!({}));
    app.object
        .update_object(&rid, &|s| s.obj["metadata"] = md.clone())
        .await;
    get_run_route(State(app), principal, Path((tid, rid))).await
}

pub async fn list_runs(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(tid): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    let items = app
        .object
        .list_objects(&principal.agent.id, "thread.run")
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .filter(|o| o["thread_id"] == json!(tid))
        .collect();
    Json(page(items, &q)).into_response()
}

pub async fn cancel_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((tid, rid)): Path<(String, String)>,
) -> Response {
    let Some(r) = get_run(&app, &principal.agent.id, &tid, &rid).await else {
        return not_found("run", &rid);
    };
    if !matches!(
        r.obj["status"].as_str(),
        Some("queued" | "in_progress" | "requires_action")
    ) {
        return err(
            StatusCode::BAD_REQUEST,
            &format!(
                "Cannot cancel run with status '{}'.",
                r.obj["status"].as_str().unwrap_or("")
            ),
        );
    }
    if let Some(h) = running().lock().unwrap().remove(&rid) {
        h.abort();
    }
    app.object
        .update_object(&rid, &|s| {
            s.obj["status"] = json!("cancelled");
            s.obj["cancelled_at"] = json!(now());
            s.obj["required_action"] = Value::Null;
        })
        .await;
    get_run_route(State(app), principal, Path((tid, rid))).await
}

pub async fn submit_tool_outputs(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Path((tid, rid)): Path<(String, String)>,
    Json(b): Json<Value>,
) -> Response {
    let Some(r) = get_run(&app, &principal.agent.id, &tid, &rid).await else {
        return not_found("run", &rid);
    };
    if r.obj["status"] != "requires_action" {
        return err(
            StatusCode::BAD_REQUEST,
            "Runs in status other than requires_action do not accept tool outputs.",
        );
    }
    let want: Vec<String> = r
        .obj
        .pointer("/required_action/submit_tool_outputs/tool_calls")
        .and_then(|t| t.as_array())
        .cloned()
        .unwrap_or_default()
        .iter()
        .filter_map(|t| t["id"].as_str().map(String::from))
        .collect();
    let outs = b
        .get("tool_outputs")
        .and_then(|t| t.as_array())
        .cloned()
        .unwrap_or_default();
    for w in &want {
        if !outs.iter().any(|o| o["tool_call_id"] == json!(w)) {
            return err(
                StatusCode::BAD_REQUEST,
                &format!("Missing tool output for call {w}."),
            );
        }
    }
    let tool_msgs: Vec<Value> = outs
        .iter()
        .map(|o| json!({"role": "tool", "tool_call_id": o["tool_call_id"], "content": o["output"]}))
        .collect();
    app.object
        .update_object(&rid, &|s| {
            s.history.extend(tool_msgs.clone());
            s.obj["required_action"] = Value::Null;
            for st in s
                .input
                .iter_mut()
                .filter(|st| st["type"] == "tool_calls" && st["status"] == "in_progress")
            {
                st["status"] = json!("completed");
                st["completed_at"] = json!(now());
                if let Some(tcs) = st
                    .pointer_mut("/step_details/tool_calls")
                    .and_then(|t| t.as_array_mut())
                {
                    for tc in tcs {
                        if let Some(o) = outs.iter().find(|o| o["tool_call_id"] == tc["id"]) {
                            tc["function"]["output"] = o["output"].clone();
                        }
                    }
                }
            }
        })
        .await;
    let stream = b.get("stream").and_then(|v| v.as_bool()).unwrap_or(false);
    go(app, principal, headers, rid, stream).await
}

pub async fn list_steps(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((tid, rid)): Path<(String, String)>,
    Query(q): Query<ListQuery>,
) -> Response {
    match get_run(&app, &principal.agent.id, &tid, &rid).await {
        Some(s) => Json(page(s.input, &q)).into_response(),
        None => not_found("run", &rid),
    }
}

pub async fn get_step(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((tid, rid, sid)): Path<(String, String, String)>,
) -> Response {
    match get_run(&app, &principal.agent.id, &tid, &rid)
        .await
        .and_then(|s| s.input.into_iter().find(|x| x["id"] == json!(sid)))
    {
        Some(s) => Json(s).into_response(),
        None => not_found("run step", &sid),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn messages_become_chat() {
        let run = json!({"id": "run_1", "instructions": "be kind", "model": "m", "tools": [{"type": "function", "function": {"name": "f"}}]});
        let t = StoredObject {
            obj: json!({}),
            input: vec![message_obj("t", "user", &json!("hi"), &json!({}))],
            history: Vec::new(),
        };
        let b = chat_body(&run, &t, &[]);
        assert_eq!(b["messages"][0]["role"], "system");
        assert_eq!(b["messages"][1]["content"][0]["text"], "hi");
        assert_eq!(b["tools"][0]["function"]["name"], "f");
    }
}
