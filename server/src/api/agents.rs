//! The Agents API (beta): agents, sessions with turns, items and an
//! event stream. The seat is the agent: each turn step sends the
//! session's items as chat history with the agent's instructions and
//! function tools, in one seat conversation per session. Text becomes an
//! assistant message; tool calls put the session in `requires_action`
//! until the caller posts tool results, which go on with the same turn.
//!
//! Objects persist through the ObjectRepository (migration 010).
//! Process-local only: the event broadcast channels and the abort
//! handles of steps this process is running (a step in flight at
//! restart leaves its turn `in_progress` — cancel it or send the next
//! message; the record is never lost).
//!
//! Environments, templates, vaults, credentials and automations are not
//! ported: they describe compute this server does not run.

// Handlers return the HTTP error response itself as their `Err`.
#![allow(clippy::result_large_err)]

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use axum::body::{Body, Bytes};
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};
use tokio::sync::broadcast;

use crate::auth::AuthPrincipal;
use crate::storage::traits::StoredObject;
use crate::storage::AppState;

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

fn bad(msg: &str) -> Response {
    err(StatusCode::BAD_REQUEST, msg)
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

async fn put(app: &AppState, owner: &str, obj: Value) -> Value {
    let id = obj["id"].as_str().unwrap_or("").to_string();
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
    obj
}

#[derive(Debug, serde::Deserialize, Default)]
pub struct ListQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    order: Option<String>,
    #[serde(default)]
    agent_id: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    session_id: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    status: Option<String>,
    #[serde(default, rename = "type")]
    #[allow(dead_code)]
    kind: Option<String>,
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
    let limit = q.limit.unwrap_or(20).clamp(1, 100);
    let has_more = items.len() > limit;
    items.truncate(limit);
    let id_of = |x: Option<&Value>| x.and_then(|v| v.get("id")).cloned().unwrap_or(Value::Null);
    json!({"object": "list", "data": items, "first_id": id_of(items.first()), "last_id": id_of(items.last()), "has_more": has_more})
}

async fn listed(app: &AppState, owner: &str, object: &str) -> Vec<Value> {
    app.object
        .list_objects(owner, object)
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .collect()
}

fn deleted(id: &str, object: &str) -> Response {
    Json(json!({"id": id, "object": object, "deleted": true})).into_response()
}

fn str_map(v: Option<&Value>) -> Value {
    match v {
        Some(Value::Object(m)) => Value::Object(m.clone()),
        _ => json!({}),
    }
}

/// Apply the keys of `b` that are in `keys` onto `obj`.
fn patch(obj: &mut Value, b: &Value, keys: &[&str]) {
    for k in keys {
        if let Some(v) = b.get(*k) {
            obj[*k] = v.clone();
        }
    }
}

// ── agents ──

fn tools(v: Option<&Value>) -> Value {
    let list = v.and_then(|t| t.as_array()).cloned().unwrap_or_default();
    Value::Array(
        list.into_iter()
            .map(|mut t| {
                if t["type"] == "function" {
                    if t.get("description").is_none_or(|d| d.is_null()) {
                        t["description"] = json!("");
                    }
                    if t.get("parameters").is_none_or(|d| d.is_null()) {
                        t["parameters"] = json!({"type": "object", "properties": {}});
                    }
                    if t.get("defer_loading").is_none() {
                        t["defer_loading"] = json!(false);
                    }
                }
                t
            })
            .collect(),
    )
}

/// The agent configuration from a request body, over `base`.
fn agent_config(b: &Value, base: Option<&Value>) -> Value {
    let mut a = base.cloned().unwrap_or_else(|| {
        json!({
            "instructions": null, "model": "gpt-5.5", "name": null,
            "multi_agent": {"enabled": false, "max_concurrent_subagents": null},
            "reasoning": {"effort": null, "summary": null}, "service_tier": "auto",
            "text": {"format": {"type": "text"}, "verbosity": "medium"},
            "tools": [], "compaction": null, "experimental": null,
        })
    });
    patch(
        &mut a,
        b,
        &[
            "instructions",
            "model",
            "name",
            "multi_agent",
            "reasoning",
            "service_tier",
            "compaction",
            "experimental",
        ],
    );
    if let Some(t) = b.get("text").filter(|t| t.is_object()) {
        let mut text = a["text"].clone();
        for (k, v) in t.as_object().unwrap() {
            text[k] = v.clone();
        }
        a["text"] = text;
    }
    if b.get("tools").is_some() {
        a["tools"] = tools(b.get("tools"));
    }
    a
}

pub async fn create_agent(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<Value>,
) -> Response {
    let mut a = agent_config(&b, None);
    a["id"] = json!(uid("agent"));
    a["object"] = json!("agent");
    a["created_at"] = json!(now());
    a["updated_at"] = json!(now());
    a["metadata"] = str_map(b.get("metadata"));
    Json(put(&app, &principal.agent.id, a).await).into_response()
}

pub async fn list_agents(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    Json(page(listed(&app, &principal.agent.id, "agent").await, &q)).into_response()
}

pub async fn get_agent(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "agent").await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("agent", &id),
    }
}

pub async fn update_agent(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &id, "agent").await else {
        return not_found("agent", &id);
    };
    let mut a = agent_config(&b, Some(&s.obj));
    if let Some(m) = b.get("metadata") {
        a["metadata"] = str_map(Some(m));
    }
    a["updated_at"] = json!(now());
    app.object.update_object(&id, &|s| s.obj = a.clone()).await;
    Json(a).into_response()
}

pub async fn delete_agent(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "agent").await.is_none() {
        return not_found("agent", &id);
    }
    app.object.delete_object(&principal.agent.id, &id).await;
    deleted(&id, "agent.deleted")
}

// ── session runtime ──

struct Live {
    tx: broadcast::Sender<Value>,
}

fn live() -> &'static Mutex<HashMap<String, Live>> {
    static L: OnceLock<Mutex<HashMap<String, Live>>> = OnceLock::new();
    L.get_or_init(|| Mutex::new(HashMap::new()))
}

fn subscribe(sid: &str) -> broadcast::Receiver<Value> {
    let mut g = live().lock().unwrap();
    g.entry(sid.to_string())
        .or_insert_with(|| Live {
            tx: broadcast::channel(4096).0,
        })
        .tx
        .subscribe()
}

fn emit(sid: &str, mut ev: Value) {
    ev["event_id"] = json!(uid("event"));
    if let Some(l) = live().lock().unwrap().get(sid) {
        let _ = l.tx.send(ev);
    }
}

/// Abort handles for the session steps this process is running.
fn running() -> &'static Mutex<HashMap<String, tokio::task::AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<String, tokio::task::AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

async fn session_obj(app: &AppState, owner: &str, sid: &str) -> Value {
    of(app, owner, sid, "agent.session")
        .await
        .map(|s| s.obj)
        .unwrap_or(Value::Null)
}

async fn emit_session(app: &AppState, owner: &str, sid: &str, kind: &str) {
    let session = session_obj(app, owner, sid).await;
    emit(sid, json!({"type": kind, "session": session}));
}

fn usage(input: i64, output: i64) -> Value {
    json!({"input_tokens": input, "input_tokens_details": {"cached_tokens": 0},
           "output_tokens": output, "output_tokens_details": {"reasoning_tokens": 0},
           "total_tokens": input + output})
}

/// Mutate one turn of the session's history; returns the turn after.
async fn set_turn(
    app: &AppState,
    sid: &str,
    turn_id: &str,
    f: impl Fn(&mut Value) + Send + Sync,
) -> Value {
    let out = std::sync::Arc::new(std::sync::Mutex::new(Value::Null));
    let out2 = out.clone();
    app.object
        .update_object(sid, &move |s| {
            if let Some(t) = s.history.iter_mut().find(|t| t["id"] == json!(turn_id)) {
                f(t);
                *out2.lock().unwrap() = t.clone();
            }
        })
        .await;
    let v = out.lock().unwrap().clone();
    v
}

async fn add_item(app: &AppState, sid: &str, item: &Value) {
    let item = item.clone();
    app.object
        .update_object(sid, &move |s| s.input.push(item.clone()))
        .await;
}

/// The session's items as chat messages for the seat.
fn chat_body(session: &StoredObject) -> Value {
    let agent = &session.obj["agent"];
    let mut messages: Vec<Value> = Vec::new();
    let mut system = agent["instructions"].as_str().unwrap_or("").to_string();
    let env = &session.obj["environment"];
    if env["type"] == "self_hosted" {
        if let Some(d) = env["workspace_directory"].as_str() {
            system.push_str(&format!("\n\nWorkspace: {d}"));
        }
    }
    if !system.trim().is_empty() {
        messages.push(json!({"role": "system", "content": system.trim()}));
    }
    for it in &session.input {
        match it["type"].as_str().unwrap_or("") {
            "message" if it["role"] == "assistant" => {
                let text: String = it["content"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|p| p["text"].as_str()).collect())
                    .unwrap_or_default();
                messages.push(json!({"role": "assistant", "content": text}));
            }
            "message" => {
                let mut parts = Vec::new();
                for p in it["content"].as_array().cloned().unwrap_or_default() {
                    match p["type"].as_str().unwrap_or("") {
                        "input_text" | "text" => {
                            parts.push(json!({"type": "text", "text": p["text"]}))
                        }
                        "input_image" => parts.push(
                            json!({"type": "image_url", "image_url": {"url": p["image_url"]}}),
                        ),
                        _ => {}
                    }
                }
                messages.push(json!({"role": "user", "content": parts}));
            }
            "function_call" => {
                let args = match &it["arguments"] {
                    Value::String(s) => s.clone(),
                    v => v.to_string(),
                };
                let call = json!({"id": it["call_id"], "type": "function",
                                  "function": {"name": it["name"], "arguments": args}});
                match messages.last_mut() {
                    Some(m) if m["role"] == "assistant" && m["tool_calls"].is_array() => {
                        m["tool_calls"].as_array_mut().unwrap().push(call);
                    }
                    _ => messages
                        .push(json!({"role": "assistant", "content": null, "tool_calls": [call]})),
                }
            }
            "function_call_output" => {
                let content = match &it["output"] {
                    Value::String(s) => s.clone(),
                    Value::Array(a) => a
                        .iter()
                        .filter_map(|p| p["text"].as_str())
                        .collect::<Vec<_>>()
                        .join("\n"),
                    Value::Null => it["error"]
                        .as_str()
                        .map(|e| format!("error: {e}"))
                        .unwrap_or_default(),
                    v => v.to_string(),
                };
                messages.push(
                    json!({"role": "tool", "tool_call_id": it["call_id"], "content": content}),
                );
            }
            _ => {}
        }
    }
    let fns: Vec<Value> = agent["tools"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|t| t["type"] == "function")
        .map(|t| json!({"type": "function", "function": {"name": t["name"], "description": t["description"], "parameters": t["parameters"]}}))
        .collect();
    let mut body = json!({"model": agent["model"], "messages": messages, "stream": false});
    if !fns.is_empty() {
        body["tools"] = json!(fns);
    }
    let fmt = &agent["text"]["format"];
    if fmt["type"] == "json_schema" {
        let schema = fmt
            .get("schema")
            .cloned()
            .unwrap_or_else(|| json!({"type": "object"}));
        body["response_format"] = json!({"type": "json_schema", "json_schema": {
            "name": fmt["name"].as_str().unwrap_or("output"), "schema": schema,
            "strict": fmt.get("strict").cloned().unwrap_or(Value::Null)}});
    } else if fmt["type"] == "json_object" {
        body["response_format"] = json!({"type": "json_object"});
    }
    body
}

async fn fail_turn(app: &AppState, owner: &str, sid: &str, turn_id: &str, msg: &str) {
    let turn = set_turn(app, sid, turn_id, |t| {
        t["status"] = json!("failed");
        t["completed_at"] = json!(now());
        t["error"] = json!({"code": "server_error", "message": msg});
    })
    .await;
    emit(
        sid,
        json!({"type": "agent.session.turn.failed", "session_id": sid, "turn_id": turn_id, "turn": turn}),
    );
    app.object
        .update_object(sid, &|s| {
            s.obj["status"] = json!("idle");
            s.obj["error"] = Value::Null;
            s.obj["required_actions"] = json!([]);
            s.obj["last_active_at"] = json!(now());
        })
        .await;
    emit(
        sid,
        json!({"type": "agent.session.error", "session_id": sid, "turn_id": turn_id, "error": {"code": "server_error", "message": msg}}),
    );
    emit_session(app, owner, sid, "agent.session.idle").await;
}

/// Abort and forget the step this process runs for the session, if any.
fn abort_running(sid: &str) {
    if let Some(h) = running().lock().unwrap().remove(sid) {
        h.abort();
    }
}

/// One seat step of a turn.
async fn step(
    app: AppState,
    principal: AuthPrincipal,
    headers: HeaderMap,
    sid: String,
    turn_id: String,
) {
    let owner = principal.agent.id.clone();
    let Some(session) = of(&app, &owner, &sid, "agent.session").await else {
        return;
    };
    let body = chat_body(&session);
    let mut h = headers;
    if let Ok(v) = axum::http::HeaderValue::from_str(&format!("agent-session:{sid}")) {
        h.insert("x-openhuman-session-id", v);
    }
    h.remove("x-openhuman-mode");
    let req = match serde_json::from_value(body) {
        Ok(r) => r,
        Err(e) => return fail_turn(&app, &owner, &sid, &turn_id, &e.to_string()).await,
    };
    let resp =
        crate::api::openai::chat_completions(State(app.clone()), principal, h, Json(req)).await;
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap_or_default();
    let v: Value =
        serde_json::from_str(String::from_utf8_lossy(&bytes).trim()).unwrap_or(Value::Null);
    if v["object"] == "chat.completion.async" {
        return fail_turn(
            &app,
            &owner,
            &sid,
            &turn_id,
            "the seat did not answer in time",
        )
        .await;
    }
    let Some(msg) = v.pointer("/choices/0/message").cloned() else {
        let m = v
            .pointer("/error/message")
            .and_then(|m| m.as_str())
            .unwrap_or("no answer");
        return fail_turn(&app, &owner, &sid, &turn_id, m).await;
    };
    let tin = v
        .pointer("/usage/prompt_tokens")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    let tout = v
        .pointer("/usage/completion_tokens")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    let text = msg["content"].as_str().unwrap_or("").to_string();
    let calls = msg["tool_calls"].as_array().cloned().unwrap_or_default();
    let mut index = of(&app, &owner, &sid, "agent.session")
        .await
        .map(|s| {
            s.input
                .iter()
                .filter(|i| i["turn_id"] == json!(turn_id) && i["role"] != "user")
                .count()
        })
        .unwrap_or(0);
    let base = |id: &str, index: usize| json!({"session_id": sid, "turn_id": turn_id, "item_id": id, "output_index": index, "content_index": 0});
    let with = |mut v: Value, extra: Value| {
        if let (Some(o), Some(e)) = (v.as_object_mut(), extra.as_object()) {
            for (k, x) in e {
                o.insert(k.clone(), x.clone());
            }
        }
        v
    };
    if !text.is_empty() {
        let id = uid("msg");
        let phase = if calls.is_empty() {
            "final_answer"
        } else {
            "commentary"
        };
        let mut item = json!({"id": id, "type": "message", "role": "assistant", "phase": phase,
            "status": "in_progress", "content": [], "turn_id": turn_id});
        emit(
            &sid,
            json!({"type": "agent.session.turn.item.added", "session_id": sid, "turn_id": turn_id, "output_index": index, "item": item}),
        );
        let part = json!({"type": "output_text", "text": ""});
        emit(
            &sid,
            with(
                base(&id, index),
                json!({"type": "agent.session.turn.content_part.added", "part": part}),
            ),
        );
        emit(
            &sid,
            with(
                base(&id, index),
                json!({"type": "agent.session.turn.output_text.delta", "delta": text}),
            ),
        );
        emit(
            &sid,
            with(
                base(&id, index),
                json!({"type": "agent.session.turn.output_text.done", "text": text}),
            ),
        );
        let part = json!({"type": "output_text", "text": text});
        emit(
            &sid,
            with(
                base(&id, index),
                json!({"type": "agent.session.turn.content_part.done", "part": part}),
            ),
        );
        item["content"] = json!([part]);
        item["status"] = json!("completed");
        add_item(&app, &sid, &item).await;
        emit(
            &sid,
            json!({"type": "agent.session.turn.item.done", "session_id": sid, "turn_id": turn_id, "output_index": index, "item": item}),
        );
        index += 1;
    }
    let mut actions = Vec::new();
    for c in &calls {
        let raw = c
            .pointer("/function/arguments")
            .and_then(|a| a.as_str())
            .unwrap_or("{}");
        let args: Value = serde_json::from_str(raw).unwrap_or_else(|_| json!(raw));
        let name = c.pointer("/function/name").cloned().unwrap_or(Value::Null);
        let item = json!({"id": uid("fc"), "type": "function_call", "call_id": c["id"], "name": name,
            "arguments": args, "status": "completed", "turn_id": turn_id});
        add_item(&app, &sid, &item).await;
        emit(
            &sid,
            json!({"type": "agent.session.turn.item.added", "session_id": sid, "turn_id": turn_id, "output_index": index, "item": item}),
        );
        emit(
            &sid,
            json!({"type": "agent.session.turn.item.done", "session_id": sid, "turn_id": turn_id, "output_index": index, "item": item}),
        );
        actions.push(json!({"type": "function_call", "call_id": c["id"], "name": name, "arguments": args, "turn_id": turn_id}));
        index += 1;
    }
    let add_usage = |u: &Value| {
        let g = |k: &str| u[k].as_i64().unwrap_or(0);
        usage(g("input_tokens") + tin, g("output_tokens") + tout)
    };
    if !actions.is_empty() {
        set_turn(&app, &sid, &turn_id, |t| {
            t["status"] = json!("waiting");
            t["usage"] = add_usage(&t["usage"]);
        })
        .await;
        app.object
            .update_object(&sid, &move |s| {
                s.obj["status"] = json!("requires_action");
                s.obj["required_actions"] = json!(actions.clone());
                s.obj["usage"] = add_usage(&s.obj["usage"]);
                s.obj["last_active_at"] = json!(now());
            })
            .await;
        emit_session(&app, &owner, &sid, "agent.session.requires_action").await;
        return;
    }
    let turn = set_turn(&app, &sid, &turn_id, |t| {
        t["status"] = json!("completed");
        t["completed_at"] = json!(now());
        t["usage"] = add_usage(&t["usage"]);
    })
    .await;
    emit(
        &sid,
        json!({"type": "agent.session.turn.completed", "session_id": sid, "turn_id": turn_id, "turn": turn, "usage": turn["usage"]}),
    );
    app.object
        .update_object(&sid, &|s| {
            s.obj["status"] = json!("idle");
            s.obj["required_actions"] = json!([]);
            s.obj["usage"] = add_usage(&s.obj["usage"]);
            s.obj["last_active_at"] = json!(now());
        })
        .await;
    emit_session(&app, &owner, &sid, "agent.session.idle").await;
}

fn spawn_step(
    app: &AppState,
    principal: &AuthPrincipal,
    headers: &HeaderMap,
    sid: &str,
    turn_id: &str,
) {
    let (app, principal, headers) = (app.clone(), principal.clone(), headers.clone());
    let (s, t) = (sid.to_string(), turn_id.to_string());
    let key = sid.to_string();
    let task = tokio::spawn(async move {
        step(app, principal, headers, s.clone(), t).await;
        running().lock().unwrap().remove(&s);
    });
    running().lock().unwrap().insert(key, task.abort_handle());
}

/// Normalize input messages (a string, or a list of user messages).
fn input_messages(v: &Value) -> Result<Vec<Value>, String> {
    match v {
        Value::Null => Ok(Vec::new()),
        Value::String(s) => Ok(vec![
            json!({"type": "message", "role": "user", "content": [{"type": "input_text", "text": s}]}),
        ]),
        Value::Array(a) => a
            .iter()
            .map(|m| {
                let content = match &m["content"] {
                    Value::String(s) => json!([{"type": "input_text", "text": s}]),
                    Value::Array(p) => Value::Array(p.clone()),
                    _ => return Err("each input message needs content".to_string()),
                };
                Ok(json!({"type": "message", "role": "user", "content": content}))
            })
            .collect(),
        _ => Err("input must be a string or a list of messages".into()),
    }
}

/// Start a turn with these user messages.
async fn start_turn(
    app: &AppState,
    principal: &AuthPrincipal,
    headers: &HeaderMap,
    sid: &str,
    msgs: Vec<Value>,
) {
    let owner = principal.agent.id.clone();
    let turn_id = uid("turn");
    let agent_id = session_obj(app, &owner, sid).await["agent"]["id"].clone();
    let turn = json!({"id": turn_id, "object": "agent.session.turn", "session_id": sid, "agent_id": agent_id,
        "created_at": now(), "started_at": now(), "completed_at": null, "status": "in_progress",
        "error": null, "subagent_id": null, "usage": usage(0, 0)});
    let turn2 = turn.clone();
    app.object
        .update_object(sid, &move |s| {
            s.history.push(turn2.clone());
            s.obj["status"] = json!("in_progress");
            s.obj["last_active_at"] = json!(now());
        })
        .await;
    let mut queued = turn.clone();
    queued["status"] = json!("queued");
    emit(
        sid,
        json!({"type": "agent.session.turn.created", "session_id": sid, "turn_id": turn_id, "turn": queued}),
    );
    emit_session(app, &owner, sid, "agent.session.in_progress").await;
    emit(
        sid,
        json!({"type": "agent.session.turn.in_progress", "session_id": sid, "turn_id": turn_id, "turn": turn}),
    );
    for mut m in msgs {
        m["id"] = json!(uid("msg"));
        m["status"] = json!("completed");
        m["turn_id"] = json!(turn_id);
        add_item(app, sid, &m).await;
        emit(
            sid,
            json!({"type": "agent.session.turn.item.added", "session_id": sid, "turn_id": turn_id, "item": m}),
        );
    }
    spawn_step(app, principal, headers, sid, &turn_id);
}

// ── sessions ──

/// Keep only the environment fields that configure the seat's context;
/// the seat works on the caller's own files, so no environment is run.
fn environment(v: &Value) -> Result<Value, String> {
    let ty = v["type"].as_str().unwrap_or("");
    let list = |k: &str| {
        v.get(k)
            .filter(|x| x.is_array())
            .cloned()
            .unwrap_or(json!([]))
    };
    match ty {
        "none" => Ok(json!({"type": "none"})),
        "self_hosted" => {
            let Some(dir) = v["workspace_directory"].as_str() else {
                return Err("environment.workspace_directory is required".into());
            };
            Ok(
                json!({"id": uid("env"), "type": "self_hosted", "workspace_directory": dir,
                "capability_directories": list("capability_directories"), "remote_url": ""}),
            )
        }
        "openai_hosted" => {
            let id = v["environment_id"]
                .as_str()
                .map(String::from)
                .unwrap_or_else(|| uid("env"));
            let net = v
                .get("network")
                .filter(|n| n.is_object())
                .cloned()
                .unwrap_or(json!({"access": "enabled"}));
            let pk = v.get("packages").cloned().unwrap_or(json!({}));
            let arr = |k: &str| {
                pk.get(k)
                    .filter(|x| x.is_array())
                    .cloned()
                    .unwrap_or(json!([]))
            };
            Ok(json!({"id": id, "type": "openai_hosted",
                "capability_directories": list("capability_directories"), "files": list("files"),
                "network": {"access": net["access"].as_str().unwrap_or("enabled"),
                            "allowed_domains": net.get("allowed_domains").filter(|x| x.is_array()).cloned().unwrap_or(json!([]))},
                "packages": {"npm": arr("npm"), "python": arr("python"), "system": arr("system")},
                "plugins": list("plugins"), "skills": list("skills"),
                "container_size": v.get("container_size").cloned().unwrap_or(json!("small")),
                "desktop": v.get("desktop").cloned().unwrap_or(Value::Null)}))
        }
        _ => Err("environment.type must be none, openai_hosted or self_hosted".into()),
    }
}

/// Build a session from a create body.
async fn new_session(app: &AppState, owner: &str, b: &Value) -> Result<Value, Response> {
    let Some(env) = b.get("environment") else {
        return Err(bad("environment is required"));
    };
    let env = environment(env).map_err(|e| bad(&e))?;
    let mut agent = match b.get("agent_id").and_then(|a| a.as_str()) {
        Some(aid) => match of(app, owner, aid, "agent").await {
            Some(s) => {
                let mut a = s.obj;
                if let Some(o) = a.as_object_mut() {
                    for k in ["object", "created_at", "updated_at", "metadata"] {
                        o.remove(k);
                    }
                }
                a
            }
            None => return Err(not_found("agent", aid)),
        },
        None => {
            let mut a = agent_config(&json!({}), None);
            a["id"] = json!(uid("agent"));
            a
        }
    };
    if let Some(over) = b.get("agent").filter(|a| a.is_object()) {
        let id = agent["id"].clone();
        agent = agent_config(over, Some(&agent));
        agent["id"] = id;
    }
    let sid = uid("sess");
    let obj = json!({"id": sid, "object": "agent.session", "agent": agent, "created_at": now(),
        "environment": env, "error": null, "last_active_at": now(), "metadata": str_map(b.get("metadata")),
        "required_actions": [], "status": "idle", "usage": usage(0, 0),
        "vault_ids": b.get("vault_ids").filter(|v| v.is_array()).cloned().unwrap_or(json!([])),
        "review": b.get("review").cloned().unwrap_or(json!("none")),
        "spend_control": b.get("spend_control").and_then(|s| s.get("limit")).filter(|l| !l.is_null())
            .map(|l| json!({"limit": l, "consumed": 0})).unwrap_or(Value::Null)});
    put(app, owner, obj.clone()).await;
    crate::api::webhooks::fire(owner, "agent.session.created", &sid);
    Ok(obj)
}

fn sse(ev: &Value) -> Result<Bytes, std::convert::Infallible> {
    Ok(Bytes::from(format!("data: {ev}\n\n")))
}

/// Follow a session's events. `until_turn`: end once a turn has ended and
/// the session is idle again (or failed); otherwise follow until the
/// caller hangs up.
fn follow(mut rx: broadcast::Receiver<Value>, first: Vec<Value>, until_turn: bool) -> Response {
    let out = async_stream::stream! {
        for e in &first {
            yield sse(e);
        }
        let mut turn_ended = false;
        let mut tick = tokio::time::interval(std::time::Duration::from_secs(15));
        tick.tick().await;
        loop {
            tokio::select! {
                _ = tick.tick() => yield Ok(Bytes::from_static(b": keepalive\n\n")),
                ev = rx.recv() => match ev {
                    Ok(ev) => {
                        let kind = ev["type"].as_str().unwrap_or("").to_string();
                        yield sse(&ev);
                        if kind.starts_with("agent.session.turn.") && (kind.ends_with(".completed") || kind.ends_with(".failed") || kind.ends_with(".cancelled")) {
                            turn_ended = true;
                        }
                        if until_turn && (kind == "agent.session.failed" || (kind == "agent.session.idle" && turn_ended)) {
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => break,
                },
            }
        }
    };
    Response::builder()
        .header("Content-Type", "text/event-stream")
        .header("Cache-Control", "no-cache")
        .body(Body::from_stream(out))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

pub async fn create_session(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let msgs = match input_messages(b.get("input").unwrap_or(&Value::Null)) {
        Ok(m) => m,
        Err(e) => return bad(&e),
    };
    let obj = match new_session(&app, &owner, &b).await {
        Ok(o) => o,
        Err(r) => return r,
    };
    let sid = obj["id"].as_str().unwrap_or("").to_string();
    let rx = subscribe(&sid);
    let stream = b.get("stream").and_then(|s| s.as_bool()) == Some(true);
    let has_input = !msgs.is_empty();
    if has_input {
        start_turn(&app, &principal, &headers, &sid, msgs).await;
    }
    if stream {
        let created =
            json!({"type": "agent.session.created", "event_id": uid("event"), "session": obj});
        let mut first = vec![created];
        if !has_input {
            first.push(
                json!({"type": "agent.session.idle", "event_id": uid("event"), "session": obj}),
            );
            return follow_done(first);
        }
        return follow(rx, first, true);
    }
    Json(session_obj(&app, &owner, &sid).await).into_response()
}

fn follow_done(first: Vec<Value>) -> Response {
    let body: String = first.iter().map(|e| format!("data: {e}\n\n")).collect();
    Response::builder()
        .header("Content-Type", "text/event-stream")
        .body(Body::from(body))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

pub async fn list_sessions(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    let mut v = listed(&app, &principal.agent.id, "agent.session").await;
    if let Some(a) = &q.agent_id {
        v.retain(|s| s["agent"]["id"] == json!(a));
    }
    Json(page(v, &q)).into_response()
}

pub async fn get_session(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match of(&app, &principal.agent.id, &id, "agent.session").await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("session", &id),
    }
}

pub async fn update_session(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &id, "agent.session").await else {
        return not_found("session", &id);
    };
    let mut o = s.obj;
    if let Some(a) = b.get("agent").filter(|a| a.is_object()) {
        let aid = o["agent"]["id"].clone();
        o["agent"] = agent_config(a, Some(&o["agent"]));
        o["agent"]["id"] = aid;
    }
    if let Some(m) = b.get("metadata") {
        o["metadata"] = str_map(Some(m));
    }
    patch(&mut o, &b, &["review"]);
    if let Some(l) = b.get("spend_control").and_then(|s| s.get("limit")) {
        o["spend_control"] = if l.is_null() {
            Value::Null
        } else {
            json!({"limit": l, "consumed": 0})
        };
    }
    app.object.update_object(&id, &|s| s.obj = o.clone()).await;
    Json(o).into_response()
}

pub async fn delete_session(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if of(&app, &principal.agent.id, &id, "agent.session")
        .await
        .is_none()
    {
        return not_found("session", &id);
    }
    abort_running(&id);
    app.object.delete_object(&principal.agent.id, &id).await;
    live().lock().unwrap().remove(&id);
    deleted(&id, "agent.session.deleted")
}

/// `POST /v1/agents/sessions/{id}/events`: messages, tool results, cancel.
pub async fn create_events(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Path(sid): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let Some(events) = b.get("events").and_then(|e| e.as_array()).cloned() else {
        return bad("events is required");
    };
    for ev in events {
        let Some(s) = of(&app, &owner, &sid, "agent.session").await else {
            return not_found("session", &sid);
        };
        match ev["type"].as_str().unwrap_or("") {
            "agent.session.input.message" => {
                if s.obj["status"] != "idle" {
                    return err(
                        StatusCode::CONFLICT,
                        "the session is busy: wait for agent.session.idle, or cancel the turn",
                    );
                }
                let msgs = match input_messages(&ev["input"]) {
                    Ok(m) if !m.is_empty() => m,
                    Ok(_) => return bad("input is empty"),
                    Err(e) => return bad(&e),
                };
                start_turn(&app, &principal, &headers, &sid, msgs).await;
            }
            "agent.session.input.tool_result" => {
                let call_id = ev["call_id"].clone();
                let actions = s.obj["required_actions"]
                    .as_array()
                    .cloned()
                    .unwrap_or_default();
                let Some(action) = actions.iter().find(|a| a["call_id"] == call_id).cloned() else {
                    return bad(&format!("no pending tool call {call_id}"));
                };
                let turn_id = action["turn_id"].as_str().unwrap_or("").to_string();
                let ok = ev["success"].as_bool().unwrap_or(true);
                let item = json!({"id": uid("fco"), "type": "function_call_output", "call_id": call_id,
                    "output": ev.get("output").cloned().unwrap_or(Value::Null),
                    "error": ev.get("error").cloned().unwrap_or(Value::Null),
                    "status": if ok { "completed" } else { "failed" }, "turn_id": turn_id});
                add_item(&app, &sid, &item).await;
                emit(
                    &sid,
                    json!({"type": "agent.session.turn.item.added", "session_id": sid, "turn_id": turn_id, "item": item}),
                );
                let rest: Vec<Value> = actions
                    .into_iter()
                    .filter(|a| a["call_id"] != call_id)
                    .collect();
                let done = rest.is_empty();
                app.object
                    .update_object(&sid, &move |s| {
                        s.obj["required_actions"] = json!(rest.clone());
                        if done {
                            s.obj["status"] = json!("in_progress");
                        }
                        s.obj["last_active_at"] = json!(now());
                    })
                    .await;
                if done {
                    let turn =
                        set_turn(&app, &sid, &turn_id, |t| t["status"] = json!("in_progress"))
                            .await;
                    emit_session(&app, &owner, &sid, "agent.session.in_progress").await;
                    emit(
                        &sid,
                        json!({"type": "agent.session.turn.in_progress", "session_id": sid, "turn_id": turn_id, "turn": turn}),
                    );
                    spawn_step(&app, &principal, &headers, &sid, &turn_id);
                }
            }
            "agent.session.input.cancel" => {
                abort_running(&sid);
                let open = s
                    .history
                    .iter()
                    .rev()
                    .find(|t| {
                        matches!(
                            t["status"].as_str(),
                            Some("queued" | "in_progress" | "waiting")
                        )
                    })
                    .and_then(|t| t["id"].as_str().map(String::from));
                if let Some(tid) = open {
                    let turn = set_turn(&app, &sid, &tid, |t| {
                        t["status"] = json!("cancelled");
                        t["completed_at"] = json!(now());
                    })
                    .await;
                    emit(
                        &sid,
                        json!({"type": "agent.session.turn.cancelled", "session_id": sid, "turn_id": tid, "turn": turn}),
                    );
                }
                app.object
                    .update_object(&sid, &|s| {
                        s.obj["status"] = json!("idle");
                        s.obj["required_actions"] = json!([]);
                    })
                    .await;
                emit_session(&app, &owner, &sid, "agent.session.idle").await;
            }
            "agent.session.input.computer_use_approval_request_result" => {
                return bad("this server's agents do not use the computer, so there is no approval to answer");
            }
            other => return bad(&format!("unsupported event type {other}")),
        }
    }
    StatusCode::NO_CONTENT.into_response()
}

/// `GET /v1/agents/sessions/{id}/events`: the live event stream, opening
/// with the session's current state.
pub async fn stream_events(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(sid): Path<String>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &sid, "agent.session").await else {
        return not_found("session", &sid);
    };
    let rx = subscribe(&sid);
    let kind = match s.obj["status"].as_str().unwrap_or("idle") {
        "in_progress" => "agent.session.in_progress",
        "requires_action" => "agent.session.requires_action",
        "failed" => "agent.session.failed",
        _ => "agent.session.idle",
    };
    follow(
        rx,
        vec![json!({"type": kind, "event_id": uid("event"), "session": s.obj})],
        false,
    )
}

pub async fn list_items(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(sid): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &sid, "agent.session").await else {
        return not_found("session", &sid);
    };
    Json(page(s.input, &q)).into_response()
}

pub async fn list_turns(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(sid): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &sid, "agent.session").await else {
        return not_found("session", &sid);
    };
    Json(page(s.history, &q)).into_response()
}

pub async fn get_turn(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((sid, tid)): Path<(String, String)>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &sid, "agent.session").await else {
        return not_found("session", &sid);
    };
    match s.history.into_iter().find(|t| t["id"] == json!(tid)) {
        Some(t) => Json(t).into_response(),
        None => not_found("turn", &tid),
    }
}

pub async fn list_turn_items(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((sid, tid)): Path<(String, String)>,
    Query(q): Query<ListQuery>,
) -> Response {
    let Some(s) = of(&app, &principal.agent.id, &sid, "agent.session").await else {
        return not_found("session", &sid);
    };
    if !s.history.iter().any(|t| t["id"] == json!(tid)) {
        return not_found("turn", &tid);
    }
    let v: Vec<Value> = s
        .input
        .into_iter()
        .filter(|i| i["turn_id"] == json!(tid))
        .collect();
    Json(page(v, &q)).into_response()
}

/// Lists a session has but this server never fills: traces, artifacts
/// (the seat works on the caller's own files), subagents.
pub async fn empty_list(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(p): Path<HashMap<String, String>>,
) -> Response {
    let sid = p.get("id").cloned().unwrap_or_default();
    if of(&app, &principal.agent.id, &sid, "agent.session")
        .await
        .is_none()
    {
        return not_found("session", &sid);
    }
    Json(
        json!({"object": "list", "data": [], "first_id": null, "last_id": null, "has_more": false}),
    )
    .into_response()
}

/// A subagent, artifact or turn under a subagent: none exist here.
pub async fn none_found(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(p): Path<HashMap<String, String>>,
) -> Response {
    let sid = p.get("id").cloned().unwrap_or_default();
    if of(&app, &principal.agent.id, &sid, "agent.session")
        .await
        .is_none()
    {
        return not_found("session", &sid);
    }
    let (what, id) = match (p.get("art"), p.get("sub")) {
        (Some(a), _) => ("artifact", a.clone()),
        (None, Some(s)) => ("subagent", s.clone()),
        _ => ("object", String::new()),
    };
    not_found(what, &id)
}
