# OpenAI Compatibility: Chat Completions API

This document specifies how OpenHuman maps its internal data model to the
**OpenAI Chat Completions API** (`POST /v1/chat/completions`).

---

## 1. Core Principle

An agent (Codex, Claude Code, Trae, custom) configures:

```
Base URL:  https://api.openhuman.dev/v1
API Key:   ohk_live_xxxxxxxxxxxx
```

The agent sends a standard OpenAI Chat Completions request. OpenHuman:

1. Authenticates the API Key → resolves `AgentIdentity`
2. The API Key is bound to a specific `HumanIdentity` (the human endpoint)
3. Finds or creates a `Conversation` between this agent and human
4. Stores inbound messages using the internal `Message` model
5. Notifies the human client via WebSocket
6. Waits for the human to respond
7. Streams the human's response back as OpenAI SSE chunks

```
Agent                    OpenHuman Server                  Human Client
  |                           |                                |
  |-- POST /v1/chat/completions -->                          |
  |    { messages: [...] }    |                                |
  |                       Authenticate API Key                 |
  |                       Resolve Agent + Human                |
  |                       Find/Create Conversation              |
  |                       Store Message{sender=Agent}           |
  |                           |-- WebSocket push ----------->|
  |                           |                       Human sees message
  |                           |                       Human types reply
  |                           |<- WebSocket: reply -----------|
  |                       Store Message{sender=Human}          |
  |<- SSE stream --------------|                                |
  |  data: {choices:[...]}    |                                |
  |  data: [DONE]             |                                |
```

---

## 2. Inbound Mapping: OpenAI → Internal

### 2.1 Request

```http
POST /v1/chat/completions HTTP/1.1
Authorization: Bearer ohk_live_xxxxxxxxxxxx
Content-Type: application/json

{
  "model": "human",
  "messages": [
    {
      "role": "system",
      "content": "You are a senior Rust engineer."
    },
    {
      "role": "user",
      "content": "Review the auth middleware in src/auth.rs"
    }
  ],
  "stream": true
}
```

### 2.2 Mapping Table

| OpenAI request field | Internal mapping |
|---|---|
| `Authorization: Bearer <key>` | `AgentIdentity` (via `api_key_id`) |
| `model` | Ignored (or used for routing if multiple humans per key in future) |
| `messages[].role = "system"` | Stored as `Conversation.metadata.system_prompt`; **not** a Message |
| `messages[].role = "user"` | `Message{sender=AgentIdentity, content=TextContent}` |
| `messages[].role = "assistant"` | Previous `Message{sender=HumanIdentity}` in this conversation (context replay) |
| `stream: true` | Response is SSE; otherwise, blocking JSON response |
| `messages[].content` (string) | `ContentBlock{type: "text", text: "..."}` |
| `messages[].content` (array of parts) | `ContentBlock{type: "multipart", parts: [...]}` |

### 2.3 System Message Handling

OpenAI `system` messages are **not** stored as individual messages. They are
merged into `Conversation.metadata.system_prompt`:

```json
{
  "conversation": {
    "metadata": {
      "system_prompt": "You are a senior Rust engineer."
    }
  }
}
```

If multiple `system` messages appear, they are concatenated with `\n`.
The human client can display this as conversation context (e.g., a banner:
"This agent expects: You are a senior Rust engineer").

---

## 3. Outbound Mapping: Internal → OpenAI

### 3.1 Non-Streaming Response

When the human replies and `stream: false` (or absent):

```json
{
  "id": "chatcmpl-openhuman-cnvtok123",
  "object": "chat.completion",
  "created": 1736936400,
  "model": "openhuman-human",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The auth middleware looks solid. A few suggestions:\n1. Add rate limiting to token validation\n2. Use constant-time comparison for API key hashes"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

| OpenAI response field | Internal source |
|---|---|
| `id` | Generated `chatcmpl-` + token (correlates to conversation + message) |
| `object` | Literal `"chat.completion"` |
| `created` | Unix timestamp of human reply |
| `model` | Literal `"openhuman-human"` (signals this is a human, not an LLM) |
| `choices[0].message.role` | Always `"assistant"` (the API responder = human) |
| `choices[0].message.content` | `Message.content.text` (from `HumanIdentity` sender) |
| `choices[0].finish_reason` | `"stop"` when human finishes; `"length"` if truncated |
| `usage.*` | All zeros (no tokens consumed; human is not an LLM) |

### 3.2 Streaming Response (SSE)

When `stream: true`, the human's reply is streamed character-by-character (or
chunk-by-chunk) as SSE:

```
data: {"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"The auth "},"finish_reason":null}]}

data: {"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"middleware looks solid."},"finish_reason":null}]}

data: {"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

### 3.3 SSE Chunk Structure

Each SSE `data:` line contains a JSON object:

| Field | Value |
|---|---|
| `id` | Stable correlation ID for the entire completion |
| `object` | `"chat.completion.chunk"` |
| `created` | Unix timestamp |
| `model` | `"openhuman-human"` |
| `choices[0].index` | Always `0` (single choice) |
| `choices[0].delta.role` | `"assistant"` (first chunk only) |
| `choices[0].delta.content` | Text fragment (subsequent chunks) |
| `choices[0].finish_reason` | `null` until final chunk, then `"stop"` |

### 3.4 Keepalive

While waiting for the human to respond (before the first content chunk),
OpenHuman sends SSE comments as keepalive:

```
: keepalive 1736936405
: keepalive 1736936410
```

This prevents the agent's HTTP client from timing out. The keepalive interval
may vary by `AgentIdentity.client_type` (e.g., 5s for Codex, 15s for others).

---

## 4. Role Mapping Summary

```
 ┌─────────────────────────────────────────────────────────┐
 │                    OpenAI API surface                    │
 │                                                         │
 │   role: "user"      ←→   AgentIdentity (caller)         │
 │   role: "assistant"  ←→   HumanIdentity (responder)     │
 │   role: "system"    ←→   Conversation.metadata          │
 │                                                         │
 └─────────────────────────────────────────────────────────┘
              ↕ translation layer (this document)
 ┌─────────────────────────────────────────────────────────┐
 │                  Internal data model                    │
 │                                                         │
 │   Message.sender = ParticipantRef                       │
 │   (participant_type: "agent" | "human")                │
 │                                                         │
 └─────────────────────────────────────────────────────────┘
```

### Why this works

- To the agent, it is talking to an "assistant" that responds to its "user" messages.
  This is exactly the OpenAI pattern agents already know.
- Internally, the "assistant" is a real human. The agent never needs to know.
- The human client sees the agent as the "other party" in a chat — not as
  an "assistant" or "tool." The internal model is symmetric.

### Context replay

When the agent sends a new request with previous messages (context window),
messages with `role: "assistant"` from prior turns are **replayed** — the
server recognizes them as previously stored `Message{sender=HumanIdentity}`
and skips re-storing them. This prevents duplicate messages when agents
include conversation history.

Detection: the server compares the `content` of inbound `assistant` messages
against stored human messages in this conversation. If a match is found,
it is treated as context replay. If no match is found, it is stored as a
new message with `sender=HumanIdentity` and `metadata.source = "context_inject"`.

---

## 5. Error Responses

Errors follow the OpenAI error format:

```json
{
  "error": {
    "message": "Human is currently offline. Message has been queued.",
    "type": "human_offline",
    "code": "human_offline_queued"
  }
}
```

| Scenario | HTTP Status | Error Type |
|---|---|---|
| Invalid API key | 401 | `invalid_api_key` |
| Human not found (key unbound) | 404 | `human_not_found` |
| Human offline (non-streaming) | 202 | `human_offline_queued` (message stored, delivered later) |
| Human offline (streaming) | SSE comment `: waiting for human` then chunks when they respond |
| Human timeout (no response in TTL) | 504 | `human_timeout` |
| Rate limited | 429 | `rate_limit_exceeded` |

---

## 6. Limitations & Clarifications

| OpenAI feature | OpenHuman behavior |
|---|---|
| `temperature`, `top_p` | Ignored (human is not stochastic) |
| `max_tokens` | Honored as character limit on human reply |
| `stop` sequences | Not supported |
| `logprobs` | Not supported |
| `n` (multiple choices) | Always 1 (single human responder) |
| `tools` / `functions` | Passed through to metadata; not executed by OpenHuman |
| `response_format` | If `json_object`, human client renders a JSON input form |
| `seed` | Ignored |

---

## Appendix A — Implementation notes (2026-10)

Reference: `server/src/api/openai.rs`, `server/src/normalize.rs`.

- Only the **last** `user` message is forwarded; earlier ones are replayed
  history. It is normalized per agent family before reaching the timeline:
  WorkBuddy `<user_query>` (newest part wins), Trae `<user_input>`
  (`REQUIREMENT:` parts skipped), Claude Code bare text (leading
  `<system-reminder>` stripped), unknown agents best-effort.
- WorkBuddy `x-agent-purpose != conversation` requests are meta-requests,
  auto-answered, never forwarded to the human.
- One conversation holds at most one open turn; a second concurrent
  request gets `409 turn_already_open`.
- `stream: false` pads with `\n` keepalives and hands off to async mode on
  timeout instead of dropping. `X-OpenHuman-Mode: async` returns `202` +
  `invocation_id`; the agent polls `GET /v1/replies/{id}`.
