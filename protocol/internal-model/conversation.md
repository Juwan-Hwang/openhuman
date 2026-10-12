# Internal Model: Conversation

A Conversation is a **communication context** between two or more participants.

---

## 1. Conversation Entity

```json
{
  "id": "cnv_0189abc123def456",
  "type": "agent_human",
  "participants": [
    {
      "participant_id": "agt_0189def456",
      "participant_type": "agent",
      "joined_at": "2025-01-15T09:00:00Z",
      "role": "initiator"
    },
    {
      "participant_id": "hum_0189abc123",
      "participant_type": "human",
      "joined_at": "2025-01-15T09:00:05Z",
      "role": "responder"
    }
  ],
  "title": "Code Review — Authentication Module",
  "status": "active",
  "metadata": {
    "priority": "normal",
    "tags": ["rust", "auth"]
  },
  "created_at": "2025-01-15T09:00:00Z",
  "updated_at": "2025-01-15T09:30:00Z",
  "last_message_at": "2025-01-15T09:28:00Z"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (UUIDv7, `cnv_` prefixed) | ✅ | Globally unique conversation ID |
| `type` | `enum` | ✅ | `agent_human` · `human_human` |
| `participants` | `ParticipantRef[]` | ✅ | Ordered list of participants (min 2) |
| `title` | `string` | ❌ | Optional display title (auto-generated if absent) |
| `status` | `enum` | ❌ | `active` · `archived` · `closed` |
| `metadata` | `object` | ❌ | Free-form key-value bag |
| `created_at` | `string (ISO 8601)` | ✅ | Creation timestamp |
| `updated_at` | `string (ISO 8601)` | ✅ | Last modification timestamp |
| `last_message_at` | `string (ISO 8601)` | ❌ | Timestamp of most recent message (for sorting) |

---

## 2. ParticipantRef

A lightweight reference to a participant within a conversation. This is an
**embedded** struct, not a separate entity — it lives inside the Conversation.

```json
{
  "participant_id": "hum_0189abc123",
  "participant_type": "human",
  "joined_at": "2025-01-15T09:00:05Z",
  "role": "responder"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `participant_id` | `string` | ✅ | `HumanIdentity.id` or `AgentIdentity.id` |
| `participant_type` | `enum` | ✅ | `human` · `agent` |
| `joined_at` | `string (ISO 8601)` | ✅ | When this participant joined the conversation |
| `role` | `enum` | ❌ | `initiator` · `responder` · `observer` |

### Role Semantics

- **`initiator`** — started the conversation (e.g., the agent that called the API).
- **`responder`** — the party expected to reply (e.g., the human endpoint).
- **`observer`** — read-only participant (future: multi-party conversations, audits).

Roles are informational, not a permission system. They help the UI render
the conversation correctly (who is "me" vs. "the other side").

---

## 3. Conversation Types

### `agent_human`

The primary use case. An AI agent (Codex, Claude Code, Trae, custom) initiates
a conversation with a human endpoint via the OpenAI-compatible API.

```
Agent (initiator)  ↔  Human (responder)
```

### `human_human`

A direct human-to-human conversation through the OpenHuman client. This is
**not** routed through the OpenAI API; it uses the internal protocol directly.

```
Human A (initiator)  ↔  Human B (responder)
```

> `agent_agent` is intentionally **not** supported. Agent-to-agent communication
> should use existing MCP / A2A protocols, not OpenHuman.

---

## 4. Lifecycle

```
created → active → archived → closed
                       ↑
                  (can be reactivated)
```

| State | Description |
|---|---|
| `created` | Conversation exists but no message has been sent yet |
| `active` | At least one message has been exchanged; ongoing |
| `archived` | Soft-hidden by a participant; still queryable |
| `closed` | No more messages can be sent; historical record only |

---

## 5. Relationship to OpenAI API

In the OpenAI Chat Completions API, a "conversation" is implicit — it is the
sequence of `messages[]` in the request body. There is no conversation ID.

OpenHuman **creates or resolves** a conversation internally:

1. Agent sends `POST /v1/chat/completions` with `messages[]`.
2. OpenHuman checks the API key → resolves `AgentIdentity`.
3. The API key is bound to a specific `HumanIdentity` (the human endpoint).
4. OpenHuman finds or creates a conversation between this agent and human.
5. Messages are stored with `conversation_id` linking them together.

The conversation ID is **never exposed** in the OpenAI-compatible API surface.
It is an internal correlation key. SDK clients (Flutter, Dart SDK) do see it.

```json
// OpenAI request → internal mapping
{
  "messages": [
    {"role": "user", "content": "Review this auth code"}
  ]
}
// ↓ OpenHuman internal
{
  "conversation_id": "cnv_0189abc123def456",
  "participant_agent": "agt_0189def456",
  "participant_human": "hum_0189abc123"
}
```

---

## Appendix A — Implementation notes (2026-10)

Reference: `server/src/model/conversation.rs`, `server/src/api/history.rs`.

- Scope is **(agent, human, session)**; the session key is namespaced
  (`hdr:` / `cnv:` / `ses:` / `usr:` / `meta:` / `prm:` / `cli:`) so equal
  strings from different sources cannot collide.
- Trash model: `deleted_at IS NULL` = live; set = restorable trash.
  `DELETE .../permanent` destroys. All scoped to the owning human.
