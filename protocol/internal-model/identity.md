# Internal Model: Identity

OpenHuman has two first-class identity types: **HumanIdentity** and **AgentIdentity**.

---

## 1. HumanIdentity

Represents a **real person** who is exposed as an API endpoint.

```json
{
  "id": "hum_0189abc123",
  "display_name": "Alice Chen",
  "avatar_url": "https://cdn.openhuman.dev/avatars/hum_0189abc123.png",
  "status": "online",
  "capabilities": ["answer_questions", "review_design", "provide_feedback"],
  "metadata": {
    "timezone": "Asia/Shanghai",
    "language": "zh-CN",
    "title": "Senior Frontend Engineer"
  },
  "created_at": "2025-01-15T08:00:00Z",
  "updated_at": "2025-01-20T12:30:00Z"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (UUIDv7, `hum_` prefixed) | ✅ | Globally unique human identifier |
| `display_name` | `string` | ✅ | Human-readable name shown to agents and clients |
| `avatar_url` | `string (URI)` | ❌ | Avatar image URL |
| `status` | `enum` | ❌ | `online` · `away` · `offline` (managed by presence system) |
| `capabilities` | `string[]` | ❌ | Capability IDs this human provides (see `capability.md`) |
| `metadata` | `object` | ❌ | Free-form key-value bag (timezone, language, title, etc.) |
| `created_at` | `string (ISO 8601)` | ✅ | Creation timestamp |
| `updated_at` | `string (ISO 8601)` | ✅ | Last modification timestamp |

### Design Notes

- `id` uses UUIDv7 for time-sortable uniqueness. The `hum_` prefix distinguishes
  from agent IDs at a glance and prevents cross-type collisions in composite keys.
- `status` is **not** stored in PostgreSQL as a fixed column — it is a realtime
  value managed by Redis (presence system). It appears in API responses by merging
  Redis state with PG record at read time.
- `metadata` is a JSONB column. It carries user-defined attributes that do not
  warrant schema changes (timezone, language, job title, bio, etc.).
- A single human can have **multiple devices/sessions** (phone, desktop, browser).
  Device identity is tracked separately (see Session model in `event.md`).

---

## 2. AgentIdentity

Represents an **AI agent client** that connects to OpenHuman via the OpenAI-compatible API.

```json
{
  "id": "agt_0189def456",
  "name": "Codex Workspace",
  "client_type": "codex",
  "api_key_id": "key_0189ghi789",
  "capabilities": ["coding", "analysis", "search"],
  "metadata": {
    "model": "gpt-4o",
    "version": "1.0.6",
    "workspace": "openhuman-server"
  },
  "created_at": "2025-01-15T09:00:00Z",
  "updated_at": "2025-01-15T09:00:00Z"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (UUIDv7, `agt_` prefixed) | ✅ | Globally unique agent identifier |
| `name` | `string` | ✅ | Human-readable agent name (set by the agent or its operator) |
| `client_type` | `enum` | ✅ | `codex` · `claude_code` · `trae` · `custom` |
| `api_key_id` | `string` (`key_` prefixed) | ✅ | The API key used for authentication |
| `capabilities` | `string[]` | ❌ | Capability IDs this agent provides (see `capability.md`) |
| `metadata` | `object` | ❌ | Free-form bag (model, version, workspace, etc.) |
| `created_at` | `string (ISO 8601)` | ✅ | Creation timestamp |
| `updated_at` | `string (ISO 8601)` | ✅ | Last modification timestamp |

### Design Notes

- `client_type` is an enum, not a free string. New client types must be registered
  in the protocol. This enables the server to apply client-specific behavior
  (e.g., different SSE keepalive intervals for Codex vs. Claude Code).
- An agent is **not** a "user" in the traditional sense. It has no password.
  Its sole credential is an API Key. OAuth2 is for human-facing flows.
- `api_key_id` is a reference, not the key itself. The key hash is stored in
  the identity layer; only the ID is exposed in API responses.
- `capabilities` on an agent describes what the agent *can do* (e.g., `coding`,
  `analysis`, `search`) — this helps humans understand the agent's value.
  It does **not** grant or revoke tool permissions.

---

## 3. Participant Type Discriminator

Both identity types implement the logical concept of a **Participant** in a conversation.
The internal model uses a `participant_type` field to discriminate:

```json
{
  "participant_id": "hum_0189abc123",
  "participant_type": "human"
}
```

```json
{
  "participant_id": "agt_0189def456",
  "participant_type": "agent"
}
```

This is used in `Conversation.participants[]` and `Message.sender` to avoid
a polymorphic join table while keeping type information explicit.

---

## 4. Relationship to OpenAI API

| OpenAI concept | OpenHuman internal |
|---|---|
| `user` (role in chat message) | `AgentIdentity` — the API *caller* |
| `assistant` (role in chat message) | `HumanIdentity` — the API *responder* |
| `system` (role in chat message) | Synthesized by OpenHuman (not a stored identity) |
| API Key | `AgentIdentity.api_key_id` |

This mapping is **contextual**: from the agent's perspective, *it* is the `user`
and the *human* is the `assistant`. From the human client's perspective, the
agent is the "other party" in the chat. The internal model stores both
identities symmetrically; the role mapping only happens at the OpenAI
compatibility boundary (see `openai-compat/chat-completions.md`).

---

## Appendix A — Implementation notes (2026-10)

Reference: `server/src/model/identity.rs`, `server/src/auth.rs`.

- Only the SHA-256 digest (`key_hash`) of API keys is persisted; lookups
  hash the inbound key. No plaintext column exists (migration `003`
  dropped it).
- WebSocket accepts `Authorization: Bearer` header first, with
  `?api_key=` / `?token=` / `?authorization=` query fallback. Prefer the
  header — query strings leak into access logs.
- No OAuth2 flow is wired up; API keys are the only credential.
