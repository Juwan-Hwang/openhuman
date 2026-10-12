# Internal Model: Event

Events are the **realtime notification** mechanism. They flow over two channels:

- **WebSocket** — pushed to connected human clients (Flutter, desktop, web)
- **NATS JetStream** — durable event bus for server-internal consumers
  (notification service, sync service, audit log)

---

## 1. Event Envelope

Every event shares a common envelope:

```json
{
  "event_id": "evt_0189abc123",
  "event_type": "message.created",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:28:00.123Z",
  "data": {
    // event-specific payload
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `event_id` | `string` (UUIDv7, `evt_` prefixed) | ✅ | Unique event ID (idempotency key) |
| `event_type` | `string` | ✅ | Dotted event name (see §2) |
| `conversation_id` | `string` | ✅ | Scope: which conversation this event belongs to |
| `timestamp` | `string` (ISO 8601, ms precision) | ✅ | Server-side event time |
| `data` | `object` | ✅ | Event-specific payload |

---

## 2. Event Types

### 2.1 Message Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `message.created` | A new message is stored | `{ "message": Message }` |
| `message.updated` | Message status changed | `{ "message_id": "...", "status": "...", "prev_status": "..." }` |
| `message.deleted` | Message soft-deleted | `{ "message_id": "..." }` |

#### Example: `message.created`

```json
{
  "event_id": "evt_0189abc123",
  "event_type": "message.created",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:28:00.123Z",
  "data": {
    "message": {
      "id": "msg_0189abc123def456789",
      "conversation_id": "cnv_0189abc123def456",
      "sender": {
        "participant_id": "agt_0189def456",
        "participant_type": "agent"
      },
      "content": {
        "type": "text",
        "text": "Review the auth module."
      },
      "status": "pending",
      "created_at": "2025-01-15T09:28:00Z"
    }
  }
}
```

### 2.2 Presence Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `presence.changed` | A human's online status changed | `{ "human_id": "...", "status": "online|away|offline", "device_id": "..." }` |

#### Example: `presence.changed`

```json
{
  "event_id": "evt_0189xyz789",
  "event_type": "presence.changed",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:25:00Z",
  "data": {
    "human_id": "hum_0189abc123",
    "status": "online",
    "device_id": "dev_flutter_pixel8"
  }
}
```

> `conversation_id` for presence events is set to the human's "presence channel"
  conversation ID (a synthetic always-present conversation). This keeps the
  envelope uniform.

### 2.3 Session Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `session.connected` | A WebSocket connection established | `{ "participant_id": "...", "participant_type": "...", "device_id": "..." }` |
| `session.disconnected` | WebSocket closed | `{ "participant_id": "...", "device_id": "...", "reason": "..." }` |

#### Example: `session.connected`

```json
{
  "event_id": "evt_0189sess001",
  "event_type": "session.connected",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:00:00Z",
  "data": {
    "participant_id": "hum_0189abc123",
    "participant_type": "human",
    "device_id": "dev_flutter_iphone15"
  }
}
```

### 2.4 Conversation Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `conversation.created` | New conversation started | `{ "conversation": Conversation }` |
| `conversation.updated` | Title/status/metadata changed | `{ "conversation_id": "...", "changes": {} }` |
| `conversation.archived` | Conversation archived | `{ "conversation_id": "..." }` |

### 2.5 Capability Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `capability.updated` | A participant's capabilities changed | `{ "participant_id": "...", "added": [...], "removed": [...] }` |

### 2.6 Typing Events

| Event Type | Trigger | `data` Payload |
|---|---|---|
| `typing.started` | Participant started typing | `{ "participant_id": "...", "conversation_id": "..." }` |
| `typing.stopped` | Participant stopped typing | `{ "participant_id": "...", "conversation_id": "..." }` |

---

## 3. Delivery Semantics

### WebSocket (Human Client)

- Events are pushed to all connected devices of a participant.
- Delivery is **at-least-once**. Clients use `event_id` for deduplication.
- If a client is offline, events are buffered. On reconnect, the client
  requests missed events via a `since` cursor (event timestamp or sequence).

### NATS JetStream (Server-Internal)

- Events are published to a JetStream stream named `openhuman.events`.
- Consumers (notification, sync, audit) have their own durable consumer names.
- JetStream provides **at-least-once** with redelivery and ack timeouts.

### SSE (Server → Agent Client)

- The OpenAI-compatible streaming endpoint (`POST /v1/chat/completions` with
  `stream: true`) converts `message.created` events from the human into
  SSE chunks in OpenAI `chat.completion.chunk` format.
- This is **not** raw event passthrough — the event is **translated** by the
  compatibility layer (see `openai-compat/chat-completions.md`).

---

## 4. Event Ordering

- Events within a single conversation are **causally ordered** by `timestamp`.
- `event_id` (UUIDv7) is monotonically increasing per server instance, providing
  a tiebreaker for sub-millisecond collisions.
- Clients should sort by `(timestamp, event_id)` to establish a total order.
- The server does not guarantee global ordering across different conversations.

---

## Appendix A — Implementation notes (2026-10)

The table above is the Phase 2 design. The shipped wire format differs in
the following ways (reference: `server/src/ws/protocol.rs`):

- Implemented Server → Client types: `session.connected`,
  `message.received` (with optional `images[]`), `reply.delivered`,
  `capability.updated`, `tool.result`, `async.invocation.created`, `error`.
  The `message.*` / `conversation.*` / `presence.*` families from §2 are
  not emitted.
- `message.received` carries `sender_name?` in addition to the §3 payload.
- `tool.result` carries `invocation_id` (the OpenAI call id) for
  correlation — see `tool_result_event`.
- `conversation_id` on `session.connected` / `capability.updated` is the
  human id (routing key), not a conversation.
- Client → Server adds `end.turn` (`conversation_id`), and `reply.send`
  / `tool.invoke` carry optional `invocation_id` / `text` respectively.
- NATS JetStream transport is not implemented; events travel over
  WebSocket only.
