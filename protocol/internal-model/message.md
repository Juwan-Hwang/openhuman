# Internal Model: Message

The Message entity is the atomic unit of communication in OpenHuman.

---

## 1. Design Principle

The internal message model is **symmetric and role-neutral**.

It does **not** use `role: user` / `role: assistant` as primary fields.
Instead, every message records a `sender` (a Participant) and a `content` block.
The OpenAI role mapping is applied only at the compatibility boundary.

> **Critical**: In OpenHuman, `assistant` does **not** mean "AI".
> It means "the API responder" — which is the **Human**.
> The `user` role maps to the **Agent** (the API caller).
> See `openai-compat/chat-completions.md` for the full mapping.

---

## 2. Message Entity

```json
{
  "id": "msg_0189abc123def456789",
  "conversation_id": "cnv_0189abc123def456",
  "sender": {
    "participant_id": "agt_0189def456",
    "participant_type": "agent"
  },
  "content": {
    "type": "text",
    "text": "Can you review the auth middleware in src/auth.rs?"
  },
  "attachments": [],
  "metadata": {
    "openai_model": "gpt-4o",
    "client_message_id": "req_abc123"
  },
  "status": "delivered",
  "created_at": "2025-01-15T09:28:00Z"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (UUIDv7, `msg_` prefixed) | ✅ | Globally unique message ID |
| `conversation_id` | `string` (`cnv_` prefixed) | ✅ | Parent conversation |
| `sender` | `ParticipantRef` | ✅ | Who sent this message |
| `content` | `ContentBlock` | ✅ | The message payload (see §3) |
| `attachments` | `Attachment[]` | ❌ | Attached files (see §4) |
| `metadata` | `object` | ❌ | Free-form bag (model name, client message ID, trace IDs) |
| `status` | `enum` | ✅ | Delivery lifecycle (see §5) |
| `created_at` | `string (ISO 8601)` | ✅ | Server-side creation timestamp |

---

## 3. ContentBlock

A message has exactly one `content` block. The `type` field discriminates the shape.

### 3.1 TextContent

```json
{
  "type": "text",
  "text": "Review the auth module, focusing on token validation."
}
```

| Field | Type | Description |
|---|---|---|
| `type` | `"text"` | Discriminator |
| `text` | `string` | Plain text (UTF-8, no length limit enforced at protocol level) |

### 3.2 StructuredContent

For rich, interactive payloads — e.g., a code diff, a design review request,
or a structured form. The `schema` field follows JSON Schema draft 2020-12.

```json
{
  "type": "structured",
  "schema": {
    "type": "object",
    "properties": {
      "files": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "path": { "type": "string" },
            "diff": { "type": "string" }
          }
        }
      }
    }
  },
  "data": {
    "files": [
      {
        "path": "src/auth.rs",
        "diff": "@@ -12,7 +12,9 @@ fn validate_token(token: &str) -> Result<Claims> {"
      }
    ]
  }
}
```

| Field | Type | Description |
|---|---|---|
| `type` | `"structured"` | Discriminator |
| `schema` | `object (JSON Schema)` | Describes the shape of `data` |
| `data` | `object` | The actual payload, validated against `schema` |

The Flutter client uses `schema` to select an appropriate renderer
(JSON Schema Renderer per architecture spec §9).

### 3.3 MultiPartContent

When a message contains multiple parts (e.g., text + structured), the
content type is `multipart`:

```json
{
  "type": "multipart",
  "parts": [
    {
      "type": "text",
      "text": "Here's the diff I need reviewed:"
    },
    {
      "type": "structured",
      "schema": { "type": "string" },
      "data": "--- a/src/auth.rs\n+++ b/src/auth.rs\n@@ -12,7 +12,9 @@"
    }
  ]
}
```

---

## 4. Attachment

Files attached to a message. Stored as object references (S3 / file system),
not inline.

```json
{
  "id": "att_0189xyz",
  "filename": "auth-review.pdf",
  "content_type": "application/pdf",
  "size_bytes": 245678,
  "url": "https://cdn.openhuman.dev/attachments/att_0189xyz"
}
```

| Field | Type | Description |
|---|---|---|
| `id` | `string` (`att_` prefixed) | Unique attachment ID |
| `filename` | `string` | Original filename |
| `content_type` | `string (MIME)` | MIME type |
| `size_bytes` | `integer` | File size in bytes |
| `url` | `string (URI)` | Download URL (time-limited presigned) |

---

## 5. Message Status (Delivery Lifecycle)

```
pending → sent → delivered → read
                       ↓
                    failed
```

| Status | Trigger | Description |
|---|---|---|
| `pending` | Message created, not yet pushed to recipient | Queued for delivery |
| `sent` | Pushed via WebSocket / notification | Recipient's client received the push |
| `delivered` | Recipient's client ACKed receipt | Confirmed delivery |
| `read` | Recipient opened / viewed the message | Human or agent client marked as read |
| `failed` | Delivery exhausted retries | Error stored in `metadata.error` |

---

## 6. OpenAI Role Mapping

This is the **only** place where OpenAI roles appear. The internal model
itself never stores `role: user` or `role: assistant`.

### 6.1 Inbound (Agent → OpenHuman)

When an agent calls `POST /v1/chat/completions`:

| OpenAI `role` | Internal mapping |
|---|---|
| `user` | `sender = AgentIdentity`, `content.text = message.content` |
| `system` | Stored as metadata on the conversation, not as a message |
| `assistant` | Previous messages from the human (context continuation) |

### 6.2 Outbound (OpenHuman → Agent)

When the human replies and OpenHuman streams the response back via SSE:

| Internal sender | OpenAI `role` in response |
|---|---|
| `HumanIdentity` | `assistant` |
| `AgentIdentity` | `user` (should not normally appear in response; logged only) |

### 6.3 Full Mapping Table

```
Agent sends:  role=user     "Review this code"     →  Message{sender=Agent, content=text}
Human sends:  (via Flutter) "Looks good, ship it"  →  Message{sender=Human,  content=text}
                                                              ↓
                                                    OpenAI response: role=assistant, content="Looks good, ship it"
```

> The mapping is **per-conversation, per-API-key**. The same human can be
> `assistant` in one conversation (agent_human) and `user` in another
> (human_human, if the other party is querying via API). This is why the
> internal model must be role-neutral.

---

## Appendix A — Implementation notes (2026-10)

Reference: `server/src/model/message.rs`.

- `visibility` (`human_visible` / `internal_only`) exists on the model:
  tool results and context replay are stored but hidden from the timeline.
- `status` lifecycle: `pending` → `delivered` on live push or backlog
  drain. `mark_delivered` never overwrites `read` / `failed`.
- Only `pending` messages are pushed on connect; full history is fetched
  over HTTP, never replayed over the socket.
