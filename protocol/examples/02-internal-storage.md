# Example 2: Internal Storage

How OpenHuman persists the message from Example 1 across its data stores.

---

## PostgreSQL

### `conversations` table

```sql
-- The conversation record (found or created)
SELECT * FROM conversations WHERE id = 'cnv_0189abc123def456';
```

| id | type | status | title | metadata | created_at | updated_at | last_message_at |
|---|---|---|---|---|---|---|---|
| cnv_0189abc123def456 | agent_human | active | Code Review — Auth Module | `{"system_prompt": "You are a senior Rust engineer...", "tags": ["rust","auth"]}` | 2025-01-15 09:00:00 | 2025-01-15 09:28:00 | 2025-01-15 09:28:00 |

### `conversation_participants` table

| conversation_id | participant_id | participant_type | joined_at | role |
|---|---|---|---|---|
| cnv_0189abc123def456 | agt_0189def456 | agent | 2025-01-15 09:00:00 | initiator |
| cnv_0189abc123def456 | hum_0189abc123 | human | 2025-01-15 09:00:05 | responder |

### `messages` table

```sql
SELECT * FROM messages WHERE conversation_id = 'cnv_0189abc123def456'
ORDER BY created_at DESC LIMIT 1;
```

| id | conversation_id | sender_id | sender_type | content_type | content_text | attachments | metadata | status | created_at |
|---|---|---|---|---|---|---|---|---|---|
| msg_0189f8e7d6c5b4a3 | cnv_0189abc123def456 | agt_0189def456 | agent | text | `Review this auth middleware...` | `[]` | `{"openai_model":"human","openai_role":"user","client_type":"codex"}` | pending | 2025-01-15 09:28:00 |

> **Note**: `content_text` is shown here as a flat column for illustration.
> In practice, `content` is stored as JSONB to support `text`, `structured`,
> and `multipart` types uniformly. The `content_type` column acts as a
> discriminator for query filtering.

### `identities` (agent)

| id | name | client_type | api_key_id | capabilities | metadata | created_at |
|---|---|---|---|---|---|---|
| agt_0189def456 | Codex Workspace | codex | key_0189ghi789 | `["coding","analysis","search"]` | `{"model":"gpt-4o","version":"1.0.6"}` | 2025-01-15 09:00:00 |

### `identities` (human)

| id | display_name | avatar_url | capabilities | metadata | created_at |
|---|---|---|---|---|---|
| hum_0189abc123 | Alice Chen | https://cdn...png | `["answer_questions","review_design","provide_feedback"]` | `{"timezone":"Asia/Shanghai","language":"zh-CN","title":"Senior Frontend Engineer"}` | 2025-01-15 08:00:00 |

---

## Redis

### Presence

```
# Key: presence:hum_0189abc123
# Value:
{
  "status": "online",
  "device_id": "dev_flutter_pixel8",
  "last_seen": 1736936480
}
```

### SSE Connection Registry

```
# Key: sse:agt_0189def456:cnv_0189abc123def456
# Value: connection metadata (node ID, started_at, keepalive_interval)
```

This allows the server to know which node holds the agent's open SSE connection,
so when the human replies, the message can be routed to the correct node for
SSE delivery.

---

## NATS JetStream

### Event Publication

```
Subject: openhuman.events.cnv_0189abc123def456

Message:
{
  "event_id": "evt_0189evt0001",
  "event_type": "message.created",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:28:00.123Z",
  "data": {
    "message": { ... }
  }
}
```

### Consumers

| Consumer | Purpose | Durable Name |
|---|---|---|
| Notification Service | Push to human devices | `notif-durable` |
| Sync Service | Multi-device consistency | `sync-durable` |
| Audit Log | Compliance record | `audit-durable` |

Each consumer independently ACKs the event. If a consumer is down, JetStream
redelivers on its schedule.

---

## Data Flow Summary

```
Agent HTTP Request
    ↓
API Gateway (Axum)
    ↓
Auth Service → validate API key → resolve Agent + Human
    ↓
Messaging Service → find/create Conversation → store Message (PostgreSQL)
    ↓
Redis → register SSE connection (for later response delivery)
    ↓
NATS JetStream → publish message.created event
    ↓
WebSocket Gateway → push event to Human Client (Redis pub/sub for device routing)
    ↓
[SSE connection held open, sending keepalive comments]
    ↓
Waiting for human response... (see Example 3)
```
