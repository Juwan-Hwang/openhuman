//! `POST /v1/chat/completions` — OpenAI Chat Completions compatible endpoint.
//!
//! Phase 6: Realtime message routing.
//! Phase 7.3: Human-triggered tool_calls response.
//!
//! # Reply Payload Modes
//!
//! The Human Console can send two types of reply via `reply.send`:
//!
//! 1. **Text reply** — plain text string → `ChatCompletionResponse::from_human_reply`
//! 2. **Tool call reply** — JSON with `__tool_call__` marker → `ChatCompletionResponse::from_tool_call`
//!
//! The tool call format (sent by Human Console via WS `reply.send`):
//! ```json
//! {
//!   "__tool_call__": true,
//!   "tool_name": "Bash",
//!   "arguments": {"command": "echo hello"}
//! }
//! ```
//!
//! This is an internal wire format between Human Console and OpenHuman.
//! The Agent never sees it — the Agent receives a standard OpenAI
//! `tool_calls` response.

use std::collections::HashMap;
use std::time::Duration;

use axum::body::{Body, Bytes};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event as SseEvent, KeepAlive, Sse};
use axum::response::{IntoResponse, Json, Response};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::time::interval;
use uuid::Uuid;

use crate::async_reply::merge_window;
use crate::auth::AuthPrincipal;
use crate::model::content::ContentBlock;
use crate::model::identity::ParticipantRef;
use crate::model::message::{Message, MessageStatus};
use crate::openai_compat::{
    ChatCompletionChunk, ChatCompletionRequest, ChatCompletionResponse, ToolCallSpec,
};
use crate::profile::AgentProfile;
use crate::storage::AppState;

// ── Reply payload parsing ──

/// Parsed reply from the Human Console — text, a tool call, or an
/// end-of-turn signal.
#[derive(Debug, Clone)]
pub(crate) enum HumanReply {
    /// Plain text reply from the human.
    ///
    /// `ended` says whether the human also closed the turn. Multi-turn
    /// streaming keeps the SSE stream open across replies, so plain prose
    /// waits for more unless an explicit end-of-turn accompanied it.
    Text { text: String, ended: bool },
    /// One or more tool calls — the human wants the agent to execute them.
    ///
    /// A `Vec` because a human may tap several tools before the turn
    /// closes; OpenAI models that as one assistant message with an array of
    /// calls, which is what lets a client run them in parallel.
    ToolCalls {
        calls: Vec<ToolCallRequest>,
        /// Words the human said alongside the call(s).
        ///
        /// OpenAI allows one assistant message to carry `content` *and*
        /// `tool_calls` at the same time. Emitting `content: null` whenever
        /// a tool is involved silently discards whatever the human typed —
        /// "run this and tell them I'm here" loses the second half.
        text: Option<String>,
    },
    /// End-of-turn signal — the human explicitly closed the turn.
    ///
    /// Terminates the SSE stream with a normal `finish_reason: stop`.
    EndTurn,
}

/// A single tool call the human asked for.
#[derive(Debug, Clone)]
pub(crate) struct ToolCallRequest {
    pub tool_name: String,
    pub arguments: Value,
    /// Correlation id from the originating `tool.invoke` message.
    ///
    /// Present when the call was triggered from the Human Console's tool
    /// panel (WS `tool.invoke`). `None` for the legacy `__tool_call__`
    /// payload. Used to pair a later `tool.result` back to this call.
    pub invocation_id: Option<String>,
}

/// Wire sentinel for the end-of-turn signal delivered via the reply channel.
const END_TURN_SIGNAL: &str = "__END_TURN__";

/// Take whatever else arrives inside `window`.
///
/// Used after the first payload of a turn has already been received. Stops
/// early on an explicit `end.turn` — holding a turn open after the human
/// asked to close it would only add latency.
///
/// The `end.turn` is kept in the returned payloads rather than discarded:
/// it closes the collection window *and* closes the turn, and dropping it
/// would leave the turn waiting forever for an end that already arrived.
async fn collect_rest(
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<String>,
    window: Duration,
) -> Vec<String> {
    if window.is_zero() {
        return Vec::new();
    }

    let mut out = Vec::new();
    // Intentionally a `loop`, not `while let`: the timeout arm and the
    // channel-closed arm both break with different meanings, and folding
    // them into a while-let condition hides that.
    #[allow(clippy::while_let_loop)]
    loop {
        match tokio::time::timeout(window, rx.recv()).await {
            Ok(Some(payload)) => {
                let closed = payload.trim() == END_TURN_SIGNAL;
                out.push(payload);
                if closed {
                    break;
                }
            }
            // Window elapsed with nothing more, or the channel went away.
            Ok(None) | Err(_) => break,
        }
    }
    out
}

/// Fold everything collected in one turn into a single reply.
///
/// Prose is joined in order; tool calls keep their own ids so each can be
/// answered separately with `role: "tool"`.
fn merge_replies(payloads: &[String]) -> HumanReply {
    let mut prose: Vec<String> = Vec::new();
    let mut calls: Vec<ToolCallRequest> = Vec::new();
    let mut ended = false;

    for payload in payloads {
        match parse_reply(payload) {
            HumanReply::Text { text: t, .. } => {
                if !t.trim().is_empty() {
                    prose.push(t);
                }
            }
            HumanReply::ToolCalls { calls: mut c, text } => {
                if let Some(t) = text {
                    if !t.trim().is_empty() {
                        prose.push(t);
                    }
                }
                calls.append(&mut c);
            }
            HumanReply::EndTurn => {
                ended = true;
            }
        }
    }

    if !calls.is_empty() {
        let text = prose.join("\n\n").trim().to_string();
        return HumanReply::ToolCalls {
            calls,
            text: if text.is_empty() { None } else { Some(text) },
        };
    }

    let text = prose.join("\n\n");
    if text.trim().is_empty() {
        HumanReply::EndTurn
    } else {
        HumanReply::Text { text, ended }
    }
}

/// Wire format for tool call replies sent via `reply.send`.
///
/// The Human Console sends this JSON object as the `text` field of
/// a `reply.send` WS message. OpenHuman detects the `__tool_call__`
/// marker and converts it to a standard OpenAI `tool_calls` response.
#[derive(Debug, Deserialize)]
struct ToolCallPayload {
    #[serde(rename = "__tool_call__")]
    is_tool_call: bool,
    tool_name: String,
    arguments: Value,
}

/// Wire format for tool invocations sent by the Human Console via WS
/// `tool.invoke`, and relayed onto the reply channel by
/// [`crate::ws::handler::handle_tool_invoke`].
///
/// The Human Console sends this when the human taps a tool in the tool
/// panel instead of typing a reply. It lands on the reply channel of the
/// conversation whose SSE request is currently suspended, so the waiting
/// agent turn resolves with a real `tool_calls` response.
///
/// ```json
/// {
///   "type": "tool.invoke",
///   "invocation_id": "inv_01H...",
///   "tool_id": "Bash",
///   "input": {"command": "echo hello"}
/// }
/// ```
///
/// **Why this must be parsed here:** before this existed, the payload fell
/// through to [`HumanReply::Text`], so the agent received the JSON as a
/// quoted string with `finish_reason: "stop"`. OpenAI-compatible clients
/// only act on a `tool_calls` array, so the tool would never run.
///
/// `text` is optional companion prose: the console sends it when the human
/// typed something in the same breath as tapping the tool.
///
/// ```json
/// {
///   "type": "tool.invoke",
///   "invocation_id": "inv_01H...",
///   "tool_id": "Bash",
///   "input": {"command": "echo hello"},
///   "text": "run this and tell them I'm here"
/// }
/// ```
#[derive(Debug, Deserialize)]
struct ToolInvokePayload {
    #[serde(rename = "type")]
    kind: String,
    invocation_id: Option<String>,
    tool_id: String,
    /// Companion prose to surface as `content` alongside `tool_calls`.
    #[serde(default)]
    text: Option<String>,
    /// Tool arguments. Defaults to an empty object rather than `null`, so a
    /// tool invoked with no input still serialises to valid JSON arguments
    /// (`{}`) in the OpenAI `function.arguments` string.
    #[serde(default = "empty_json_object")]
    input: Value,
}

fn empty_json_object() -> Value {
    Value::Object(Default::default())
}

/// Discriminator value marking a [`ToolInvokePayload`].
const TOOL_INVOKE_TYPE: &str = "tool.invoke";

/// Parse a reply payload string into either a text reply or a tool call.
///
/// Recognized shapes, in priority order:
///
/// 1. `__END_TURN__` sentinel → [`HumanReply::EndTurn`]
/// 2. `{"type": "tool.invoke", ...}` — relayed WS `tool.invoke` →
///    [`HumanReply::ToolCall`] with the `invocation_id` preserved
/// 3. `{"__tool_call__": true, ...}` — legacy `reply.send` tool payload →
///    [`HumanReply::ToolCall`] with no `invocation_id`
///
/// Anything else is treated as plain human text.
/// Parse a completed turn, which may be a single payload or a JSON array.
///
/// A merged turn travels as an array of the payloads the human sent inside
/// the merge window, so prose and tool calls can be recombined here rather
/// than being split across responses. A lone payload is unaffected.
pub(crate) fn parse_turn(payload: &str) -> HumanReply {
    if let Ok(Value::Array(items)) = serde_json::from_str::<Value>(payload) {
        if items.len() > 1 {
            let payloads: Vec<String> = items
                .iter()
                .map(|v| match v {
                    Value::String(s) => s.clone(),
                    other => other.to_string(),
                })
                .collect();
            return merge_replies(&payloads);
        }
    }
    parse_reply(payload)
}

pub(crate) fn parse_reply(payload: &str) -> HumanReply {
    // End-of-turn sentinel — highest priority check.
    if payload.trim() == END_TURN_SIGNAL {
        return HumanReply::EndTurn;
    }
    if payload.trim_start().starts_with('{') {
        // Tool invocation relayed from the Human Console's tool panel.
        // Must be checked BEFORE the generic text fallback, otherwise the
        // JSON is handed to the agent as a quoted string and no tool runs.
        if let Ok(invoke) = serde_json::from_str::<ToolInvokePayload>(payload) {
            if invoke.kind == TOOL_INVOKE_TYPE {
                let text = invoke.text.filter(|t| !t.trim().is_empty());
                return HumanReply::ToolCalls {
                    calls: vec![ToolCallRequest {
                        tool_name: invoke.tool_id,
                        arguments: invoke.input,
                        invocation_id: invoke.invocation_id,
                    }],
                    text,
                };
            }
        }
        if let Ok(tc) = serde_json::from_str::<ToolCallPayload>(payload) {
            if tc.is_tool_call {
                return HumanReply::ToolCalls {
                    calls: vec![ToolCallRequest {
                        tool_name: tc.tool_name,
                        arguments: tc.arguments,
                        invocation_id: None,
                    }],
                    text: None,
                };
            }
        }
    }
    HumanReply::Text {
        text: payload.to_string(),
        ended: false,
    }
}

// ── Conversation scoping ──

/// Resolve which conversation an inbound request belongs to.
///
/// The OpenAI Chat Completions API is stateless — agents replay the whole
/// transcript on every turn and carry no session identifier of their own.
/// Without an explicit scoping dimension every chat window opened with the
/// same API key therefore landed in one shared conversation.
///
/// Resolution order (first non-empty wins):
///
/// 1. `x-openhuman-conversation-id` / `x-conversation-id` header
/// 2. `conversation` field in the body — `"conv_x"` or `{"id": "conv_x"}`
/// 3. `x-openhuman-session-id` / `x-session-id` header
/// 4. `user` field in the body
/// 5. `metadata.conversation_id` / `metadata.session_id`
/// 6. SHA-256 fingerprint of the system prompt — agents that change project
///    or mode change their prompt, so this separates those threads
/// 7. Client fingerprint — a digest of stable per-client headers, so two
///    unidentified callers still land in distinct conversations
///
/// Each source is namespaced with a prefix so an agent's `user` value can
/// never collide with a header-derived id of the same string.
fn resolve_session_key(
    headers: &HeaderMap,
    req: &ChatCompletionRequest,
    system_prompt: Option<&str>,
) -> String {
    /// Pull a trimmed, non-empty header value (or `None`).
    fn header_value<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
        let v = headers.get(name)?.to_str().ok()?.trim();
        if v.is_empty() {
            None
        } else {
            Some(v)
        }
    }

    // 1. Explicit conversation id header — the most reliable signal.
    for name in ["x-openhuman-conversation-id", "x-conversation-id"] {
        if let Some(v) = header_value(headers, name) {
            return format!("hdr:{}", v);
        }
    }

    // 2. Conversation handle in the request body (Responses-API style).
    if let Some(conv) = &req.conversation {
        let id = conv.id().trim();
        if !id.is_empty() {
            return format!("cnv:{}", id);
        }
    }

    // 3. Generic session header.
    for name in ["x-openhuman-session-id", "x-session-id"] {
        if let Some(v) = header_value(headers, name) {
            return format!("ses:{}", v);
        }
    }

    // 4. OpenAI `user` field.
    if let Some(u) = &req.user {
        let u = u.trim();
        if !u.is_empty() {
            return format!("usr:{}", u);
        }
    }

    // 5. Caller-supplied metadata.
    if let Some(md) = &req.metadata {
        for k in [
            "conversation_id",
            "conversationId",
            "session_id",
            "sessionId",
        ] {
            if let Some(v) = md.get(k).and_then(|v| v.as_str()) {
                let v = v.trim();
                if !v.is_empty() {
                    return format!("meta:{}", v);
                }
            }
        }
    }

    // 6. System-prompt fingerprint — distinguishes project/mode switches.
    //
    //    Scoped by client as well: two different agents sharing a system
    //    prompt (a CLI, an IDE extension, a desktop app) must not land in
    //    one conversation, because they would then also share one outbound
    //    queue and a tool call issued in one would be collected by a
    //    request from the other.
    if let Some(p) = system_prompt {
        if !p.trim().is_empty() {
            return format!(
                "prm:{}:{}",
                prompt_fingerprint(p),
                client_fingerprint(headers)
            );
        }
    }

    // 7. Client fingerprint — the last resort.
    //
    //    Falling through to a single global `"default"` put every
    //    unidentified caller in one conversation. That is not a benign
    //    collision: undelivered replies are queued per conversation, so one
    //    client's parked tool call gets handed to whichever other client
    //    happens to ask next. Distinct callers need distinct conversations
    //    even when they say nothing about who they are.
    format!("cli:{}", client_fingerprint(headers))
}

/// Short, stable digest identifying the calling client.
///
/// Derived from headers a client sends consistently on every request, so the
/// same caller keeps the same conversation while different callers do not
/// collide. Not a security boundary — only a disambiguator.
fn client_fingerprint(headers: &HeaderMap) -> String {
    use sha2::{Digest, Sha256};

    fn value<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
        headers
            .get(name)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .trim()
    }

    let seed = format!(
        "{}\u{1f}{}\u{1f}{}",
        value(headers, "user-agent"),
        value(headers, "accept-language"),
        value(headers, "x-stainless-arch"),
    );
    let digest = Sha256::digest(seed.as_bytes());
    hex::encode(&digest[..6])
}

/// The acknowledgement streamed to the agent before the human answers.
///
/// Presence goes both ways: an offline human is told via push, but the
/// caller sitting on an open request gets nothing either way unless we say
/// something. `None` disables the notice entirely.
///
/// The notice is wrapped in `[OpenHuman ...]` markers so agents can
/// recognize and filter it: it is transport status, not the human's reply,
/// and must not be treated as conversation content.
fn status_notice(is_online: bool) -> Option<String> {
    if is_online {
        std::env::var("OPENHUMAN_ONLINE_MESSAGE")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .or_else(|| {
                if std::env::var("OPENHUMAN_ACK_ONLINE")
                    .map(|v| v.trim() == "0" || v.trim().eq_ignore_ascii_case("false"))
                    .unwrap_or(false)
                {
                    None
                } else {
                    Some(
                        "[OpenHuman 提示]: 人类专家当前在线，消息已送达，正在等待回复...\n\n"
                            .to_string(),
                    )
                }
            })
    } else {
        Some(
            std::env::var("OPENHUMAN_OFFLINE_MESSAGE")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| {
                    "[OpenHuman 提示]: 人类专家当前处于离线状态，已发送待办通知至移动端。本会话保持等待中，请稍候回复...\n\n"
                        .to_string()
                }),
        )
    }
}

/// Infer a MIME type for an image reference.
///
/// Handles the `data:` URLs agents send for inline images, which is the
/// common case — a bare `https://...` may or may not end in an extension,
/// and guessing wrong only affects how the console labels the attachment.
fn guess_image_type(url: &str) -> String {
    if let Some(rest) = url.strip_prefix("data:") {
        let mime = rest.split(';').next().unwrap_or("").trim();
        if !mime.is_empty() {
            return mime.to_string();
        }
    }
    let lower = url.to_lowercase();
    for (ext, mime) in [
        (".png", "image/png"),
        (".jpg", "image/jpeg"),
        (".jpeg", "image/jpeg"),
        (".gif", "image/gif"),
        (".webp", "image/webp"),
        (".bmp", "image/bmp"),
        (".svg", "image/svg+xml"),
    ] {
        if lower.split('?').next().unwrap_or("").ends_with(ext) {
            return mime.to_string();
        }
    }
    "image/*".to_string()
}

/// First 16 hex chars of the SHA-256 of a system prompt.
///
/// Not a security boundary — it only needs to be stable across identical
/// prompts and different across distinct ones, which is why real SHA-256 is
/// used instead of `DefaultHasher` (whose output is not stable across
/// process restarts, and would silently fork conversations on every deploy).
fn prompt_fingerprint(prompt: &str) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(prompt.as_bytes());
    hex::encode(&digest[..8])
}

// ── Inbound message processing ──

/// Inbound → internal mapping.
///
/// Extracts `system` messages as conversation metadata and stores
/// `user` messages as `Message{sender=AgentIdentity}`.
/// `assistant` messages are treated as context replay (skipped).
/// `tool` messages are stored with `tool_call_id` metadata.
fn process_inbound_messages(
    req: &ChatCompletionRequest,
    principal: &AuthPrincipal,
    conversation_id: &str,
    client_type: &crate::profile::ClientType,
) -> (Option<String>, Vec<Message>) {
    let mut system_prompt: Option<String> = None;
    let mut messages = Vec::new();
    let now = Utc::now();

    // ── Deduplication strategy ──
    //
    // WorkBuddy (and most AI tools) send the FULL conversation history
    // with every request — all previous user/assistant messages are
    // replayed. If we push every user message to the human timeline,
    // old messages will appear duplicated on every new request.
    //
    // Solution: find the LAST user message in the batch — that's the
    // only one that represents new input from the agent. All earlier
    // user messages have already been delivered in prior requests.
    //
    // Edge case: if there's only 1 user message, push it (first turn).
    let last_user_idx = req
        .messages
        .iter()
        .rposition(|m| m.role == crate::openai_compat::ChatRole::User);

    for (idx, msg) in req.messages.iter().enumerate() {
        match msg.role {
            crate::openai_compat::ChatRole::System => {
                let text = msg.content.to_text();
                match &mut system_prompt {
                    Some(existing) => {
                        existing.push('\n');
                        existing.push_str(&text);
                    }
                    None => system_prompt = Some(text),
                }
            }
            crate::openai_compat::ChatRole::User => {
                // Only push the LAST user message — earlier ones are
                // conversation history that was already delivered.
                if Some(idx) != last_user_idx {
                    continue;
                }

                // Peel the agent wrapper off before anything reaches the
                // timeline. Per-agent normalizers (see `normalize.rs`) know
                // each family's envelope tag and noise blocks; the text that
                // survives is what the human actually reads.
                let clean_text =
                    crate::normalize::normalize_user_message(client_type, &msg.content);

                // Vision input: carry the images through so the human can
                // actually see what the question is about.
                let images = msg.content.image_urls();
                let message = Message {
                    id: format!("msg_{}", Uuid::now_v7().simple()),
                    conversation_id: conversation_id.to_string(),
                    sender: ParticipantRef::agent_named(&principal.agent.id, &principal.agent.name),
                    content: ContentBlock::text(&clean_text),
                    attachments: images
                        .iter()
                        .enumerate()
                        .map(|(i, url)| crate::model::content::Attachment {
                            id: format!("att_{}_{}", i, Uuid::now_v7().simple()),
                            filename: format!("image-{}.png", i + 1),
                            content_type: guess_image_type(url),
                            size_bytes: url.len() as u64,
                            url: url.clone(),
                        })
                        .collect(),
                    metadata: {
                        let mut m = HashMap::new();
                        m.insert("openai_role".to_string(), Value::String("user".to_string()));
                        if !images.is_empty() {
                            m.insert(
                                "images".to_string(),
                                Value::Array(
                                    images.iter().map(|u| Value::String(u.clone())).collect(),
                                ),
                            );
                        }
                        m
                    },
                    status: MessageStatus::Pending,
                    visibility: crate::model::message::MessageVisibility::HumanVisible,
                    created_at: now,
                };
                messages.push(message);
            }
            crate::openai_compat::ChatRole::Assistant => {
                // Context replay — skip for MVP.
            }
            crate::openai_compat::ChatRole::Tool => {
                // Tool execution result from the agent.
                let text = msg.content.to_text();
                let tool_call_id = msg.tool_call_id.clone();

                // [tool_result] debug logging
                tracing::info!(
                    tool_call_id = %tool_call_id.as_deref().unwrap_or("unknown"),
                    content_len = text.len(),
                    "[tool_result] received from agent"
                );

                let message = Message {
                    id: format!("msg_{}", Uuid::now_v7().simple()),
                    conversation_id: conversation_id.to_string(),
                    sender: ParticipantRef::agent_named(&principal.agent.id, &principal.agent.name),
                    content: ContentBlock::text(text),
                    attachments: Vec::new(),
                    metadata: {
                        let mut m = HashMap::new();
                        m.insert("openai_role".to_string(), Value::String("tool".to_string()));
                        if let Some(ref id) = tool_call_id {
                            m.insert("tool_call_id".to_string(), Value::String(id.clone()));
                        }
                        m
                    },
                    status: MessageStatus::Pending,
                    visibility: crate::model::message::MessageVisibility::InternalOnly,
                    created_at: now,
                };
                messages.push(message);
            }
        }
    }

    (system_prompt, messages)
}

/// Push inbound messages to the human's WebSocket connections.
fn push_messages_to_human(app: &AppState, inbound_messages: Vec<Message>, human_id: String) {
    let app = app.clone();
    tokio::spawn(async move {
        for msg in &inbound_messages {
            // A tool result is not a chat message. Delivering it as
            // `message.received` makes the console render an unrelated text
            // bubble while the tool card it belongs to stays on "pending"
            // forever — the console has no way to correlate the two. Send
            // the dedicated `tool.result` event instead.
            if let Some(event) = build_tool_result_event(&app, msg).await {
                let event_json = crate::ws::protocol::event_to_json(&event);
                let delivered = app.connections.send_to_human(&human_id, &event_json).await;
                tracing::info!(
                    delivered = delivered,
                    tool_call_id = %msg.metadata.get("tool_call_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown"),
                    "[tool_result] routed back to the originating call"
                );
                if delivered {
                    // Otherwise a reconnect replays it through the backlog,
                    // where it is indistinguishable from a chat message and
                    // shows up as a stray text bubble.
                    app.message
                        .mark_delivered(std::slice::from_ref(&msg.id))
                        .await;
                }
                continue;
            }

            let images: Vec<String> = msg
                .metadata
                .get("images")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            let event = if images.is_empty() {
                crate::ws::protocol::message_received(
                    &msg.conversation_id,
                    &msg.id,
                    &msg.sender.participant_id,
                    &format!("{:?}", msg.sender.participant_type).to_lowercase(),
                    msg.sender.display_name.as_deref(),
                    msg.content.as_text().unwrap_or(""),
                )
            } else {
                crate::ws::protocol::message_received_with_images(
                    &msg.conversation_id,
                    &msg.id,
                    &msg.sender.participant_id,
                    &format!("{:?}", msg.sender.participant_type).to_lowercase(),
                    msg.sender.display_name.as_deref(),
                    msg.content.as_text().unwrap_or(""),
                    &images,
                )
            };
            let event_json = crate::ws::protocol::event_to_json(&event);
            let delivered = app.connections.send_to_human(&human_id, &event_json).await;
            if delivered {
                tracing::info!(
                    "Pushed message to human WS: conversation_id={}, message_id={}",
                    msg.conversation_id,
                    msg.id
                );
                // Mark it seen now, not just on reconnect. Leaving it
                // pending means the next reconnect replays a message the
                // human already answered.
                app.message
                    .mark_delivered(std::slice::from_ref(&msg.id))
                    .await;
            } else {
                tracing::info!(
                    "Human offline, message persisted as Pending: conversation_id={}, message_id={}",
                    msg.conversation_id,
                    msg.id
                );
                let sender_name = msg
                    .sender
                    .display_name
                    .clone()
                    .unwrap_or_else(|| "AI Agent".to_string());
                let preview = msg.content.as_text().unwrap_or("").to_string();
                crate::notification::dispatch_offline_notification(
                    human_id.clone(),
                    sender_name,
                    msg.conversation_id.clone(),
                    preview,
                );
            }
        }
    });
}

/// Build a `tool.result` event for an inbound `role: "tool"` message.
///
/// Returns `None` for anything that is not a tool result, so the caller
/// falls through to the normal `message.received` path.
///
/// The `tool_id` is recovered from the stored call the result answers: the
/// agent only echoes `tool_call_id`, and the console needs the tool name to
/// know which card to settle.
async fn build_tool_result_event(
    app: &AppState,
    msg: &Message,
) -> Option<crate::model::event::Event> {
    let is_tool_role = msg.metadata.get("openai_role").and_then(|v| v.as_str()) == Some("tool");
    if !is_tool_role {
        return None;
    }

    let tool_call_id = msg
        .metadata
        .get("tool_call_id")
        .and_then(|v| v.as_str())?
        .to_string();

    let tool_id = app
        .message
        .find_tool_call(&msg.conversation_id, &tool_call_id)
        .await
        .and_then(|m| {
            m.metadata
                .get("tool_id")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());

    let output = serde_json::Value::String(msg.content.as_text().unwrap_or("").to_string());

    Some(crate::ws::protocol::tool_result_event(
        &msg.conversation_id,
        &tool_call_id,
        &tool_id,
        "success",
        Some(&output),
        None,
    ))
}

// ── Handler ──

/// Handler for `POST /v1/chat/completions`.
///
/// Phase 7.1.1: Extracts agent profile (tools, context) from HTTP request.
/// Phase 7.3: Supports human-triggered tool_calls responses.
pub async fn chat_completions(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(req): Json<ChatCompletionRequest>,
) -> Response {
    // ── Filter meta-requests from WorkBuddy ──
    //
    // WorkBuddy sends multiple requests per user message:
    //   - x-agent-purpose: conversation_topic → generates a title (not real chat)
    //   - x-agent-purpose: conversation       → the actual user conversation
    //
    // The topic request wraps the user's text in <session>...</session> tags
    // and uses a system prompt about title generation. We must NOT push these
    // to the human's chat timeline.
    //
    // Strategy: If x-agent-purpose is present and != "conversation", treat it
    // as a meta-request — respond with a minimal auto-generated reply without
    // forwarding to the human.
    let agent_purpose = headers
        .get("x-agent-purpose")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("conversation");

    let is_meta_request = agent_purpose != "conversation";

    if is_meta_request {
        tracing::info!(
            agent_purpose = %agent_purpose,
            "Meta-request detected — auto-responding without human"
        );
        return handle_meta_request(req, agent_purpose);
    }

    // 1. Extract agent profile from the HTTP request.
    let profile = AgentProfile::extract(&headers, &req, &principal.agent.id);
    tracing::info!(
        agent_id = %profile.agent_id,
        client_type = %profile.client_type,
        tools_count = profile.capabilities.len(),
        "Extracted agent profile from HTTP request"
    );

    // 2. Upsert capabilities + context into the registry.
    {
        let capabilities = profile.capabilities.clone();
        let has_tools = !capabilities.is_empty();
        let context = profile.to_context();
        let agent_id = profile.agent_id.clone();
        let human_id = principal.human.id.clone();
        let app_clone = app.clone();
        tokio::spawn(async move {
            // Only update capabilities if the request actually has tools.
            // Topic/meta requests have 0 tools — they would overwrite the
            // real tool list with an empty one if we upserted unconditionally.
            if has_tools {
                app_clone
                    .capability
                    .set_capabilities(&agent_id, capabilities)
                    .await;
            }
            app_clone.context.set_context(&agent_id, context).await;

            let caps = app_clone.capability.get_capabilities(&agent_id).await;
            let ctx = app_clone.context.get_context(&agent_id).await;
            let event =
                crate::ws::protocol::capability_updated(&human_id, &agent_id, &caps, ctx.as_ref());
            let event_json = crate::ws::protocol::event_to_json(&event);
            let _ = app_clone
                .connections
                .send_to_human(&human_id, &event_json)
                .await;
        });
    }

    // 3. Process inbound messages
    let (system_prompt, mut inbound_messages) =
        process_inbound_messages(&req, &principal, "pending", &profile.client_type);

    // 4. Resolve which conversation this request belongs to, then store
    //    the inbound messages under it.
    let session_key = resolve_session_key(&headers, &req, system_prompt.as_deref());
    tracing::info!(
        agent_id = %principal.agent.id,
        session_key = %session_key,
        "Resolved conversation session scope"
    );

    let conversation_id = {
        let cnv = app
            .conversation
            .find_or_create(
                &principal.agent.id,
                &principal.human.id,
                &session_key,
                system_prompt,
            )
            .await;
        for msg in &mut inbound_messages {
            msg.conversation_id = cnv.id.clone();
        }
        for msg in &inbound_messages {
            app.message.insert(msg.clone()).await;
        }
        cnv.id
    };

    // 5. Keepalive interval based on agent's client_type
    let keepalive_secs = principal.agent.client_type.keepalive_secs();
    let human_id = principal.human.id.clone();

    // Check if the client requested usage info in streaming mode.
    // WorkBuddy and Claude Code send `stream_options: { include_usage: true }`.
    let include_usage = req
        .stream_options
        .as_ref()
        .and_then(|so| so.get("include_usage"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // 5b. A human reply that arrived after the previous request ended would
    //     otherwise be lost: there was nothing in flight to carry it. Surface
    //     it now, on the next request, instead of making the caller wait for
    //     an answer the human already gave.
    if let Some(backlog) = app.outbound.drain(&conversation_id).await {
        let payload = select_backlog_payload(&backlog);
        tracing::info!(
            conversation_id = %conversation_id,
            backlog_len = backlog.len(),
            "Delivering reply that was parked after the previous request ended"
        );
        // The new message still reaches the human — they can answer it, and
        // that answer rides the next request the same way.
        push_messages_to_human(&app, inbound_messages, human_id.clone());
        return handle_backlog(
            app,
            conversation_id,
            payload,
            req.stream,
            is_async_mode(&headers),
            include_usage,
        )
        .await;
    }

    // 6. Branch: streaming vs non-streaming vs async.
    //
    // A second concurrent turn on one conversation is refused outright:
    // replies route per conversation, so two open requests would race for
    // the same answer and one of them would hang until timeout. The caller
    // retries after the first turn closes.
    if !is_async_mode(&headers) && app.reply.has_waiter(&conversation_id).await {
        // The new message still reaches the human — refusing the turn must
        // not swallow what the agent just said.
        push_messages_to_human(&app, inbound_messages, human_id);
        return (
            StatusCode::CONFLICT,
            Json(json!({
                "error": {
                    "message": "Another turn is already open on this conversation. Wait for it to finish, then resubmit.",
                    "type": "conflict",
                    "code": "turn_already_open",
                    "conversation_id": conversation_id,
                }
            })),
        )
            .into_response();
    }

    if req.stream {
        handle_streaming(
            app,
            conversation_id,
            keepalive_secs,
            inbound_messages,
            human_id,
            include_usage,
        )
        .await
    } else if is_async_mode(&headers) {
        handle_async(app, conversation_id, inbound_messages, human_id).await
    } else {
        handle_non_streaming(app, conversation_id, inbound_messages, human_id).await
    }
}

/// Pick which parked payload answers the current request.
///
/// A tool invocation wins over prose: it terminates the turn, whereas text
/// would leave the agent waiting for more. Otherwise the parked prose is
/// joined so a human who sent several replies loses none of them.
///
/// Detection parses the payload rather than substring-matching for
/// `"tool.invoke"`: a human typing the words "tool.invoke" in a normal
/// reply must not be mistaken for a tool call.
fn select_backlog_payload(backlog: &[String]) -> String {
    backlog
        .iter()
        .rev()
        .find(|p| matches!(parse_reply(p), HumanReply::ToolCalls { .. }))
        .cloned()
        .unwrap_or_else(|| backlog.join("\n\n"))
}

/// Answer immediately from a parked reply instead of waiting on the human.
async fn handle_backlog(
    app: AppState,
    conversation_id: String,
    payload: String,
    stream: bool,
    async_mode: bool,
    include_usage: bool,
) -> Response {
    if async_mode {
        // Short-circuit: create and complete in one step so the caller's
        // first poll already has the answer.
        let invocation_id = app.async_reply.create(&conversation_id).await;
        app.async_reply.complete(&invocation_id, &payload).await;
        return (
            StatusCode::ACCEPTED,
            Json(json!({
                "id": invocation_id,
                "object": "chat.completion.async",
                "status": "completed",
                "conversation_id": conversation_id,
                "poll_url": format!("/v1/replies/{}", invocation_id),
                "source": "outbound_backlog",
            })),
        )
            .into_response();
    }

    if !stream {
        let body = build_nonstreaming_json(&app, &conversation_id, &payload).await;
        return Response::builder()
            .header("Content-Type", "application/json")
            .body(Body::from(body))
            .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
            .into_response();
    }

    let completion_id = format!("chatcmpl-{}", Uuid::now_v7().simple());
    let app_c = app.clone();
    let conv = conversation_id.clone();
    let reply = parse_reply(&payload);

    let sse = async_stream::stream! {
        let role_chunk = ChatCompletionChunk::role_header(&completion_id);
        yield Ok::<SseEvent, std::convert::Infallible>(
            SseEvent::default().data(serde_json::to_string(&role_chunk).unwrap())
        );

        match reply {
            HumanReply::Text { text, .. } => {
                for word in text.split_inclusive(char::is_whitespace) {
                    let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                    yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                }
                app_c.reply.remove(&conv).await;
                let chunk = ChatCompletionChunk::finish(&completion_id);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
            HumanReply::ToolCalls { calls, text } => {
                if let Some(prose) = text.filter(|t| !t.trim().is_empty()) {
                    for word in prose.split_inclusive(char::is_whitespace) {
                        let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                    }
                }

                for call in &calls {
                    let call_id = call
                        .invocation_id
                        .clone()
                        .filter(|id| !id.trim().is_empty())
                        .unwrap_or_else(|| format!("call_{}", Uuid::now_v7().simple()));
                    let chunk = ChatCompletionChunk::tool_call_delta(
                        &completion_id,
                        &call_id,
                        &call.tool_name,
                        &call.arguments.to_string(),
                    );
                    yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                }

                app_c.reply.remove(&conv).await;
                let chunk = ChatCompletionChunk::finish_tool_calls(&completion_id);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
            HumanReply::EndTurn => {
                app_c.reply.remove(&conv).await;
                let chunk = ChatCompletionChunk::finish(&completion_id);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
        }

        if include_usage {
            let chunk = ChatCompletionChunk::usage_chunk(&completion_id);
            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
        }

        yield Ok(SseEvent::default().data("[DONE]"));
    };

    Sse::new(sse)
        .keep_alive(KeepAlive::default())
        .into_response()
}

// ── Async mode ──

/// Header that opts a request into asynchronous reply mode.
const ASYNC_MODE_HEADER: &str = "x-openhuman-mode";

/// How long the blocking path waits for a human reply.
///
/// Overridable because 5 minutes is arbitrary: some deployments want a short
/// fail-fast window, others are willing to hold a connection for an hour.
/// Callers that need longer than any sane HTTP timeout should use async mode
/// instead of raising this.
fn reply_timeout_secs() -> u64 {
    std::env::var("OPENHUMAN_REPLY_TIMEOUT_SECS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(300)
}

/// Whether the caller asked for asynchronous delivery.
///
/// Accepts `x-openhuman-mode: async`, and also honours a global override via
/// `OPENHUMAN_ASYNC_MODE=always` for deployments where no request should ever
/// block on a human.
fn is_async_mode(headers: &HeaderMap) -> bool {
    let always = std::env::var("OPENHUMAN_ASYNC_MODE")
        .map(|v| v.trim().eq_ignore_ascii_case("always"))
        .unwrap_or(false);
    if always {
        return true;
    }

    headers
        .get(ASYNC_MODE_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(|v| v.trim().eq_ignore_ascii_case("async"))
        .unwrap_or(false)
}

/// Asynchronous handler — hand the turn to the human and return at once.
///
/// Answers `202 Accepted` with an `invocation_id` instead of blocking. The
/// agent then polls `GET /v1/replies/{invocation_id}` (optionally long-polling
/// with `?wait=<secs>`) until the human answers.
///
/// This exists because the blocking path can only ever wait as long as an
/// HTTP client is willing to hold a connection open, and humans routinely
/// take longer than that.
async fn handle_async(
    app: AppState,
    conversation_id: String,
    inbound_messages: Vec<Message>,
    human_id: String,
) -> Response {
    let invocation_id = app.async_reply.create(&conversation_id).await;

    // Deliver the turn to the human. The invocation id rides along so the
    // console can echo it back on `reply.send` and complete this invocation
    // rather than a stale one.
    let app_clone = app.clone();
    let conv = conversation_id.clone();
    let inv = invocation_id.clone();
    tokio::spawn(async move {
        // `push_messages_to_human` spawns its own task; the invocation event
        // is emitted alongside it so the console learns the id either way.
        push_messages_to_human(&app_clone, inbound_messages, human_id.clone());
        let event = crate::ws::protocol::async_invocation_created(&conv, &inv);
        let event_json = crate::ws::protocol::event_to_json(&event);
        let _ = app_clone
            .connections
            .send_to_human(&human_id, &event_json)
            .await;
    });

    tracing::info!(
        conversation_id = %conversation_id,
        invocation_id = %invocation_id,
        "Async invocation created — awaiting human reply"
    );

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "id": invocation_id,
            "object": "chat.completion.async",
            "status": "pending",
            "conversation_id": conversation_id,
            "poll_url": format!("/v1/replies/{}", invocation_id),
            // Tell the agent how to wait without spinning.
            "hint": "Poll poll_url until status is \"completed\". ?wait=<secs> long-polls."
        })),
    )
        .into_response()
}

// ── Meta-request handler ──

/// Handle WorkBuddy meta-requests (e.g., conversation_topic) without
/// forwarding to the human.
///
/// These requests are internal to WorkBuddy's workflow — they generate
/// session titles, intent classifications, etc. We auto-respond with
/// a minimal reply so WorkBuddy doesn't block waiting for human input.
fn handle_meta_request(req: ChatCompletionRequest, purpose: &str) -> Response {
    // Generate a minimal response based on the purpose.
    let reply = match purpose {
        "conversation_topic" => {
            // Extract the user's text from <session>...</session> tags.
            let raw = req
                .messages
                .iter()
                .filter(|m| m.role == crate::openai_compat::ChatRole::User)
                .map(|m| m.content.to_text())
                .collect::<Vec<_>>()
                .join(" ");

            // Try to extract content from <session> tags.
            let title =
                extract_session_content(&raw).unwrap_or_else(|| "New conversation".to_string());

            // WorkBuddy expects a JSON object with title. Serialized, not
            // format!-built: a title containing a quote would otherwise
            // break the JSON and the topic request with it.
            serde_json::to_string(&json!({
                "isNewTopic": true,
                "title": title.trim(),
            }))
            .unwrap_or_else(|_| r#"{"isNewTopic":true,"title":"New conversation"}"#.to_string())
        }
        _ => "ok".to_string(),
    };

    if req.stream {
        // For streaming meta-requests, send the reply as SSE chunks.
        let completion_id = format!("chatcmpl-{}", Uuid::now_v7().simple());
        let stream = async_stream::stream! {
            let role_chunk = ChatCompletionChunk::role_header(&completion_id);
            yield Ok::<SseEvent, std::convert::Infallible>(
                SseEvent::default().data(serde_json::to_string(&role_chunk).unwrap())
            );

            for word in reply.split_inclusive(char::is_whitespace) {
                let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }

            let chunk = ChatCompletionChunk::finish(&completion_id);
            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));

            let chunk = ChatCompletionChunk::usage_chunk(&completion_id);
            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));

            yield Ok(SseEvent::default().data("[DONE]"));
        };
        Sse::new(stream).into_response()
    } else {
        Json(ChatCompletionResponse::from_human_reply(&reply)).into_response()
    }
}

/// Extract content from `<session>...</session>` XML tags.
fn extract_session_content(text: &str) -> Option<String> {
    let start = text.find("<session>")?;
    let end = text.rfind("</session>")?;
    let content = &text[start + "<session>".len()..end];
    let trimmed = content.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

// NOTE: inbound user-message normalization used to live here as
// `extract_user_message` (WorkBuddy `<user_query>` + `<session>` only).
// It now lives in `crate::normalize`, with one normalizer per agent
// family — see that module for the observed formats.

// ── Non-streaming handler ──

/// How often the non-streaming path writes a keepalive byte.
///
/// 5 seconds matches the SSE heartbeat — comfortably below the ~60s idle
/// threshold most proxies use to declare a connection dead.
fn nonstreaming_keepalive_secs() -> u64 {
    std::env::var("OPENHUMAN_KEEPALIVE_SECS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(5)
}

/// Non-streaming handler: wait for the human, then return one JSON body.
///
/// The response is written **incrementally** even though the payload is a
/// single JSON object. A `stream: false` request that sits silent for two
/// minutes gets killed by an idle-response timeout — Cloudflare answers
/// `524` at roughly 100 seconds, well before the human has had time to
/// read the question, let alone answer it.
///
/// The fix is to keep bytes moving: we emit a bare `\n` every few seconds
/// and then the JSON object. RFC 8259 permits whitespace before a JSON
/// value, so every conforming parser — including the OpenAI SDKs, which
/// call `response.json()` — ignores the padding. The caller sees an
/// ordinary `application/json` response, unchanged except that it arrives
/// late instead of never.
async fn handle_non_streaming(
    app: AppState,
    conversation_id: String,
    inbound_messages: Vec<Message>,
    human_id: String,
) -> Response {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    app.reply.register(&conversation_id, tx).await;
    // Cloned: the timeout branch below still needs the human id to announce
    // the handoff, and the success branch shadows it with the resolved one.
    push_messages_to_human(&app, inbound_messages, human_id.clone());

    // Configurable via OPENHUMAN_REPLY_TIMEOUT_SECS. Callers that need to
    // wait longer than any HTTP client tolerates should use async mode
    // (`x-openhuman-mode: async`) rather than raising this.
    let timeout = Duration::from_secs(reply_timeout_secs());
    let keepalive = Duration::from_secs(nonstreaming_keepalive_secs());

    let app_s = app.clone();
    let conv_s = conversation_id.clone();
    let human_s = human_id.clone();

    let body = async_stream::stream! {
        let mut ticker = interval(keepalive);
        ticker.tick().await;
        let deadline = tokio::time::Instant::now() + timeout;

        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());

            let out: Bytes = tokio::select! {
                _ = ticker.tick() => Bytes::from_static(b"\n"),
                maybe_payload = rx.recv() => {
                    match maybe_payload {
                        Some(first) => {
                            // Let the rest of this turn arrive before
                            // answering, so prose and tool calls can share
                            // one assistant message.
                            let mut payloads = vec![first];
                            payloads.append(&mut collect_rest(&mut rx, merge_window()).await);
                            let reply = merge_replies(&payloads);
                            let json = build_nonstreaming_json_from_reply(
                                &app_s, &conv_s, reply,
                            ).await;
                            Bytes::from(json)
                        }
                        // Channel dropped — nothing left to wait for.
                        None => break,
                    }
                }
                _ = tokio::time::sleep(remaining) => {
                    let json = handoff_to_async_json(&app_s, &conv_s, &human_s).await;
                    Bytes::from(json)
                }
            };

            // A keepalive is pure padding; anything else is the payload and
            // therefore the last thing we write.
            let is_keepalive = out.as_ref() == b"\n";
            yield Ok::<Bytes, std::convert::Infallible>(out);

            if !is_keepalive {
                break;
            }
        }
    };

    Response::builder()
        .header("Content-Type", "application/json")
        .header("Cache-Control", "no-cache")
        .body(Body::from_stream(body))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
        .into_response()
}

/// Turn one human reply into the JSON body of a non-streaming completion.
///
/// Shared by the wait loop above so the reply is parsed, persisted and
/// serialised exactly once.
async fn build_nonstreaming_json(
    app: &AppState,
    conversation_id: &str,
    reply_payload: &str,
) -> String {
    let reply = parse_reply(reply_payload);
    build_nonstreaming_json_from_reply(app, conversation_id, reply).await
}

async fn build_nonstreaming_json_from_reply(
    app: &AppState,
    conversation_id: &str,
    reply: HumanReply,
) -> String {
    let now = Utc::now();
    let conversation = app.conversation.get(conversation_id).await;
    let human_id = conversation
        .as_ref()
        .and_then(|c| c.human_id().map(|s| s.to_string()))
        .unwrap_or_default();

    app.reply.remove(conversation_id).await;

    // Correlation metadata for the stored reply. Populated only for tool
    // calls, so a later `role: "tool"` result can be routed back to the
    // exact call instead of arriving as an orphan message.
    let mut reply_meta: HashMap<String, Value> = HashMap::new();

    let (response, stored_content) = match reply {
        HumanReply::Text { text, .. } => {
            tracing::info!(
                conversation_id = %conversation_id,
                reply_len = text.len(),
                "Human text reply received"
            );
            let resp = ChatCompletionResponse::from_human_reply(&text);
            (resp, text)
        }
        HumanReply::ToolCalls { calls, text } => {
            tracing::info!(
                conversation_id = %conversation_id,
                call_count = calls.len(),
                companion_text = ?text,
                "[tool_call] generated for agent"
            );

            let specs: Vec<ToolCallSpec> = calls
                .iter()
                .map(|c| {
                    // Reuse the originating `invocation_id` as the OpenAI
                    // call id so the agent's `role: "tool"` reply can be
                    // paired back to the exact call the human triggered.
                    let call_id = c
                        .invocation_id
                        .clone()
                        .filter(|id| !id.trim().is_empty())
                        .unwrap_or_else(|| format!("call_{}", Uuid::now_v7().simple()));
                    ToolCallSpec {
                        id: call_id,
                        name: c.tool_name.clone(),
                        arguments: c.arguments.clone(),
                    }
                })
                .collect();

            // Record each call so later `role: "tool"` results can be routed
            // back instead of arriving as orphan messages.
            if let Some(first) = specs.first() {
                reply_meta.insert("tool_call_id".to_string(), Value::String(first.id.clone()));
                reply_meta.insert("tool_id".to_string(), Value::String(first.name.clone()));
            }
            reply_meta.insert(
                "tool_call_ids".to_string(),
                Value::Array(specs.iter().map(|s| Value::String(s.id.clone())).collect()),
            );

            // `content` and `tool_calls` coexist: the human's words ride
            // along with the call instead of being discarded.
            let resp = ChatCompletionResponse::from_tool_calls(specs.clone(), text.clone());

            let content = serde_json::to_string(&serde_json::json!({
                "tool_calls": specs.iter().map(|s| json!({
                    "tool_call": s.name,
                    "arguments": s.arguments,
                })).collect::<Vec<_>>(),
            }))
            .unwrap_or_else(|_| "{}".to_string());

            (resp, content)
        }
        HumanReply::EndTurn => {
            // Non-streaming mode cannot do multi-turn — an explicit
            // end-of-turn resolves to an empty (acknowledging) reply.
            tracing::info!(
                conversation_id = %conversation_id,
                "Human ended the turn (non-streaming)"
            );
            let resp = ChatCompletionResponse::from_human_reply("(turn ended)");
            (resp, "(turn ended)".to_string())
        }
    };

    // Store the human's reply in conversation history.
    app.message
        .insert(Message {
            id: format!("msg_{}", Uuid::now_v7().simple()),
            conversation_id: conversation_id.to_string(),
            sender: ParticipantRef::human_named(&human_id, "You"),
            content: ContentBlock::text(&stored_content),
            attachments: Vec::new(),
            metadata: reply_meta,
            status: MessageStatus::Sent,
            visibility: crate::model::message::MessageVisibility::HumanVisible,
            created_at: now,
        })
        .await;

    serde_json::to_string(&response).unwrap_or_else(|err| {
        tracing::error!("failed to serialise completion: {err}");
        r#"{"error":{"message":"internal serialisation error"}}"#.to_string()
    })
}

/// Elapsed reply window: keep the turn alive in async mode instead of
/// dropping it, and tell the caller where to pick it up.
///
/// The status code is already committed by the time this runs — the first
/// keepalive byte has gone out — so the handoff is described in the body
/// rather than as a `202`.
async fn handoff_to_async_json(app: &AppState, conversation_id: &str, human_id: &str) -> String {
    app.reply.remove(conversation_id).await;

    let invocation_id = app.async_reply.create(conversation_id).await;

    // Tell the console which invocation to complete. A client that does not
    // track ids still works: the WS handler falls back to the newest pending
    // invocation for this conversation.
    let app_clone = app.clone();
    let conv = conversation_id.to_string();
    let inv = invocation_id.clone();
    let hid = human_id.to_string();
    tokio::spawn(async move {
        let event = crate::ws::protocol::async_invocation_created(&conv, &inv);
        let event_json = crate::ws::protocol::event_to_json(&event);
        let _ = app_clone.connections.send_to_human(&hid, &event_json).await;
    });

    tracing::info!(
        conversation_id = %conversation_id,
        invocation_id = %invocation_id,
        timeout_secs = reply_timeout_secs(),
        "Reply window elapsed — handed off to async mode"
    );

    json!({
        "id": invocation_id,
        "object": "chat.completion.async",
        "status": "pending",
        "conversation_id": conversation_id,
        "poll_url": format!("/v1/replies/{}", invocation_id),
        "timed_out_after_secs": reply_timeout_secs(),
        "hint": "The turn is still open. Poll poll_url until status is \"completed\"; ?wait=<secs> long-polls."
    })
    .to_string()
}

// ── Streaming handler ──

/// Streaming handler: SSE with keepalive, then content chunks, then [DONE].
///
/// If the human sends a tool call reply, the SSE stream emits
/// `tool_calls` delta chunks instead of content deltas.
///
/// If `include_usage` is true, a usage chunk is sent after the
/// finish chunk (per OpenAI `stream_options.include_usage` spec).
async fn handle_streaming(
    app: AppState,
    conversation_id: String,
    keepalive_secs: u64,
    inbound_messages: Vec<Message>,
    human_id: String,
    include_usage: bool,
) -> Response {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    let is_online = app.connections.is_online(&human_id).await;

    app.reply.register(&conversation_id, tx).await;
    push_messages_to_human(&app, inbound_messages, human_id);

    let completion_id = format!("chatcmpl-{}", Uuid::now_v7().simple());
    let conv_id = conversation_id.clone();
    let app_clone = app.clone();
    let ka_secs = keepalive_secs.max(1);

    let stream = async_stream::stream! {
        // ── Multi-turn reply loop ──
        //
        // The human can send SEVERAL replies per agent request. Each text
        // reply is streamed as content deltas; the SSE stream stays open
        // (with keepalive heartbeats) until the human either:
        //   1. Ends the turn explicitly   → `finish_reason: stop` + [DONE]
        //   2. Requests a tool call      → `finish_reason: tool_calls`
        //      (WorkBuddy executes the tool and opens a NEW request)
        let mut keepalive = interval(Duration::from_secs(ka_secs));
        // Tick once immediately so the first heartbeat goes out right away.
        keepalive.tick().await;

        let mut sent_role_header = false;
        // The most recent prose the human sent this turn. Multi-turn
        // streaming keeps the turn open across several replies, so a human
        // who types and *then* taps a tool would otherwise lose the prose
        // when the tool call closes the turn with `content: null`.

        // Acknowledge the request straight away, whichever way presence
        // went. A caller that hears nothing for a minute cannot tell whether
        // the turn was lost or is simply waiting for a person, so say so
        // immediately and keep the stream open for the real reply.
        let notice = status_notice(is_online);
        if let Some(notice) = notice {
            sent_role_header = true;
            let role_chunk = ChatCompletionChunk::role_header(&completion_id);
            yield Ok::<SseEvent, std::convert::Infallible>(
                SseEvent::default().data(serde_json::to_string(&role_chunk).unwrap())
            );

            for word in notice.split_inclusive(char::is_whitespace) {
                let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
        }

        let conv_for_cleanup = conv_id.clone();
        let result: HumanReply = loop {
            let msg = tokio::select! {
                _ = keepalive.tick() => {
                    let chunk = ChatCompletionChunk::heartbeat(&completion_id);
                    yield Ok::<SseEvent, std::convert::Infallible>(
                        SseEvent::default().data(serde_json::to_string(&chunk).unwrap())
                    );
                    continue;
                }
                msg = rx.recv() => {
                    match msg {
                        Some(text) => text,
                        None => { return; }
                    }
                }
            };

            // Hold briefly for whatever else the human does: typing and then
            // tapping a tool are two separate events, and answering the first
            // at once strands the second in a later response.
            let mut payloads = vec![msg];
            payloads.append(&mut collect_rest(&mut rx, merge_window()).await);
            let reply = merge_replies(&payloads);

            match reply {
                HumanReply::Text { text, ended } => {
                    tracing::info!(
                        conversation_id = %conv_id,
                        reply_len = text.len(),
                        ended,
                        "Human text reply received (streaming, multi-turn)"
                    );

                    // Resolve the human's identity for storage.
                    let conversation = app_clone.conversation.get(&conv_id).await;
                    let human_id = conversation
                        .as_ref()
                        .and_then(|c| c.human_id().map(|s| s.to_string()))
                        .unwrap_or_default();

                    // Store this reply in the conversation history.
                    app_clone.message.insert(Message {
                        id: format!("msg_{}", Uuid::now_v7().simple()),
                        conversation_id: conv_id.clone(),
                        sender: ParticipantRef::human_named(&human_id, "You"),
                        content: ContentBlock::text(&text),
                        attachments: Vec::new(),
                        metadata: HashMap::new(),
                        status: MessageStatus::Sent,
                        visibility: crate::model::message::MessageVisibility::HumanVisible,
                        created_at: Utc::now(),
                    }).await;

                    // Stream the reply as content deltas.
                    if !sent_role_header {
                        sent_role_header = true;
                        let chunk = ChatCompletionChunk::role_header(&completion_id);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                    }
                    // Separate consecutive replies with a blank line so
                    // the agent sees them as distinct messages.
                    let payload = if text.ends_with('\n') { text.clone() } else { format!("{}\n\n", text) };
                    for word in payload.split_inclusive(char::is_whitespace) {
                        let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                    }

                    // Keep waiting for more — unless the human closed the
                    // turn in the same breath, in which case this prose is
                    // the whole answer.
                    if ended {
                        break HumanReply::EndTurn;
                    }
                    continue;
                }
                HumanReply::ToolCalls { .. } | HumanReply::EndTurn => break reply,
            }
        };

        // ── Turn finished — clean up the reply channel ──
        app_clone.reply.remove(&conv_for_cleanup).await;

        let conversation = app_clone.conversation.get(&conv_for_cleanup).await;
        let human_id = conversation
            .as_ref()
            .and_then(|c| c.human_id().map(|s| s.to_string()))
            .unwrap_or_default();
        let now = Utc::now();

        match &result {
            HumanReply::EndTurn => {
                tracing::info!(
                    conversation_id = %conv_for_cleanup,
                    "Human ended the turn (streaming)"
                );
                // If no content was sent at all, emit a minimal role header
                // so the agent SDK still sees a well-formed stream.
                if !sent_role_header {
                    let chunk = ChatCompletionChunk::role_header(&completion_id);
                    yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                }
                let chunk = ChatCompletionChunk::finish(&completion_id);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
            HumanReply::ToolCalls { calls, text } => {
                let companion = text.clone().filter(|t| !t.trim().is_empty());

                tracing::info!(
                    conversation_id = %conv_for_cleanup,
                    call_count = calls.len(),
                    companion_text = ?companion,
                    "[tool_call] generated for agent (streaming)"
                );

                // Stream the companion prose before the calls so the agent
                // sees both halves of what the human meant to say.
                if let Some(prose) = companion.as_deref() {
                    // A tool call closes the turn, so this header is the
                    // last one — no need to record that it was sent.
                    if !sent_role_header {
                        let chunk = ChatCompletionChunk::role_header(&completion_id);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                    }
                    let payload = if prose.ends_with('\n') {
                        prose.to_string()
                    } else {
                        format!("{}\n\n", prose)
                    };
                    for word in payload.split_inclusive(char::is_whitespace) {
                        let chunk = ChatCompletionChunk::content_delta(&completion_id, word);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                    }
                }

                for call in calls {
                    let stored_content = format!(
                        "{{\"tool_call\":\"{}\",\"arguments\":{}}}",
                        call.tool_name, call.arguments
                    );

                    // Reuse the originating invocation id as the OpenAI call
                    // id, so a later `role: "tool"` result can be routed back
                    // to this exact call — see `push_messages_to_human`.
                    let call_id = call
                        .invocation_id
                        .clone()
                        .filter(|id| !id.trim().is_empty())
                        .unwrap_or_else(|| format!("call_{}", Uuid::now_v7().simple()));

                    let mut tool_meta = HashMap::new();
                    tool_meta.insert(
                        "tool_call_id".to_string(),
                        Value::String(call_id.clone()),
                    );
                    tool_meta.insert(
                        "tool_id".to_string(),
                        Value::String(call.tool_name.clone()),
                    );
                    tool_meta.insert(
                        "openai_role".to_string(),
                        Value::String("assistant".to_string()),
                    );

                    app_clone.message.insert(Message {
                        id: format!("msg_{}", Uuid::now_v7().simple()),
                        conversation_id: conv_for_cleanup.clone(),
                        sender: ParticipantRef::human_named(&human_id, "You"),
                        content: ContentBlock::text(&stored_content),
                        attachments: Vec::new(),
                        metadata: tool_meta,
                        status: MessageStatus::Sent,
                        visibility: crate::model::message::MessageVisibility::HumanVisible,
                        created_at: now,
                    }).await;

                    let chunk = ChatCompletionChunk::tool_call_delta(
                        &completion_id,
                        &call_id,
                        &call.tool_name,
                        &call.arguments.to_string(),
                    );
                    yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                }

                // Finish chunk with finish_reason: tool_calls.
                let chunk = ChatCompletionChunk::finish_tool_calls(&completion_id);
                yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
            }
            HumanReply::Text { .. } => {
                unreachable!("text replies break out of the loop only via the arm above")
            }
        }

        // Usage chunk (if stream_options.include_usage was requested)
        if include_usage {
            let chunk = ChatCompletionChunk::usage_chunk(&completion_id);
            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
        }

        // [DONE]
        yield Ok(SseEvent::default().data("[DONE]"));
    };

    Sse::new(stream).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::openai_compat::ChatCompletionRequest;

    /// Build a request the same way the wire does, so the fixtures used here
    /// cannot drift from what serde actually accepts.
    fn request(body: serde_json::Value) -> ChatCompletionRequest {
        serde_json::from_value(body).expect("fixture must deserialize")
    }

    // ── parse_reply ──

    #[test]
    fn tool_invoke_payload_becomes_a_real_tool_call() {
        // The shape a Human Console sends as a WS `tool.invoke` event. It
        // must not be handed to the agent as a quoted JSON string — that is
        // what silently downgraded tool calls to text with
        // `finish_reason: stop`, so no client ever executed them.
        let payload = r#"{"type":"tool.invoke","invocation_id":"inv_1","tool_id":"Bash","input":{"command":"ls -la"}}"#;

        match parse_reply(payload) {
            HumanReply::ToolCalls { calls, text } => {
                assert_eq!(calls.len(), 1);
                assert_eq!(calls[0].tool_name, "Bash");
                assert_eq!(calls[0].arguments, json!({"command": "ls -la"}));
                assert_eq!(calls[0].invocation_id.as_deref(), Some("inv_1"));
                assert!(text.is_none(), "no companion prose in this payload");
            }
            other => panic!("expected a ToolCall, got {other:?}"),
        }
    }

    #[test]
    fn tool_invoke_can_carry_companion_text() {
        // A human who says something and taps a tool in the same breath must
        // not lose the words: OpenAI allows content and tool_calls together.
        let payload =
            r#"{"type":"tool.invoke","tool_id":"Bash","input":{"command":"ls"},"text":"我触发了"}"#;

        match parse_reply(payload) {
            HumanReply::ToolCalls { calls, text } => {
                assert_eq!(calls[0].tool_name, "Bash");
                assert_eq!(text.as_deref(), Some("我触发了"));
            }
            other => panic!("expected a ToolCall, got {other:?}"),
        }
    }

    #[test]
    fn blank_companion_text_is_dropped() {
        let payload = r#"{"type":"tool.invoke","tool_id":"Bash","input":{},"text":"   "}"#;
        match parse_reply(payload) {
            HumanReply::ToolCalls { text, .. } => {
                assert!(
                    text.is_none(),
                    "whitespace-only text must not become content"
                );
            }
            other => panic!("expected a ToolCall, got {other:?}"),
        }
    }

    #[test]
    fn tool_invoke_without_input_defaults_to_empty_object() {
        let payload = r#"{"type":"tool.invoke","tool_id":"Read"}"#;
        match parse_reply(payload) {
            HumanReply::ToolCalls { calls, .. } => {
                assert_eq!(calls[0].tool_name, "Read");
                assert_eq!(calls[0].arguments, json!({}));
                assert!(calls[0].invocation_id.is_none());
            }
            other => panic!("expected a ToolCall, got {other:?}"),
        }
    }

    #[test]
    fn legacy_tool_call_payload_still_works() {
        let payload =
            r#"{"__tool_call__":true,"tool_name":"Bash","arguments":{"command":"echo hi"}}"#;
        match parse_reply(payload) {
            HumanReply::ToolCalls { calls, .. } => {
                assert_eq!(calls[0].tool_name, "Bash");
                assert_eq!(calls[0].arguments, json!({"command": "echo hi"}));
                assert!(
                    calls[0].invocation_id.is_none(),
                    "legacy payloads carry no id"
                );
            }
            other => panic!("expected a ToolCall, got {other:?}"),
        }
    }

    // ── merge_replies: one turn, one assistant message ──

    #[test]
    fn prose_and_tool_call_merge_into_one_message() {
        // The whole point of the merge window: typing and then tapping a
        // tool are two events, and the agent must see one message carrying
        // both, not two responses.
        let payloads = vec![
            "我先看个时间".to_string(),
            r#"{"type":"tool.invoke","invocation_id":"inv_1","tool_id":"get_current_time","input":{}}"#
                .to_string(),
        ];

        match merge_replies(&payloads) {
            HumanReply::ToolCalls { calls, text } => {
                assert_eq!(calls.len(), 1);
                assert_eq!(calls[0].tool_name, "get_current_time");
                assert_eq!(
                    text.as_deref(),
                    Some("我先看个时间"),
                    "prose must survive alongside the call"
                );
            }
            other => panic!("expected ToolCalls, got {other:?}"),
        }
    }

    #[test]
    fn several_tools_merge_into_one_array() {
        let payloads = vec![
            r#"{"type":"tool.invoke","invocation_id":"inv_a","tool_id":"Read","input":{}}"#
                .to_string(),
            r#"{"type":"tool.invoke","invocation_id":"inv_b","tool_id":"Bash","input":{"c":"ls"}}"#
                .to_string(),
        ];

        match merge_replies(&payloads) {
            HumanReply::ToolCalls { calls, text } => {
                assert_eq!(calls.len(), 2, "both calls belong to one message");
                assert_eq!(calls[0].invocation_id.as_deref(), Some("inv_a"));
                assert_eq!(calls[1].invocation_id.as_deref(), Some("inv_b"));
                assert!(text.is_none());
            }
            other => panic!("expected ToolCalls, got {other:?}"),
        }
    }

    #[test]
    fn inline_image_is_parsed_not_dropped() {
        // Vision input arrives as an `image_url` part. Dropping it left the
        // human answering a question about a picture they never received.
        let body = json!({
            "messages": [{
                "role": "user",
                "content": [
                    {"type": "text", "text": "这张图里有什么？"},
                    {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="}}
                ]
            }]
        });

        let req = request(body);
        let content = &req.messages[0].content;

        assert!(content.has_image(), "image part must be recognised");
        assert_eq!(
            content.image_urls(),
            vec!["data:image/png;base64,iVBORw0KGgo="]
        );
        // The text survives, and the image leaves a marker so the human is
        // not staring at a message that looks empty.
        let text = content.to_text();
        assert!(text.contains("这张图里有什么？"), "got {text:?}");
        assert!(text.contains("[图片]"), "got {text:?}");
    }

    #[test]
    fn image_mime_is_read_from_the_data_url() {
        assert_eq!(
            guess_image_type("data:image/jpeg;base64,AAAA"),
            "image/jpeg"
        );
        assert_eq!(guess_image_type("https://x.example/a.png"), "image/png");
    }

    #[test]
    fn merged_turn_travelling_as_an_array_is_recombined() {
        // Async turns submit several payloads as one JSON array; the parser
        // must see that as a single turn, not as a text blob.
        let payload = serde_json::to_string(&vec![
            serde_json::Value::String("我先看个时间".to_string()),
            serde_json::json!({
                "type": "tool.invoke",
                "invocation_id": "inv_1",
                "tool_id": "get_current_time",
                "input": {},
            }),
        ])
        .unwrap();

        match parse_turn(&payload) {
            HumanReply::ToolCalls { calls, text } => {
                assert_eq!(calls.len(), 1);
                assert_eq!(calls[0].tool_name, "get_current_time");
                assert_eq!(text.as_deref(), Some("我先看个时间"));
            }
            other => panic!("expected ToolCalls, got {other:?}"),
        }
    }

    #[test]
    fn single_payload_is_never_mistaken_for_a_merged_turn() {
        assert!(matches!(parse_turn("plain text"), HumanReply::Text { .. }));
    }

    #[test]
    fn online_and_offline_both_acknowledge() {
        // A caller holding an open request gets told something either way;
        // silence for a minute is indistinguishable from a lost turn.
        let online = status_notice(true).expect("online turn is acknowledged");
        let offline = status_notice(false).expect("offline turn is acknowledged");

        assert!(online.contains("在线"), "got {online:?}");
        assert!(offline.contains("离线"), "got {offline:?}");
    }

    #[test]
    fn consecutive_prose_is_joined_not_overwritten() {
        let payloads = vec!["first".to_string(), "second".to_string()];
        match merge_replies(&payloads) {
            HumanReply::Text { text: t, .. } => {
                assert!(t.contains("first"), "got {t:?}");
                assert!(t.contains("second"), "got {t:?}");
            }
            other => panic!("expected Text, got {other:?}"),
        }
    }

    #[test]
    fn end_turn_alone_yields_no_phantom_content() {
        let payloads = vec![END_TURN_SIGNAL.to_string()];
        assert!(matches!(merge_replies(&payloads), HumanReply::EndTurn));
    }

    #[test]
    fn tool_plus_end_turn_still_reports_the_tool() {
        // Closing the turn must not swallow a call made in the same breath.
        let payloads = vec![
            r#"{"type":"tool.invoke","invocation_id":"inv_1","tool_id":"Read","input":{}}"#
                .to_string(),
            END_TURN_SIGNAL.to_string(),
        ];
        assert!(matches!(
            merge_replies(&payloads),
            HumanReply::ToolCalls { .. }
        ));
    }

    #[test]
    fn other_json_stays_human_text() {
        // A human legitimately pasting JSON must not be reinterpreted as a
        // tool call just because it starts with `{`.
        let payload = r#"{"type":"something.else","tool_id":"Bash"}"#;
        assert!(matches!(parse_reply(payload), HumanReply::Text { .. }));

        let payload = r#"{"note":"call me"}"#;
        assert!(matches!(parse_reply(payload), HumanReply::Text { .. }));
    }

    #[test]
    fn plain_text_and_end_turn() {
        assert!(matches!(
            parse_reply("Sure, on it."),
            HumanReply::Text { .. }
        ));
        assert!(matches!(
            parse_reply("  __END_TURN__  "),
            HumanReply::EndTurn
        ));
    }

    // ── resolve_session_key ──

    fn session_key(headers: &[(&str, &str)], body: serde_json::Value) -> String {
        let mut map = HeaderMap::new();
        for (k, v) in headers {
            let name = axum::http::HeaderName::from_bytes(k.as_bytes()).unwrap();
            map.insert(name, v.parse().unwrap());
        }
        resolve_session_key(&map, &request(body), None)
    }

    fn body() -> serde_json::Value {
        json!({"model": "openhuman-human", "messages": []})
    }

    #[test]
    fn no_identifier_falls_back_to_a_client_scoped_key() {
        // Deliberately *not* a single global "default": callers that say
        // nothing about who they are would otherwise share one conversation
        // — and one outbound queue, so a tool call issued in one client gets
        // collected by a request from another.
        let key = session_key(&[], body());
        assert!(key.starts_with("cli:"), "got {key}");
        assert_ne!(key, "default");
    }

    #[test]
    fn unidentified_callers_do_not_share_a_conversation() {
        let curl = session_key(&[("user-agent", "curl/8.4.0")], body());
        let workbuddy = session_key(&[("user-agent", "WorkBuddy/1.0")], body());
        assert_ne!(
            curl, workbuddy,
            "distinct clients must not land in one conversation"
        );
        // Same client, repeated requests: stable, so the thread continues.
        let again = session_key(&[("user-agent", "curl/8.4.0")], body());
        assert_eq!(curl, again);
    }

    #[test]
    fn same_prompt_different_clients_stay_apart() {
        let req_a = || {
            json!({"messages": [
                {"role": "system", "content": "You are a release engineer."},
                {"role": "user", "content": "hi"},
            ]})
        };

        let prompt = "You are a release engineer.";
        let mut h1 = HeaderMap::new();
        h1.insert("user-agent", "curl/8.4.0".parse().unwrap());
        let a = resolve_session_key(&h1, &request(req_a()), Some(prompt));

        let mut h2 = HeaderMap::new();
        h2.insert("user-agent", "WorkBuddy/1.0".parse().unwrap());
        let b = resolve_session_key(&h2, &request(req_a()), Some(prompt));

        assert!(a.starts_with("prm:"), "got {a}");
        assert_ne!(a, b, "a shared prompt must not merge two clients");
    }

    #[test]
    fn conversation_id_header_wins() {
        let key = session_key(
            &[
                ("x-openhuman-conversation-id", "design-review"),
                ("x-session-id", "ignored"),
            ],
            body(),
        );
        assert_eq!(key, "hdr:design-review");
    }

    #[test]
    fn conversation_body_field_is_used() {
        let key = session_key(
            &[],
            json!({"messages": [], "conversation": {"id": "conv_7"}}),
        );
        assert_eq!(key, "cnv:conv_7");

        let key = session_key(&[], json!({"messages": [], "conversation": "conv_8"}));
        assert_eq!(key, "cnv:conv_8");
    }

    #[test]
    fn sources_are_namespaced_so_equal_strings_cannot_collide() {
        let by_user = session_key(&[], json!({"messages": [], "user": "alice"}));
        let by_header = session_key(&[("x-session-id", "alice")], body());
        assert_eq!(by_user, "usr:alice");
        assert_eq!(by_header, "ses:alice");
        assert_ne!(by_user, by_header);
    }

    #[test]
    fn distinct_chat_windows_get_distinct_keys() {
        let a = session_key(&[("x-openhuman-conversation-id", "window-a")], body());
        let b = session_key(&[("x-openhuman-conversation-id", "window-b")], body());
        assert_ne!(a, b);
    }

    #[test]
    fn system_prompt_fingerprint_is_stable_and_distinct() {
        let h = HeaderMap::new();
        let req = request(body());
        let first = resolve_session_key(&h, &req, Some("You are a release engineer."));
        let second = resolve_session_key(&h, &req, Some("You are a release engineer."));
        let third = resolve_session_key(&h, &req, Some("You are a lawyer."));

        assert_eq!(
            first, second,
            "identical prompts must reuse one conversation"
        );
        assert_ne!(first, third);
        assert!(first.starts_with("prm:"));
    }
}
