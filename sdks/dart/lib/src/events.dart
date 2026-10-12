/// OpenHuman Dart SDK — Event models.
///
/// This file implements all WebSocket protocol event types, aligned
/// 1:1 with the Rust server implementation:
///
///   - `server/src/ws/protocol.rs`   — event builders + ClientMessage enum
///   - `server/src/model/event.rs`   — Event envelope struct
///
/// and the protocol specification:
///
///   - `protocol/internal-model/event.md` — event envelope + type taxonomy
///
/// # JSON Wire Format
///
/// All Server → Client events share the `OpenHumanEvent` envelope:
///
/// ```json
/// {
///   "event_id": "evt_0189abc123",
///   "event_type": "message.received",
///   "conversation_id": "cnv_0189abc123def456",
///   "timestamp": "2025-01-15T09:28:00.123Z",
///   "data": { ... }
/// }
/// ```
///
/// Client → Server messages use a tagged union with `event_type`:
///
/// ```json
/// {
///   "event_type": "reply.send",
///   "conversation_id": "cnv_xxx",
///   "text": "the reply"
/// }
/// ```
///
/// # Field Naming
///
/// Dart fields use camelCase. JSON fields use snake_case.
/// Mapping is done via `@JsonKey` annotations so the wire format
/// is never changed.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'events.freezed.dart';
part 'events.g.dart';

// ═════════════════════════════════════════════════════════════════
//  Enums
// ═════════════════════════════════════════════════════════════════

/// All Server → Client event types.
///
/// Aligned with `server/src/ws/protocol.rs` event builders.
enum EventType {
  /// `session.connected` — WS connection authenticated.
  ///
  /// Payload: [SessionConnectedData]
  sessionConnected,

  /// `message.received` — Agent sent a message to the human.
  ///
  /// Payload: [MessageReceivedData]
  messageReceived,

  /// `reply.delivered` — Human's reply was delivered to SSE.
  ///
  /// Payload: [ReplyDeliveredData]
  replyDelivered,

  /// `capability.updated` — Agent published a capability manifest.
  ///
  /// Payload: [CapabilityUpdatedData]
  capabilityUpdated,

  /// `tool.result` — Agent returned a tool invocation result.
  ///
  /// Payload: [ToolResultData]
  toolResult,

  /// `async.invocation.created` — Server opened an async turn.
  ///
  /// Payload: [AsyncInvocationCreatedData]
  asyncInvocationCreated,

  /// `error` — Protocol or server error.
  ///
  /// Payload: [ErrorData]
  error,
}

/// Extension to convert [EventType] to/from the wire-format string.
extension EventTypeX on EventType {
  /// Convert to the snake_case wire-format string used in JSON.
  String get wireName {
    switch (this) {
      case EventType.sessionConnected:
        return 'session.connected';
      case EventType.messageReceived:
        return 'message.received';
      case EventType.replyDelivered:
        return 'reply.delivered';
      case EventType.capabilityUpdated:
        return 'capability.updated';
      case EventType.toolResult:
        return 'tool.result';
      case EventType.asyncInvocationCreated:
        return 'async.invocation.created';
      case EventType.error:
        return 'error';
    }
  }

  /// Parse a wire-format string into an [EventType].
  ///
  /// Returns `null` for unknown event types (forward-compatible).
  static EventType? fromWireName(String? name) {
    switch (name) {
      case 'session.connected':
        return EventType.sessionConnected;
      case 'message.received':
        return EventType.messageReceived;
      case 'reply.delivered':
        return EventType.replyDelivered;
      case 'capability.updated':
        return EventType.capabilityUpdated;
      case 'tool.result':
        return EventType.toolResult;
      case 'async.invocation.created':
        return EventType.asyncInvocationCreated;
      case 'error':
        return EventType.error;
      default:
        return null;
    }
  }
}

/// WebSocket connection lifecycle state.
///
/// Used by `connection.dart` (to be implemented) to expose a
/// connection state stream to the Flutter layer.
enum ConnectionState {
  /// Initial state — not yet connected.
  idle,

  /// Attempting to establish WebSocket connection.
  connecting,

  /// WebSocket connected and authenticated (session.connected received).
  connected,

  /// Connection lost, attempting to reconnect with backoff.
  reconnecting,

  /// Permanently disconnected (either by user or after max retries).
  disconnected,

  /// Unrecoverable error.
  error,
}

/// Human presence status.
///
/// Aligned with `server/src/model/identity.rs::HumanStatus`.
enum HumanStatus {
  online,
  away,
  offline,
}

// ═════════════════════════════════════════════════════════════════
//  Event Envelope (Server → Client)
// ═════════════════════════════════════════════════════════════════

/// Common envelope for all Server → Client events.
///
/// Aligned with Rust `server/src/model/event.rs::Event`:
///
/// ```rust
/// pub struct Event {
///     pub event_id: String,
///     pub event_type: String,
///     pub conversation_id: String,
///     pub timestamp: DateTime<Utc>,
///     pub data: Value,
/// }
/// ```
///
/// JSON wire format (from `protocol/internal-model/event.md §1`):
///
/// ```json
/// {
///   "event_id": "evt_0189abc123",
///   "event_type": "message.received",
///   "conversation_id": "cnv_0189abc123def456",
///   "timestamp": "2025-01-15T09:28:00.123Z",
///   "data": { ... }
/// }
/// ```
@freezed
class OpenHumanEvent with _$OpenHumanEvent {
  const factory OpenHumanEvent({
    /// Unique event ID (UUIDv7, `evt_` prefixed).
    ///
    /// Used for client-side deduplication (at-least-once delivery).
    @JsonKey(name: 'event_id') required String eventId,

    /// Event type string (e.g., `"message.received"`).
    ///
    /// Use [EventTypeX.fromWireName] to parse into [EventType].
    @JsonKey(name: 'event_type') required String eventType,

    /// Conversation ID this event belongs to.
    @JsonKey(name: 'conversation_id') required String conversationId,

    /// Server-side event timestamp (ISO 8601, millisecond precision).
    required DateTime timestamp,

    /// Event-specific payload. Structure depends on [eventType].
    ///
    /// For typed access, parse this into the corresponding data class
    /// (e.g., [MessageReceivedData.fromJson] for `message.received`).
    required Map<String, dynamic> data,
  }) = _OpenHumanEvent;

  factory OpenHumanEvent.fromJson(Map<String, dynamic> json) =>
      _$OpenHumanEventFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Server → Client Event Payloads
// ═════════════════════════════════════════════════════════════════

/// Payload for `session.connected` event.
///
/// Sent immediately after WS authentication succeeds.
///
/// Aligned with Rust `server/src/ws/protocol.rs::session_connected`:
/// ```rust
/// pub fn session_connected(human_id: &str, display_name: &str) -> Event {
///     Event::new("session.connected", human_id, json!({
///         "human_id": human_id,
///         "display_name": display_name,
///     }))
/// }
/// ```
@freezed
class SessionConnectedData with _$SessionConnectedData {
  const factory SessionConnectedData({
    /// The authenticated human's ID.
    @JsonKey(name: 'human_id') required String humanId,

    /// The human's display name.
    @JsonKey(name: 'display_name') required String displayName,
  }) = _SessionConnectedData;

  factory SessionConnectedData.fromJson(Map<String, dynamic> json) =>
      _$SessionConnectedDataFromJson(json);
}

/// Payload for `message.received` event.
///
/// Pushed to all connected devices of the human when an agent
/// sends a message via `POST /v1/chat/completions`.
///
/// Aligned with Rust `server/src/ws/protocol.rs::message_received`:
/// ```rust
/// pub fn message_received(
///     conversation_id: &str,
///     message_id: &str,
///     sender_id: &str,
///     sender_type: &str,
///     text: &str,
/// ) -> Event { ... }
/// ```
@freezed
class MessageReceivedData with _$MessageReceivedData {
  const factory MessageReceivedData({
    /// The conversation this message belongs to (`cnv_` prefixed).
    @JsonKey(name: 'conversation_id') required String conversationId,

    /// Unique message ID (`msg_` prefixed).
    @JsonKey(name: 'message_id') required String messageId,

    /// The sender's participant ID (`agt_xxx` for agents).
    @JsonKey(name: 'sender_id') required String senderId,

    /// The sender's participant type (`"agent"` or `"human"`).
    @JsonKey(name: 'sender_type') required String senderType,

    /// The sender's display name (optional — for UI rendering).
    @JsonKey(name: 'sender_name') String? senderName,

    /// The message text content.
    required String text,

    /// Image references attached to the message (`http(s)` or
    /// `data:image/...;base64,` URLs).
    ///
    /// Present when the agent sent vision input. Absent for plain text, so
    /// existing consumers are unaffected.
    @Default(<String>[]) List<String> images,
  }) = _MessageReceivedData;

  factory MessageReceivedData.fromJson(Map<String, dynamic> json) =>
      _$MessageReceivedDataFromJson(json);
}

/// Payload for `reply.delivered` event.
///
/// Sent to the human's WS client to confirm that their reply
/// was delivered to the waiting SSE stream.
///
/// Aligned with Rust `server/src/ws/protocol.rs::reply_delivered`:
/// ```rust
/// pub fn reply_delivered(conversation_id: &str, delivered: bool) -> Event {
///     Event::new("reply.delivered", conversation_id, json!({
///         "delivered": delivered,
///     }))
/// }
/// ```
@freezed
class ReplyDeliveredData with _$ReplyDeliveredData {
  const factory ReplyDeliveredData({
    /// Whether the reply was delivered to a waiting SSE handler.
    required bool delivered,
  }) = _ReplyDeliveredData;

  factory ReplyDeliveredData.fromJson(Map<String, dynamic> json) =>
      _$ReplyDeliveredDataFromJson(json);
}

/// Payload for `capability.updated` event.
///
/// Pushed to all connected human devices when an agent publishes
/// a `capability.manifest` (or when the server auto-extracts
/// capabilities from the HTTP `tools[]` array).
///
/// Aligned with Rust `server/src/ws/protocol.rs::capability_updated`:
/// ```rust
/// pub fn capability_updated(
///     human_id: &str,
///     agent_id: &str,
///     capabilities: &[AgentCapability],
///     context: Option<&AgentContext>,
/// ) -> Event { ... }
/// ```
///
/// Note: `capabilities` and `context` are kept as raw JSON here
/// because the typed `AgentCapability` / `AgentContext` models
/// belong in `capabilities.dart` (to be implemented in a later phase).
/// The `client.dart` layer will convert these to typed models
/// when needed.
@freezed
class CapabilityUpdatedData with _$CapabilityUpdatedData {
  const factory CapabilityUpdatedData({
    /// The agent whose capabilities changed.
    @JsonKey(name: 'agent_id') required String agentId,

    /// Agent's tool list (raw JSON — see `capabilities.dart` for typed model).
    ///
    /// Each element has the shape:
    /// ```json
    /// {
    ///   "id": "github_create_issue",
    ///   "name": "Create GitHub Issue",
    ///   "description": "...",
    ///   "category": "github",
    ///   "input_schema": { ... },
    ///   "output_schema": { ... },
    ///   "ui_schema": { ... },
    ///   "permissions": ["..."],
    ///   "metadata": {}
    /// }
    /// ```
    @JsonKey(name: 'capabilities')
    @Default(<Map<String, dynamic>>[])
    List<Map<String, dynamic>> capabilities,

    /// Agent's runtime context (raw JSON — may be `null`).
    @JsonKey(name: 'context') Map<String, dynamic>? context,
  }) = _CapabilityUpdatedData;

  factory CapabilityUpdatedData.fromJson(Map<String, dynamic> json) =>
      _$CapabilityUpdatedDataFromJson(json);
}

/// Payload for `tool.result` event.
///
/// Pushed to the human's WS client when the agent returns a result
/// for a `tool.invoke` request.
///
/// Aligned with Rust `server/src/ws/protocol.rs::tool_result_event`:
/// ```rust
/// pub fn tool_result_event(
///     human_id: &str,
///     invocation_id: &str,
///     tool_id: &str,
///     status: &str,
///     output: Option<&Value>,
///     error: Option<&str>,
/// ) -> Event { ... }
/// ```
@freezed
class ToolResultData with _$ToolResultData {
  const factory ToolResultData({
    /// Correlates to the original `tool.invoke` request.
    @JsonKey(name: 'invocation_id') required String invocationId,

    /// The tool that was invoked.
    @JsonKey(name: 'tool_id') required String toolId,

    /// Outcome: `"success"`, `"error"`, `"timeout"`, `"cancelled"`, `"pending"`.
    required String status,

    /// Output data (conforming to the tool's `output_schema`).
    /// `null` on error or timeout.
    dynamic output,

    /// Error message if `status` is `"error"`.
    String? error,
  }) = _ToolResultData;

  factory ToolResultData.fromJson(Map<String, dynamic> json) =>
      _$ToolResultDataFromJson(json);
}

/// Payload for `error` event.
///
/// Aligned with Rust `server/src/ws/protocol.rs::error_event`:
/// ```rust
/// pub fn error_event(
///     conversation_id: &str,
///     code: &str,
///     message: &str,
/// ) -> Event { ... }
/// ```
@freezed
class ErrorData with _$ErrorData {
  const factory ErrorData({
    /// Machine-readable error code (e.g., `"tool_not_found"`).
    required String code,

    /// Human-readable error message.
    required String message,
  }) = _ErrorData;

  factory ErrorData.fromJson(Map<String, dynamic> json) =>
      _$ErrorDataFromJson(json);
}

/// Payload for `async.invocation.created` event.
///
/// Sent when an agent submits a turn in async mode. The console must
/// echo [invocationId] back on its `reply.send` so the reply completes
/// this specific invocation — in async mode nobody holds a blocking
/// request open, so there is no reply channel to fall back to.
///
/// Aligned with Rust `server/src/ws/protocol.rs::async_invocation_created`:
/// ```rust
/// pub fn async_invocation_created(conversation_id: &str, invocation_id: &str) -> Event {
///     Event::new("async.invocation.created", conversation_id, json!({
///         "invocation_id": invocation_id,
///     }))
/// }
/// ```
@freezed
class AsyncInvocationCreatedData with _$AsyncInvocationCreatedData {
  const factory AsyncInvocationCreatedData({
    /// The conversation this invocation belongs to (`cnv_` prefixed).
    ///
    /// Injected by the client from the event envelope — the server sends
    /// it as `conversation_id` on the envelope, not inside `data`.
    @JsonKey(name: 'conversation_id') required String conversationId,

    /// The async invocation to complete (`inv_` prefixed).
    @JsonKey(name: 'invocation_id') required String invocationId,
  }) = _AsyncInvocationCreatedData;

  factory AsyncInvocationCreatedData.fromJson(Map<String, dynamic> json) =>
      _$AsyncInvocationCreatedDataFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Client → Server Messages
// ═════════════════════════════════════════════════════════════════

/// A message from the human client to the server.
///
/// Uses a tagged union with `event_type` as the discriminator,
/// aligned with Rust `server/src/ws/protocol.rs::ClientMessage`:
///
/// ```rust
/// #[serde(tag = "event_type")]
/// pub enum ClientMessage {
///     #[serde(rename = "reply.send")]
///     ReplySend { conversation_id: String, text: String },
///     #[serde(rename = "presence.update")]
///     PresenceUpdate { status: String },
///     #[serde(rename = "capability.manifest")]
///     CapabilityManifest { ... },
///     #[serde(rename = "tool.invoke")]
///     ToolInvoke { ... },
/// }
/// ```
///
/// Because freezed does not natively support serde-style `tag` serialization,
/// each variant is a separate freezed class that implements a `toJson` method
/// that injects the `event_type` field. The [ClientMessage.fromWire] factory
/// is not needed for outbound messages — the client only sends, never receives
/// these.
//
// Design note: freezed sealed unions use a `runtimeType` discriminator by
// default, not a custom JSON tag. To match the Rust `#[serde(tag = "event_type")]`
// wire format exactly, we use individual freezed classes (not a single union)
// and provide a [ClientMessage] wrapper with a `wireJson` getter.

// ── reply.send ──

/// `reply.send` — Human sends a reply for an agent's conversation.
///
/// Wire format:
/// ```json
/// {
///   "event_type": "reply.send",
///   "conversation_id": "cnv_xxx",
///   "text": "the reply"
/// }
/// ```
@freezed
class ReplySend with _$ReplySend {
  const ReplySend._();

  const factory ReplySend({
    @JsonKey(name: 'conversation_id') required String conversationId,
    required String text,

    /// Async invocation this reply completes.
    ///
    /// Set when answering a turn delivered in async mode (see
    /// `async.invocation.created`). Without it the server falls back to
    /// the newest pending invocation for the conversation, which is wrong
    /// when several turns are open at once.
    @JsonKey(name: 'invocation_id') String? invocationId,
  }) = _ReplySend;

  factory ReplySend.fromJson(Map<String, dynamic> json) =>
      _$ReplySendFromJson(json);

  /// Serialize to wire JSON with `event_type` tag injected.
  Map<String, dynamic> toWireJson() => {
        'event_type': 'reply.send',
        'conversation_id': conversationId,
        'text': text,
        if (invocationId != null) 'invocation_id': invocationId,
      };
}

// ── presence.update ──

/// `presence.update` — Human updates their presence status.
///
/// Wire format:
/// ```json
/// {
///   "event_type": "presence.update",
///   "status": "online"
/// }
/// ```
@freezed
class PresenceUpdate with _$PresenceUpdate {
  const PresenceUpdate._();

  const factory PresenceUpdate({
    required String status,
  }) = _PresenceUpdate;

  factory PresenceUpdate.fromJson(Map<String, dynamic> json) =>
      _$PresenceUpdateFromJson(json);

  /// Serialize to wire JSON with `event_type` tag injected.
  Map<String, dynamic> toWireJson() => {
        'event_type': 'presence.update',
        'status': status,
      };
}

// ── capability.manifest ──

/// `capability.manifest` — Agent publishes its tool manifest.
///
/// This is an **optional native extension**. The HTTP path
/// (`POST /v1/chat/completions`) automatically extracts tools
/// from the `tools[]` array — this WS event is NOT required
/// for basic operation.
///
/// Wire format:
/// ```json
/// {
///   "event_type": "capability.manifest",
///   "agent_id": "agt_xxx",
///   "capabilities": [ { "id": "...", "name": "...", ... } ],
///   "context": { "agent_id": "...", "system_prompt": "...", ... }
/// }
/// ```
@freezed
class CapabilityManifest with _$CapabilityManifest {
  const CapabilityManifest._();

  const factory CapabilityManifest({
    @JsonKey(name: 'agent_id') required String agentId,
    @JsonKey(name: 'capabilities')
    @Default(<Map<String, dynamic>>[])
    List<Map<String, dynamic>> capabilities,
    Map<String, dynamic>? context,
  }) = _CapabilityManifest;

  factory CapabilityManifest.fromJson(Map<String, dynamic> json) =>
      _$CapabilityManifestFromJson(json);

  /// Serialize to wire JSON with `event_type` tag injected.
  Map<String, dynamic> toWireJson() => {
        'event_type': 'capability.manifest',
        'agent_id': agentId,
        'capabilities': capabilities,
        if (context != null) 'context': context,
      };
}

// ── tool.invoke ──

/// `tool.invoke` — Human requests an agent tool invocation.
///
/// This is an **optional native extension**. The standard OpenAI
/// `tool_calls` response path is used instead — the human (via
/// OpenHuman) returns a `tool_calls` response, and the agent
/// executes the tool and sends back a `role: "tool"` message.
///
/// Wire format:
/// ```json
/// {
///   "event_type": "tool.invoke",
///   "conversation_id": "cnv_xxx",
///   "invocation_id": "inv_xxx",
///   "tool_id": "github_create_issue",
///   "input": { "repo": "...", "title": "..." }
/// }
/// ```
@freezed
class ToolInvokeMessage with _$ToolInvokeMessage {
  const ToolInvokeMessage._();

  const factory ToolInvokeMessage({
    @JsonKey(name: 'conversation_id') required String conversationId,
    @JsonKey(name: 'invocation_id') required String invocationId,
    @JsonKey(name: 'tool_id') required String toolId,
    required dynamic input,

    /// Words the human said alongside the tool call.
    ///
    /// Forwarded so the agent sees them as `content` next to
    /// `tool_calls` — without this the companion prose never arrives.
    String? text,
  }) = _ToolInvokeMessage;

  factory ToolInvokeMessage.fromJson(Map<String, dynamic> json) =>
      _$ToolInvokeMessageFromJson(json);

  /// Serialize to wire JSON with `event_type` tag injected.
  Map<String, dynamic> toWireJson() => {
        'event_type': 'tool.invoke',
        'conversation_id': conversationId,
        'invocation_id': invocationId,
        'tool_id': toolId,
        'input': input,
        if (text != null) 'text': text,
      };
}
