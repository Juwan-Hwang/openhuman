//! Agent Seat — the human seat, opened to agents over plain HTTP.
//!
//! The human side of OpenHuman normally speaks WebSocket: a Flutter client
//! holds a socket open, receives `message.received`, and answers with
//! `reply.send` / `tool.invoke` / `end.turn`. An *agent* sitting in that
//! seat (a remote assistant answering a developer who types into Claude
//! Code or Codex) usually cannot hold a socket: it runs in short bursts,
//! from a shell or an MCP client, and is gone between turns.
//!
//! The seat bridges that gap without a second code path:
//!
//! - On first use it registers a **virtual device** in the same
//!   [`ConnectionRegistry`](crate::ws::registry::ConnectionRegistry) the
//!   WebSocket handler uses, so every event a human device would receive
//!   (messages, tool results, capability updates) lands in a per-seat
//!   queue instead of a socket. Pending backlog is drained into it exactly
//!   as on a WebSocket connect.
//! - `GET /v1/seat/inbox` long-polls that queue with a cursor. Polling with
//!   `after=N` acknowledges everything up to `N`, so a seat that crashes
//!   mid-turn replays what it had not acknowledged instead of losing it.
//! - `POST /v1/seat/send` takes the very same client event JSON a
//!   WebSocket client sends and runs it through the same handler.
//!   `/v1/seat/reply` and `/v1/seat/tool-call` are typed shortcuts.
//! - A seat nobody has polled for [`seat_ttl`] is detached, so the human
//!   correctly reads as offline and the offline/async paths take over.
//!
//! Tool calls proposed from the seat are *proposals*: they travel back to
//! the calling client as OpenAI `tool_calls`, and that client executes
//! them under its own sandbox and permission prompts.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json, Response};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::{Mutex, Notify};
use uuid::Uuid;

use crate::auth::AuthPrincipal;
use crate::storage::AppState;

/// Longest a single long-poll may hold. Kept under the ~100 s idle timeout
/// CDNs apply to quiet HTTP responses.
const MAX_WAIT_SECS: u64 = 90;
/// Default long-poll hold when the caller does not say.
const DEFAULT_WAIT_SECS: u64 = 25;
/// Events kept per seat before the oldest are dropped.
const QUEUE_CAP: usize = 1000;
/// `client_msg_id`s remembered per seat for idempotent sends.
const DEDUP_CAP: usize = 256;
/// Text longer than this is cut in the compact view (full view keeps it).
const COMPACT_TEXT_CHARS: usize = 8000;

/// Detach a seat after this long without a poll (`OPENHUMAN_SEAT_TTL_SECS`).
fn seat_ttl() -> Duration {
    let secs = std::env::var("OPENHUMAN_SEAT_TTL_SECS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|v| *v >= 10)
        .unwrap_or(180);
    Duration::from_secs(secs)
}

struct SeatState {
    queue: VecDeque<(u64, Value)>,
    next_cursor: u64,
    last_poll: Instant,
    seen_ids: VecDeque<String>,
}

struct Seat {
    human_id: String,
    device_id: String,
    state: Mutex<SeatState>,
    notify: Notify,
}

impl Seat {
    async fn push(&self, event: Value) {
        let mut st = self.state.lock().await;
        st.next_cursor += 1;
        let c = st.next_cursor;
        st.queue.push_back((c, event));
        while st.queue.len() > QUEUE_CAP {
            st.queue.pop_front();
        }
        drop(st);
        self.notify.notify_waiters();
    }

    /// Drop acknowledged events and return everything after `after`.
    async fn take_after(&self, after: u64) -> (Vec<(u64, Value)>, u64) {
        let mut st = self.state.lock().await;
        st.last_poll = Instant::now();
        while st.queue.front().map(|(c, _)| *c <= after).unwrap_or(false) {
            st.queue.pop_front();
        }
        let events: Vec<_> = st.queue.iter().cloned().collect();
        (events, st.next_cursor)
    }

    /// Record a `client_msg_id`; `false` when it was already seen.
    async fn first_time(&self, id: &str) -> bool {
        let mut st = self.state.lock().await;
        if st.seen_ids.iter().any(|s| s == id) {
            return false;
        }
        st.seen_ids.push_back(id.to_string());
        while st.seen_ids.len() > DEDUP_CAP {
            st.seen_ids.pop_front();
        }
        true
    }
}

/// All attached seats, keyed by API key id (one seat per key).
#[derive(Default)]
struct SeatHub {
    seats: Mutex<HashMap<String, Arc<Seat>>>,
}

fn hub() -> &'static SeatHub {
    static HUB: OnceLock<SeatHub> = OnceLock::new();
    HUB.get_or_init(SeatHub::default)
}

/// Get the seat for this key, attaching a virtual device on first use.
async fn attach(app: &AppState, p: &AuthPrincipal) -> Arc<Seat> {
    let key = p.api_key.id.clone();
    let mut seats = hub().seats.lock().await;
    if let Some(s) = seats.get(&key) {
        return s.clone();
    }

    let seat = Arc::new(Seat {
        human_id: p.human.id.clone(),
        device_id: format!("seat_{}", Uuid::now_v7().simple()),
        state: Mutex::new(SeatState {
            queue: VecDeque::new(),
            next_cursor: 0,
            last_poll: Instant::now(),
            seen_ids: VecDeque::new(),
        }),
        notify: Notify::new(),
    });
    seats.insert(key.clone(), seat.clone());
    drop(seats);

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    app.connections
        .register(&seat.human_id, &seat.device_id, tx.clone())
        .await;

    // Pump: everything the registry fans out to this "device" becomes a
    // queued event.
    let pump_seat = seat.clone();
    tokio::spawn(async move {
        while let Some(raw) = rx.recv().await {
            let v = serde_json::from_str::<Value>(&raw).unwrap_or(Value::String(raw));
            pump_seat.push(v).await;
        }
    });

    // Same backlog + presence handling as a WebSocket connect.
    crate::ws::handler::drain_pending_messages(app, &seat.human_id, &tx).await;
    // The "human expert is online" notice is injected into the caller's
    // assistant text. For an agent seat that re-attaches every few minutes
    // it just pollutes transcripts, so it is opt-in here.
    if matches!(
        std::env::var("OPENHUMAN_SEAT_ANNOUNCE").as_deref(),
        Ok("1") | Ok("true") | Ok("on")
    ) {
        crate::ws::handler::announce_online(app, &seat.human_id).await;
    }

    // Reaper: detach once nobody polls, so the human reads as offline.
    let reap_app = app.clone();
    let reap_seat = seat.clone();
    tokio::spawn(async move {
        let ttl = seat_ttl();
        loop {
            tokio::time::sleep(Duration::from_secs(10)).await;
            let idle = reap_seat.state.lock().await.last_poll.elapsed();
            if idle > ttl {
                hub().seats.lock().await.remove(&key);
                reap_app
                    .connections
                    .unregister(&reap_seat.human_id, &reap_seat.device_id)
                    .await;
                tracing::info!("Seat detached after {:?} idle: key={}", idle, key);
                break;
            }
        }
    });

    tracing::info!(
        "Seat attached: human_id={}, device_id={}",
        seat.human_id,
        seat.device_id
    );
    seat
}

fn err(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        Json(json!({ "error": { "code": code, "message": message } })),
    )
        .into_response()
}

fn truncate(s: &str, max: usize) -> (String, bool) {
    if s.chars().count() <= max {
        (s.to_string(), false)
    } else {
        (s.chars().take(max).collect(), true)
    }
}

/// Flatten one queued event for an agent reader.
///
/// Compact keeps what a turn needs (who, what, which conversation) and
/// swaps a capability flood for the list of tool names; `full` returns the
/// event exactly as a WebSocket client would have seen it.
fn render(cursor: u64, ev: &Value, full: bool) -> Value {
    if full {
        return json!({ "cursor": cursor, "event": ev });
    }
    let ty = ev.get("event_type").and_then(|v| v.as_str()).unwrap_or("");
    let conv = ev.get("conversation_id").cloned().unwrap_or(Value::Null);
    let data = ev.get("data").cloned().unwrap_or(Value::Null);
    let mut out = json!({ "cursor": cursor, "type": ty, "conversation_id": conv });
    match ty {
        "message.received" => {
            let text = data.get("text").and_then(|v| v.as_str()).unwrap_or("");
            let (t, cut) = truncate(text, COMPACT_TEXT_CHARS);
            out["text"] = Value::String(t);
            if cut {
                out["truncated"] = Value::Bool(true);
            }
            out["message_id"] = data.get("message_id").cloned().unwrap_or(Value::Null);
            out["from"] = data.get("sender_name").cloned().unwrap_or(Value::Null);
            if let Some(imgs) = data.get("images").and_then(|v| v.as_array()) {
                out["image_count"] = json!(imgs.len());
            }
        }
        "capability.updated" => {
            let names: Vec<Value> = data
                .get("capabilities")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|c| c.get("id").cloned()).collect())
                .unwrap_or_default();
            out["agent_id"] = data.get("agent_id").cloned().unwrap_or(Value::Null);
            out["tools"] = Value::Array(names);
        }
        "tool.result" => {
            for k in ["invocation_id", "tool_id", "status", "error"] {
                out[k] = data.get(k).cloned().unwrap_or(Value::Null);
            }
            let output = data.get("output").cloned().unwrap_or(Value::Null);
            let s = match &output {
                Value::String(s) => s.clone(),
                Value::Null => String::new(),
                other => other.to_string(),
            };
            let (t, cut) = truncate(&s, COMPACT_TEXT_CHARS);
            out["output"] = Value::String(t);
            if cut {
                out["truncated"] = Value::Bool(true);
            }
        }
        _ => {
            out["data"] = data;
        }
    }
    out
}

// ── GET /v1/seat/inbox ──

#[derive(Debug, Deserialize)]
pub struct InboxQuery {
    #[serde(default)]
    after: u64,
    wait: Option<u64>,
    #[serde(default)]
    view: Option<String>,
    /// Only return events of these types (comma separated).
    #[serde(default)]
    types: Option<String>,
}

/// Long-poll the seat's queue. Returns as soon as anything newer than
/// `after` exists, or empty when `wait` runs out.
pub async fn inbox(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<InboxQuery>,
) -> Response {
    let seat = attach(&app, &principal).await;
    let wait = Duration::from_secs(q.wait.unwrap_or(DEFAULT_WAIT_SECS).min(MAX_WAIT_SECS));
    let deadline = Instant::now() + wait;
    let full = q.view.as_deref() == Some("full");
    let filter: Option<Vec<String>> = q
        .types
        .as_ref()
        .map(|t| t.split(',').map(|s| s.trim().to_string()).collect());

    loop {
        let notified = seat.notify.notified();
        let (events, latest) = seat.take_after(q.after).await;
        let events: Vec<_> = events
            .into_iter()
            .filter(|(_, ev)| match &filter {
                None => true,
                Some(f) => ev
                    .get("event_type")
                    .and_then(|v| v.as_str())
                    .map(|t| f.iter().any(|x| x == t))
                    .unwrap_or(false),
            })
            .collect();
        let now = Instant::now();
        if !events.is_empty() || now >= deadline {
            let rendered: Vec<Value> = events.iter().map(|(c, e)| render(*c, e, full)).collect();
            let cursor = events.last().map(|(c, _)| *c).unwrap_or(q.after);
            // Only this seat's own open turns: never leak other humans'
            // conversation ids.
            let mut waiting = Vec::new();
            for id in app.reply.conversations_with_waiters().await {
                let mine = app
                    .conversation
                    .get(&id)
                    .await
                    .and_then(|c| c.human_id().map(|h| h == principal.human.id))
                    .unwrap_or(false);
                if mine {
                    waiting.push(id);
                }
            }
            return Json(json!({
                "cursor": cursor,
                "latest": latest,
                "events": rendered,
                "waiting_turns": waiting,
            }))
            .into_response();
        }
        let _ = tokio::time::timeout(deadline - now, notified).await;
    }
}

// ── POST /v1/seat/send ──

/// Send a raw client event, the same JSON a WebSocket client sends
/// (`{"event_type":"reply.send", ...}`). Optional top-level
/// `client_msg_id` makes the send idempotent.
pub async fn send(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(body): Json<Value>,
) -> Response {
    let seat = attach(&app, &principal).await;
    if let Some(id) = body.get("client_msg_id").and_then(|v| v.as_str()) {
        if !seat.first_time(id).await {
            return Json(json!({ "ok": true, "duplicate": true })).into_response();
        }
    }
    let raw = body.to_string();
    if let Err(e) = crate::ws::protocol::ClientMessage::from_json(&raw) {
        return err(StatusCode::BAD_REQUEST, "invalid_event", &e.to_string());
    }
    crate::ws::handler::handle_client_message(
        &raw,
        &app,
        &principal.human.id,
        &principal.agent.id,
    )
    .await;
    Json(json!({ "ok": true })).into_response()
}

// ── POST /v1/seat/reply ──

#[derive(Debug, Deserialize)]
pub struct ReplyBody {
    conversation_id: String,
    text: String,
    #[serde(default)]
    invocation_id: Option<String>,
    /// Close the turn after this reply (default true: one reply, one turn).
    #[serde(default = "yes")]
    end_turn: bool,
    #[serde(default)]
    client_msg_id: Option<String>,
}

fn yes() -> bool {
    true
}

/// Reply with text, and by default end the turn so the caller's request
/// finishes with `finish_reason: stop`.
pub async fn reply(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<ReplyBody>,
) -> Response {
    let seat = attach(&app, &principal).await;
    if let Some(id) = &b.client_msg_id {
        if !seat.first_time(id).await {
            return Json(json!({ "ok": true, "duplicate": true })).into_response();
        }
    }
    let had_waiter = app.reply.has_waiter(&b.conversation_id).await;
    let ev = json!({
        "event_type": "reply.send",
        "conversation_id": b.conversation_id,
        "text": b.text,
        "invocation_id": b.invocation_id,
    });
    crate::ws::handler::handle_client_message(
        &ev.to_string(),
        &app,
        &principal.human.id,
        &principal.agent.id,
    )
    .await;
    if b.end_turn && had_waiter {
        let end = json!({ "event_type": "end.turn", "conversation_id": b.conversation_id });
        crate::ws::handler::handle_client_message(
            &end.to_string(),
            &app,
            &principal.human.id,
            &principal.agent.id,
        )
        .await;
    }
    Json(json!({
        "ok": true,
        "live": had_waiter,
        "turn_ended": b.end_turn && had_waiter,
    }))
    .into_response()
}

// ── POST /v1/seat/tool-call ──

#[derive(Debug, Deserialize)]
pub struct ToolCallBody {
    conversation_id: String,
    tool: String,
    #[serde(default)]
    input: Value,
    /// Words to show alongside the call.
    #[serde(default)]
    text: Option<String>,
    /// Hold up to this many seconds for the `tool.result` (0 = return now).
    #[serde(default)]
    wait: Option<u64>,
    #[serde(default)]
    client_msg_id: Option<String>,
}

/// Propose a tool call to the calling client. The client executes it under
/// its own sandbox; with `wait` the result is returned inline when it
/// arrives in time, otherwise poll the inbox for `tool.result`.
pub async fn tool_call(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<ToolCallBody>,
) -> Response {
    let seat = attach(&app, &principal).await;
    if let Some(id) = &b.client_msg_id {
        if !seat.first_time(id).await {
            return Json(json!({ "ok": true, "duplicate": true })).into_response();
        }
    }
    if app
        .capability
        .get_capability(&principal.agent.id, &b.tool)
        .await
        .is_none()
    {
        let tools: Vec<String> = app
            .capability
            .get_capabilities(&principal.agent.id)
            .await
            .into_iter()
            .map(|c| c.id)
            .collect();
        return (
            StatusCode::NOT_FOUND,
            Json(json!({ "error": {
                "code": "tool_not_found",
                "message": format!("The caller has not declared a tool named '{}'.", b.tool),
                "available": tools,
            }})),
        )
            .into_response();
    }

    let invocation_id = format!("call_{}", Uuid::now_v7().simple());
    let input = if b.input.is_null() { json!({}) } else { b.input };
    let ev = json!({
        "event_type": "tool.invoke",
        "conversation_id": b.conversation_id,
        "invocation_id": invocation_id,
        "tool_id": b.tool,
        "input": input,
        "text": b.text,
    });
    let start_cursor = seat.state.lock().await.next_cursor;
    crate::ws::handler::handle_client_message(
        &ev.to_string(),
        &app,
        &principal.human.id,
        &principal.agent.id,
    )
    .await;

    let wait = Duration::from_secs(b.wait.unwrap_or(0).min(MAX_WAIT_SECS));
    let deadline = Instant::now() + wait;
    loop {
        let notified = seat.notify.notified();
        {
            let st = seat.state.lock().await;
            let hit = st.queue.iter().find(|(c, e)| {
                *c > start_cursor
                    && e.get("event_type").and_then(|v| v.as_str()) == Some("tool.result")
                    && e.pointer("/data/invocation_id").and_then(|v| v.as_str())
                        == Some(invocation_id.as_str())
            });
            if let Some((c, e)) = hit {
                return Json(json!({
                    "ok": true,
                    "invocation_id": invocation_id,
                    "result": render(*c, e, false),
                }))
                .into_response();
            }
        }
        let now = Instant::now();
        if now >= deadline {
            return Json(json!({
                "ok": true,
                "invocation_id": invocation_id,
                "result": null,
                "hint": "Result not back yet; poll /v1/seat/inbox?types=tool.result",
            }))
            .into_response();
        }
        let _ = tokio::time::timeout(deadline - now, notified).await;
    }
}

// ── GET /v1/seat/capabilities ──

#[derive(Debug, Deserialize)]
pub struct CapQuery {
    #[serde(default)]
    view: Option<String>,
}

/// The tools the calling client declared, and its context.
pub async fn capabilities(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<CapQuery>,
) -> Response {
    let caps = app.capability.get_capabilities(&principal.agent.id).await;
    let ctx = app.context.get_context(&principal.agent.id).await;
    let tools: Vec<Value> = if q.view.as_deref() == Some("full") {
        caps.iter().map(|c| json!(c)).collect()
    } else {
        caps.iter()
            .map(|c| {
                let d = c.description.clone().unwrap_or_default();
                let (d, _) = truncate(&d, 200);
                json!({ "id": c.id, "description": d })
            })
            .collect()
    };
    Json(json!({
        "agent_id": principal.agent.id,
        "agent_name": principal.agent.name,
        "tools": tools,
        "context": ctx,
    }))
    .into_response()
}
