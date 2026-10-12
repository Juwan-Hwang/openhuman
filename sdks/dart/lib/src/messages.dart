/// OpenHuman Dart SDK — Message models.
///
/// This file implements the internal message data model, aligned
/// 1:1 with the Rust server implementation:
///
///   - `server/src/model/message.rs`   — Message struct + MessageStatus enum
///   - `server/src/model/content.rs`   — ContentBlock enum + Attachment struct
///   - `server/src/model/identity.rs`  — ParticipantRef + ParticipantType
///
/// and the protocol specification:
///
///   - `protocol/internal-model/message.md`   — message entity, content blocks, attachments
///   - `protocol/internal-model/identity.md`  — participant ref, participant type
///
/// # Design Principle
///
/// The internal message model is **symmetric and role-neutral**.
/// It does NOT use OpenAI `role: user` / `role: assistant` as
/// primary fields. Every message records a `sender` (a
/// [ParticipantRef]) and a [ContentBlock]. The OpenAI role mapping
/// is applied only at the server's `openai_compat` boundary.
///
/// # ContentBlock Wire Format
///
/// Rust uses `#[serde(tag = "type")]` — a tagged union where the
/// `"type"` field discriminates the variant:
///
/// ```json
/// { "type": "text", "text": "..." }
/// { "type": "structured", "schema": {...}, "data": {...} }
/// { "type": "multipart", "parts": [...] }
/// ```
///
/// In Dart, freezed's union with a `type` discriminator is implemented
/// via a sealed class pattern with `@JsonKey` on the `type` field.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

// HumanStatus is defined in events.dart to avoid duplication.
// We re-export it here so consumers of messages.dart don't need
// to import events.dart separately for this shared enum.
export 'events.dart' show HumanStatus;

part 'messages.freezed.dart';
part 'messages.g.dart';

// ═════════════════════════════════════════════════════════════════
//  Enums
// ═════════════════════════════════════════════════════════════════

/// Participant type discriminator.
///
/// Aligned with Rust `server/src/model/identity.rs::ParticipantType`:
/// ```rust
/// #[serde(rename_all = "lowercase")]
/// pub enum ParticipantType { Human, Agent }
/// ```
///
/// JSON wire format: `"human"` or `"agent"`.
///
/// See: `protocol/internal-model/identity.md §3`
@JsonEnum(alwaysCreate: true, fieldRename: FieldRename.none)
enum ParticipantType {
  /// A real person exposed as an API endpoint.
  @JsonValue('human')
  human,

  /// An AI agent client (Codex, Claude Code, Trae, custom).
  @JsonValue('agent')
  agent,
}

/// Delivery lifecycle of a message.
///
/// Aligned with Rust `server/src/model/message.rs::MessageStatus`:
/// ```rust
/// #[serde(rename_all = "lowercase")]
/// pub enum MessageStatus { Pending, Sent, Delivered, Read, Failed }
/// ```
///
/// Lifecycle:
/// ```
/// pending → sent → delivered → read
///                  ↓
///               failed
/// ```
///
/// See: `protocol/internal-model/message.md §5`
@JsonEnum(alwaysCreate: true, fieldRename: FieldRename.none)
enum MessageStatus {
  /// Message created, not yet pushed to recipient.
  @JsonValue('pending')
  pending,

  /// Pushed via WebSocket / notification. Recipient's client received the push.
  @JsonValue('sent')
  sent,

  /// Recipient's client ACKed receipt.
  @JsonValue('delivered')
  delivered,

  /// Recipient opened / viewed the message.
  @JsonValue('read')
  read,

  /// Delivery exhausted retries. Error stored in `metadata.error`.
  @JsonValue('failed')
  failed,
}

// ═════════════════════════════════════════════════════════════════
//  Participant Reference
// ═════════════════════════════════════════════════════════════════

/// A lightweight reference to a participant — used in Message and
/// Conversation.
///
/// Aligned with Rust `server/src/model/identity.rs::ParticipantRef`:
/// ```rust
/// pub struct ParticipantRef {
///     pub participant_id: String,
///     pub participant_type: ParticipantType,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "participant_id": "hum_0189abc123",
///   "participant_type": "human"
/// }
/// ```
///
/// See: `protocol/internal-model/identity.md §3`
@freezed
class ParticipantRef with _$ParticipantRef {
  const factory ParticipantRef({
    /// `HumanIdentity.id` or `AgentIdentity.id`.
    @JsonKey(name: 'participant_id') required String participantId,

    /// Whether this participant is a human or an agent.
    @JsonKey(name: 'participant_type') required ParticipantType participantType,
  }) = _ParticipantRef;

  factory ParticipantRef.fromJson(Map<String, dynamic> json) =>
      _$ParticipantRefFromJson(json);

  /// Convenience: create a human participant reference.
  ///
  /// Aligned with Rust `ParticipantRef::human(id)`.
  static ParticipantRef human(String id) => ParticipantRef(
        participantId: id,
        participantType: ParticipantType.human,
      );

  /// Convenience: create an agent participant reference.
  ///
  /// Aligned with Rust `ParticipantRef::agent(id)`.
  static ParticipantRef agent(String id) => ParticipantRef(
        participantId: id,
        participantType: ParticipantType.agent,
      );
}

// ═════════════════════════════════════════════════════════════════
//  Content Blocks
// ═════════════════════════════════════════════════════════════════

/// The payload of a [OpenHumanMessage]. Exactly one variant per message.
///
/// Aligned with Rust `server/src/model/content.rs::ContentBlock`:
/// ```rust
/// #[serde(tag = "type")]
/// pub enum ContentBlock {
///     #[serde(rename = "text")]
///     Text { text: String },
///     #[serde(rename = "structured")]
///     Structured { schema: Value, data: Value },
///     #[serde(rename = "multipart")]
///     Multipart { parts: Vec<ContentBlock> },
/// }
/// ```
///
/// JSON wire format uses a `"type"` discriminator field:
///
/// **Text:**
/// ```json
/// { "type": "text", "text": "Review the auth module." }
/// ```
///
/// **Structured:**
/// ```json
/// {
///   "type": "structured",
///   "schema": { "type": "object", ... },
///   "data": { "files": [...] }
/// }
/// ```
///
/// **Multipart:**
/// ```json
/// {
///   "type": "multipart",
///   "parts": [
///     { "type": "text", "text": "Here's the diff:" },
///     { "type": "structured", "schema": {...}, "data": {...} }
///   ]
/// }
/// ```
///
/// See: `protocol/internal-model/message.md §3`
///
/// # Freezed Union Serialization
///
/// Rust uses `#[serde(tag = "type")]` for the tagged union. In freezed,
/// we use a sealed union with `@FreezedUnionValue("type")` so the
/// generated `fromJson` / `toJson` uses the `"type"` field as the
/// discriminator — matching the Rust wire format exactly.
@Freezed(unionKey: 'type')
sealed class ContentBlock with _$ContentBlock {
  /// Plain text content.
  ///
  /// Aligned with Rust `ContentBlock::Text { text: String }`.
  const factory ContentBlock.text({
    required String text,
  }) = TextContent;

  /// Structured content with a JSON Schema describing the shape of `data`.
  ///
  /// The Flutter client uses `schema` to select an appropriate renderer
  /// (JSON Schema Renderer per architecture spec §9).
  ///
  /// Aligned with Rust `ContentBlock::Structured { schema: Value, data: Value }`.
  const factory ContentBlock.structured({
    required Map<String, dynamic> schema,
    required dynamic data,
  }) = StructuredContent;

  /// Multipart content — a list of [ContentBlock] parts.
  ///
  /// Used when a message contains multiple parts (e.g., text + structured).
  ///
  /// Aligned with Rust `ContentBlock::Multipart { parts: Vec<ContentBlock> }`.
  const factory ContentBlock.multipart({
    required List<ContentBlock> parts,
  }) = MultipartContent;

  factory ContentBlock.fromJson(Map<String, dynamic> json) =>
      _$ContentBlockFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Attachment
// ═════════════════════════════════════════════════════════════════

/// An attachment reference (file, image, etc.).
///
/// Stored as object references (S3 / file system), not inline.
///
/// Aligned with Rust `server/src/model/content.rs::Attachment`:
/// ```rust
/// pub struct Attachment {
///     pub id: String,
///     pub filename: String,
///     pub content_type: String,
///     pub size_bytes: u64,
///     pub url: String,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "id": "att_0189xyz",
///   "filename": "auth-review.pdf",
///   "content_type": "application/pdf",
///   "size_bytes": 245678,
///   "url": "https://cdn.openhuman.dev/attachments/att_0189xyz"
/// }
/// ```
///
/// See: `protocol/internal-model/message.md §4`
@freezed
class Attachment with _$Attachment {
  const factory Attachment({
    /// Unique attachment ID (`att_` prefixed).
    required String id,

    /// Original filename.
    required String filename,

    /// MIME type (e.g., `"application/pdf"`, `"image/png"`).
    @JsonKey(name: 'content_type') required String contentType,

    /// File size in bytes.
    @JsonKey(name: 'size_bytes') required int sizeBytes,

    /// Download URL (time-limited presigned).
    required String url,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Message
// ═════════════════════════════════════════════════════════════════

/// A single message in a conversation.
///
/// The model is **role-neutral**: it stores `sender` (a
/// [ParticipantRef]), not an OpenAI `role`. The `user` / `assistant`
/// mapping happens only at the server's `openai_compat` boundary.
///
/// Aligned with Rust `server/src/model/message.rs::Message`:
/// ```rust
/// pub struct Message {
///     pub id: String,
///     pub conversation_id: String,
///     pub sender: ParticipantRef,
///     pub content: ContentBlock,
///     #[serde(default)]
///     pub attachments: Vec<Attachment>,
///     #[serde(default)]
///     pub metadata: HashMap<String, Value>,
///     pub status: MessageStatus,
///     pub created_at: DateTime<Utc>,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "id": "msg_0189abc123def456789",
///   "conversation_id": "cnv_0189abc123def456",
///   "sender": {
///     "participant_id": "agt_0189def456",
///     "participant_type": "agent"
///   },
///   "content": {
///     "type": "text",
///     "text": "Review the auth middleware."
///   },
///   "attachments": [],
///   "metadata": {},
///   "status": "pending",
///   "created_at": "2025-01-15T09:28:00Z"
/// }
/// ```
///
/// See: `protocol/internal-model/message.md §2`
@freezed
class OpenHumanMessage with _$OpenHumanMessage {
  const factory OpenHumanMessage({
    /// Globally unique message ID (`msg_` prefixed, UUIDv7).
    required String id,

    /// Parent conversation ID (`cnv_` prefixed).
    @JsonKey(name: 'conversation_id') required String conversationId,

    /// Who sent this message.
    required ParticipantRef sender,

    /// The message payload (text, structured, or multipart).
    required ContentBlock content,

    /// Attached files (may be empty).
    @Default(<Attachment>[]) List<Attachment> attachments,

    /// Free-form metadata bag (model name, client message ID, trace IDs, ...).
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,

    /// Delivery lifecycle status.
    required MessageStatus status,

    /// Server-side creation timestamp.
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _OpenHumanMessage;

  factory OpenHumanMessage.fromJson(Map<String, dynamic> json) =>
      _$OpenHumanMessageFromJson(json);
}
