//! WebSocket protocol — event types aligned with `protocol/internal-model/event.md`.
//!
//! All realtime events use the `Event` envelope from `model::event`:
//!
//! ```json
//! {
//!   "event_id": "evt_0189abc123",
//!   "event_type": "message.received",
//!   "conversation_id": "cnv_0189abc123def456",
//!   "timestamp": "2025-01-15T09:28:00.123Z",
//!   "data": { ... }
//! }
//! ```
//!
//! The WS protocol is a transport layer on top of the Event model:
//! - Server → Client: serialize `Event` as JSON text
//! - Client → Server: parse JSON text as `ClientMessage`
//!
//! # Event Types (Server → Client)
//!
//! | event_type             | Trigger                              |
//! |------------------------|--------------------------------------|
//! | `session.connected`     | WS connection authenticated          |
//! | `message.received`     | Agent sent a message to the human    |
//! | `reply.delivered`       | Human's reply was delivered to SSE   |
//! | `capability.updated`    | Agent published a capability manifest|
//! | `tool.result`           | Agent returned a tool invocation result |
//! | `error`                 | Protocol or server error             |
//!
//! # Event Types (Client → Server)
//!
//! | event_type             | Purpose                              |
//! |------------------------|--------------------------------------|
//! | `reply.send`            | Human sends a reply for an agent     |
//! | `presence.update`       | Human updates their status            |
//! | `capability.manifest`   | Agent publishes its tool manifest     |
//! | `tool.invoke`           | Human requests an agent tool invocation |
//!
//! # OpenHuman Native Extension Protocol (OPTIONAL)
//!
//! The `capability.manifest` and `tool.invoke` events are part of the
//! **OpenHuman Native Extension Protocol** — a set of WebSocket events
//! that provide enhanced functionality (push-based capability discovery,
//! human-initiated tool calling) for agents that implement the
//! OpenHuman SDK.
//!
//! **These are NOT required for basic operation.** Any OpenAI-compatible
//! agent can use OpenHuman with just `POST /v1/chat/completions` and a
//! Bearer API key. The HTTP path (Phase 7.1.1) automatically extracts
//! capabilities from the `tools[]` array in the request body.
//!
//! The WS extension events are:
//! - `capability.manifest` — supersedes HTTP-based discovery (optional)
//! - `tool.invoke` — human-initiated tool calling (Phase 8+)
//! - `tool.result` — agent returns tool execution result (Phase 8+)

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::event::Event;

// ── Server → Client: Event builders ──

/// Build a `session.connected` event.
///
/// Sent immediately after WS authentication succeeds.
pub fn session_connected(human_id: &str, display_name: &str) -> Event {
    Event::new(
        "session.connected",
        human_id, // conversation_id is the human's own session channel
        serde_json::json!({
            "human_id": human_id,
            "display_name": display_name,
        }),
    )
}

/// Build a `message.received` event.
///
/// Pushed to all connected devices of the human when an agent
/// sends a message via `POST /v1/chat/completions`.
pub fn message_received(
    conversation_id: &str,
    message_id: &str,
    sender_id: &str,
    sender_type: &str,
    sender_name: Option<&str>,
    text: &str,
) -> Event {
    Event::new(
        "message.received",
        conversation_id,
        serde_json::json!({
            "message_id": message_id,
            "sender_id": sender_id,
            "sender_type": sender_type,
            "sender_name": sender_name,
            "text": text,
        }),
    )
}

/// Build a `message.received` event that also carries image attachments.
///
/// Vision input arrives as `image_url` content parts (often inline
/// `data:` URLs). Without forwarding them the human is asked about a
/// picture they cannot see.
pub fn message_received_with_images(
    conversation_id: &str,
    message_id: &str,
    sender_id: &str,
    sender_type: &str,
    sender_name: Option<&str>,
    text: &str,
    images: &[String],
) -> Event {
    Event::new(
        "message.received",
        conversation_id,
        serde_json::json!({
            "message_id": message_id,
            "sender_id": sender_id,
            "sender_type": sender_type,
            "sender_name": sender_name,
            "text": text,
            "images": images,
        }),
    )
}

/// Build an `async.invocation.created` event.
///
/// Sent to the human's WS client when an agent submits a turn in
/// asynchronous mode. The console must echo `invocation_id` back on its
/// `reply.send` so the reply completes this specific invocation rather
/// than being dropped (nobody is holding a blocking request open in async
/// mode, so there is no reply channel to fall back to).
pub fn async_invocation_created(conversation_id: &str, invocation_id: &str) -> Event {
    Event::new(
        "async.invocation.created",
        conversation_id,
        serde_json::json!({
            "invocation_id": invocation_id,
        }),
    )
}

/// Build a `reply.delivered` event.
///
/// Sent to the human's WS client to confirm that their reply
/// was delivered to the waiting SSE stream.
pub fn reply_delivered(conversation_id: &str, delivered: bool) -> Event {
    Event::new(
        "reply.delivered",
        conversation_id,
        serde_json::json!({
            "delivered": delivered,
        }),
    )
}

/// Build a `capability.updated` event (Phase 7).
///
/// Pushed to all connected human devices when an agent publishes
/// a `capability.manifest`. The data contains the agent's tool list
/// and optional context, allowing the human client to render the
/// agent's capabilities in the UI.
pub fn capability_updated(
    human_id: &str,
    agent_id: &str,
    capabilities: &[crate::model::agent_capability::AgentCapability],
    context: Option<&crate::model::agent_context::AgentContext>,
) -> Event {
    Event::new(
        "capability.updated",
        human_id,
        serde_json::json!({
            "agent_id": agent_id,
            "capabilities": capabilities,
            "context": context,
        }),
    )
}

/// Build a `conversation.started` event.
///
/// Sent when a request opens a conversation the server has not seen: the
/// caller started a new session. Consoles and agent seats open it as a
/// thread of its own.
pub fn conversation_started(
    conversation_id: &str,
    agent_id: &str,
    agent_name: &str,
    client: &str,
) -> Event {
    Event::new(
        "conversation.started",
        conversation_id,
        serde_json::json!({
            "agent_id": agent_id,
            "agent_name": agent_name,
            "client": client,
        }),
    )
}

/// Build a `tool.result` event (Phase 7).
///
/// Pushed to the human's WS client when the agent returns a result
/// for a `tool.invoke` request. The human UI renders the output.
///
/// `invocation_id` is the OpenAI-visible call id (`tool_call_id`), which is
/// what lets the console settle the exact card it issued — without the
/// correlation the card stays on "pending" even though the result arrived.
///
/// The first parameter is the **conversation** id, matching every other
/// event builder (it was previously named `human_id`, which was wrong and
/// sent humans' ids into a field consumers read as a conversation id).
pub fn tool_result_event(
    conversation_id: &str,
    invocation_id: &str,
    tool_id: &str,
    status: &str,
    output: Option<&Value>,
    error: Option<&str>,
) -> Event {
    Event::new(
        "tool.result",
        conversation_id,
        serde_json::json!({
            "invocation_id": invocation_id,
            "tool_id": tool_id,
            "status": status,
            "output": output,
            "error": error,
        }),
    )
}

/// Build an `error` event.
pub fn error_event(conversation_id: &str, code: &str, message: &str) -> Event {
    Event::new(
        "error",
        conversation_id,
        serde_json::json!({
            "code": code,
            "message": message,
        }),
    )
}

// ── Client → Server: parsed messages ──

/// A message from the human client to the server.
///
/// The client sends JSON with an `event_type` field. We parse it
/// into this enum for ergonomic matching.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event_type")]
pub enum ClientMessage {
    /// Human sends a reply for an agent's conversation.
    ///
    /// `invocation_id` is set when answering a turn delivered in
    /// asynchronous mode (see `async.invocation.created`). It lets the
    /// server complete that specific pending invocation instead of pushing
    /// onto a reply channel that — in async mode — nobody is reading.
    #[serde(rename = "reply.send")]
    ReplySend {
        conversation_id: String,
        text: String,
        #[serde(default)]
        invocation_id: Option<String>,
    },

    /// Human updates their presence status.
    #[serde(rename = "presence.update")]
    PresenceUpdate { status: String },

    /// Agent publishes a capability manifest (tools + context).
    ///
    /// **Optional Native Extension**: This is sent by agents that connect
    /// via WS using the OpenHuman SDK. The HTTP path (`POST /v1/chat/completions`)
    /// automatically extracts tools from the `tools[]` array — this event
    /// is NOT required for basic operation.
    ///
    /// The server stores the capabilities and forwards a
    /// `capability.updated` event to the bound human's devices.
    #[serde(rename = "capability.manifest")]
    CapabilityManifest {
        agent_id: String,
        capabilities: Vec<crate::model::agent_capability::AgentCapability>,
        #[serde(default)]
        context: Option<crate::model::agent_context::AgentContext>,
    },

    /// Human requests an agent tool invocation.
    ///
    /// **Optional Native Extension**: Human-initiated tool calling is
    /// deferred to Phase 8+. The standard OpenAI `tool_calls` response
    /// path is used instead — the human (via OpenHuman) returns a
    /// `tool_calls` response, and the agent executes the tool and
    /// sends back a `role: "tool"` message in the next request.
    ///
    /// OpenHuman does **not** execute the tool — it only transports the request.
    #[serde(rename = "tool.invoke")]
    ToolInvoke {
        conversation_id: String,
        invocation_id: String,
        tool_id: String,
        input: Value,
        /// Words the human said alongside the tool call.
        ///
        /// Forwarded so the agent sees them as `content` next to
        /// `tool_calls` — dropping this is what made companion prose vanish.
        #[serde(default)]
        text: Option<String>,
    },

    /// Human explicitly ends the current turn.
    ///
    /// Multi-turn mode: the human can send several replies (and make
    /// several tool invocations) per agent request. The SSE stream stays
    /// open between replies; this message closes the turn, causing the
    /// waiting `POST /v1/chat/completions` request to finish with
    /// `finish_reason: stop`.
    #[serde(rename = "end.turn")]
    EndTurn { conversation_id: String },
}

impl ClientMessage {
    /// Parse a JSON string received from WebSocket.
    pub fn from_json(raw: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(raw)
    }
}

/// Convenience: serialize an `Event` to JSON for sending over WS.
pub fn event_to_json(event: &Event) -> String {
    serde_json::to_string(event).unwrap_or_else(|_| {
        r#"{"event_id":"evt_error","event_type":"error","conversation_id":"","timestamp":"1970-01-01T00:00:00Z","data":{"code":"serialize_failed","message":"Failed to serialize event."}}"#.to_string()
    })
}
