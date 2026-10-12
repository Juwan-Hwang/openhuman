# OpenAI Compatibility: Responses API (Future)

> **Status: Design Spec — Not yet implemented**
>
> OpenAI's Responses API is the newer interface. This document describes how
> OpenHuman will map to it when implemented.

---

## 1. Overview

The OpenAI Responses API (`POST /v1/responses`) is a stateful alternative to
Chat Completions. It uses a different request/response shape but the same
underlying concept: send input, receive streamed or JSON output.

OpenHuman will support this endpoint with the same internal model.

---

## 2. Inbound Mapping

### Request

```http
POST /v1/responses HTTP/1.1
Authorization: Bearer ohk_live_xxxxxxxxxxxx
Content-Type: application/json

{
  "model": "human",
  "input": "Review the auth middleware in src/auth.rs",
  "instructions": "You are a senior Rust engineer.",
  "stream": true
}
```

### Mapping Table

| Responses API field | Internal mapping |
|---|---|
| `Authorization: Bearer <key>` | `AgentIdentity` (via `api_key_id`) |
| `model` | Ignored (or routing) |
| `input` (string) | `Message{sender=AgentIdentity, content=TextContent}` |
| `input` (array of items) | `Message{sender=AgentIdentity, content=MultiPartContent}` |
| `instructions` | `Conversation.metadata.system_prompt` |
| `stream: true` | SSE response |
| `previous_response_id` | Correlates to prior conversation turn |

### Stateful Conversation

Unlike Chat Completions (where the agent sends full history each time),
the Responses API uses `previous_response_id` for stateful continuation.
OpenHuman maps this to its internal `conversation_id`:

```
Agent sends input, gets response_id = "resp_0189xyz"
Agent sends next input with previous_response_id = "resp_0189xyz"
OpenHuman resolves: same conversation, new message
```

The `response_id` encodes: `resp_` + `conversation_id` + `:` + `turn_number`.

---

## 3. Outbound Mapping

### Non-Streaming

```json
{
  "id": "resp_0189abc123",
  "object": "response",
  "created_at": "2025-01-15T09:30:00Z",
  "model": "openhuman-human",
  "status": "completed",
  "output": [
    {
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "The auth middleware looks solid. A few suggestions..."
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 0,
    "output_tokens": 0,
    "total_tokens": 0
  }
}
```

### Streaming (SSE)

The Responses API uses a different SSE event structure than Chat Completions:

```
data: {"type":"response.created","response":{"id":"resp_0189abc123",...}}

data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","role":"assistant"}}

data: {"type":"response.output_text.delta","output_index":0,"delta":"The auth "}

data: {"type":"response.output_text.delta","output_index":0,"delta":"middleware looks solid."}

data: {"type":"response.output_text.done","output_index":0,"text":"The auth middleware looks solid."}

data: {"type":"response.completed","response":{"id":"resp_0189abc123","status":"completed",...}}
```

---

## 4. Role Mapping

Identical to Chat Completions:

| Responses API role | Internal |
|---|---|
| `user` (implicit in `input`) | `AgentIdentity` |
| `assistant` (in `output`) | `HumanIdentity` |
| `instructions` | `Conversation.metadata.system_prompt` |

---

## 5. Implementation Priority

The Responses API compatibility is **Phase 5+**. Phase 2-4 will focus on
Chat Completions API compatibility, which is the most widely supported
interface across agent clients (Codex, Claude Code, Trae).

The internal data model is designed to support both APIs from day one —
only the translation layer differs.
