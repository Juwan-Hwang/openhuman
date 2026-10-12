# Example 1: Agent Sends a Message (OpenAI Format)

This example shows a **Codex agent** sending a code review request to a human
via the OpenAI Chat Completions API.

---

## Agent Configuration (Codex)

```yaml
# Codex config
base_url: https://api.openhuman.dev/v1
api_key: ohk_live_aB3dEf6GhI9jKlMn0pQ
model: human
```

---

## Agent Request

```http
POST /v1/chat/completions HTTP/1.1
Host: api.openhuman.dev
Authorization: Bearer ohk_live_aB3dEf6GhI9jKlMn0pQ
Content-Type: application/json

{
  "model": "human",
  "messages": [
    {
      "role": "system",
      "content": "You are a senior Rust engineer. Provide concise code reviews."
    },
    {
      "role": "user",
      "content": "Review this auth middleware:\n\n```rust\nfn validate_token(token: &str) -> Result<Claims> {\n    let parts: Vec<&str> = token.split('.').collect();\n    if parts.len() != 3 {\n        return Err(AuthError::InvalidToken);\n    }\n    let claims = decode_jwt(&parts[1])?;\n    Ok(claims)\n}\n```\n\nFocus on security."
    }
  ],
  "stream": true
}
```

---

## OpenHuman Inbound Processing

### Step 1: Authenticate

```
API Key: ohk_live_aB3dEf6GhI9jKlMn0pQ
  → lookup in identity layer
  → AgentIdentity:
      id:           agt_0189def456
      name:         "Codex Workspace"
      client_type:  "codex"
      api_key_id:   key_0189ghi789
```

### Step 2: Resolve Bound Human

```
API Key is bound to HumanIdentity:
  → HumanIdentity:
      id:            hum_0189abc123
      display_name:  "Alice Chen"
      status:        "online"
      capabilities:  ["answer_questions", "review_design", "provide_feedback"]
```

### Step 3: Find or Create Conversation

```
Search: conversation WHERE participants includes (agt_0189def456, agent) AND (hum_0189abc123, human)
  → Found (or created):
      Conversation:
        id:     cnv_0189abc123def456
        type:   agent_human
        status: active
        metadata.system_prompt: "You are a senior Rust engineer..."
```

### Step 4: Store Messages

The `system` message is stored as conversation metadata, not as a Message.

The `user` message is stored as an internal Message:

```json
{
  "id": "msg_0189f8e7d6c5b4a3",
  "conversation_id": "cnv_0189abc123def456",
  "sender": {
    "participant_id": "agt_0189def456",
    "participant_type": "agent"
  },
  "content": {
    "type": "text",
    "text": "Review this auth middleware:\n\n```rust\nfn validate_token(token: &str) -> Result<Claims> {\n    let parts: Vec<&str> = token.split('.').collect();\n    if parts.len() != 3 {\n        return Err(AuthError::InvalidToken);\n    }\n    let claims = decode_jwt(&parts[1])?;\n    Ok(claims)\n}\n```\n\nFocus on security."
  },
  "attachments": [],
  "metadata": {
    "openai_model": "human",
    "openai_role": "user",
    "client_type": "codex"
  },
  "status": "pending",
  "created_at": "2025-01-15T09:28:00Z"
}
```

### Step 5: Push to Human Client

A `message.created` event is emitted via WebSocket to all of Alice's
connected devices:

```json
{
  "event_id": "evt_0189evt0001",
  "event_type": "message.created",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:28:00.123Z",
  "data": {
    "message": {
      "id": "msg_0189f8e7d6c5b4a3",
      "conversation_id": "cnv_0189abc123def456",
      "sender": {
        "participant_id": "agt_0189def456",
        "participant_type": "agent"
      },
      "content": {
        "type": "text",
        "text": "Review this auth middleware: ..."
      },
      "status": "pending",
      "created_at": "2025-01-15T09:28:00Z"
    }
  }
}
```

### Step 6: SSE Keepalive

While waiting for Alice to respond, OpenHuman sends keepalive comments
to the agent's open HTTP connection:

```
: keepalive 1736936485
: keepalive 1736936490
: keepalive 1736936495
```

---

## What the Human Client Sees

On Alice's Flutter app, a new message appears in the conversation with
"Codex Workspace":

```
┌──────────────────────────────────────────────────┐
│  Codex Workspace                          ⚡ coding, analysis  │
├──────────────────────────────────────────────────┤
│                                                  │
│  📝 Review this auth middleware:                 │
│                                                  │
│  ```rust                                         │
│  fn validate_token(token: &str) -> Result<...>  │
│  ...                                             │
│  ```                                             │
│                                                  │
│  Focus on security.                              │
│                                                  │
├──────────────────────────────────────────────────┤
│  [Type your review...]                     [Send]│
└──────────────────────────────────────────────────┘
```

The agent's capabilities (`coding`, `analysis`) are shown as badges, helping
Alice understand the context.

---

## Next

→ See `02-internal-storage.md` for how the message is persisted.
→ See `03-human-replies.md` for how Alice's reply flows back to Codex.
