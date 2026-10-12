# Example 3: Human Replies (Internal → OpenAI Format)

How Alice's reply flows back to the Codex agent.

---

## Alice Types a Response

On her Flutter app, Alice sees the code review request and types:

> The auth middleware looks solid. A few suggestions:
> 1. Add rate limiting to token validation
> 2. Use constant-time comparison for API key hashes
> 3. Consider adding an expiry check for decoded claims

She presses **Send**.

---

## Human Client → OpenHuman Server

The Flutter client sends the reply over its WebSocket connection:

```json
{
  "action": "message.send",
  "data": {
    "conversation_id": "cnv_0189abc123def456",
    "content": {
      "type": "text",
      "text": "The auth middleware looks solid. A few suggestions:\n1. Add rate limiting to token validation\n2. Use constant-time comparison for API key hashes\n3. Consider adding an expiry check for decoded claims"
    }
  }
}
```

---

## Server-Side Processing

### Step 1: Store the Human's Message

```json
{
  "id": "msg_0189a1b2c3d4e5f6",
  "conversation_id": "cnv_0189abc123def456",
  "sender": {
    "participant_id": "hum_0189abc123",
    "participant_type": "human"
  },
  "content": {
    "type": "text",
    "text": "The auth middleware looks solid. A few suggestions:\n1. Add rate limiting to token validation\n2. Use constant-time comparison for API key hashes\n3. Consider adding an expiry check for decoded claims"
  },
  "attachments": [],
  "metadata": {
    "source": "human_client",
    "device_id": "dev_flutter_pixel8"
  },
  "status": "sent",
  "created_at": "2025-01-15T09:30:00Z"
}
```

### Step 2: Emit Event (for other devices + audit)

```json
{
  "event_id": "evt_0189evt0002",
  "event_type": "message.created",
  "conversation_id": "cnv_0189abc123def456",
  "timestamp": "2025-01-15T09:30:00.123Z",
  "data": {
    "message": {
      "id": "msg_0189a1b2c3d4e5f6",
      "sender": {
        "participant_id": "hum_0189abc123",
        "participant_type": "human"
      },
      "content": {
        "type": "text",
        "text": "The auth middleware looks solid. A few suggestions: ..."
      },
      "status": "sent",
      "created_at": "2025-01-15T09:30:00Z"
    }
  }
}
```

This event goes to:
- **WebSocket** → Alice's other devices (tablet, desktop) for sync
- **NATS JetStream** → audit log consumer

### Step 3: Route to SSE Connection

The server looks up the pending SSE connection in Redis:

```
Key: sse:agt_0189def456:cnv_0189abc123def456
→ Node: server-node-3, Connection: conn_789
```

The message is routed to `server-node-3`, which holds the agent's open
HTTP SSE connection.

---

## SSE Translation: Internal → OpenAI Format

The server converts the human's `Message` into OpenAI SSE chunks.

### Chunk 1: Role announcement

```
data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}
```

### Chunks 2-N: Content deltas

The human's text is split into chunks (by word or line for natural streaming):

```
data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"The auth middleware looks solid. "},"finish_reason":null}]}

data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"A few suggestions:\n"},"finish_reason":null}]}

data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"1. Add rate limiting to token validation\n"},"finish_reason":null}]}

data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"2. Use constant-time comparison for API key hashes\n"},"finish_reason":null}]}

data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{"content":"3. Consider adding an expiry check for decoded claims"},"finish_reason":null}]}
```

### Final Chunk: Finish

```
data: {"id":"chatcmpl-cnvtok123","object":"chat.completion.chunk","created":1736936400,"model":"openhuman-human","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

---

## What Codex Sees

Codex receives a standard OpenAI streaming response. It has no idea a human
typed this. From its perspective:

```
Model:    openhuman-human
Role:     assistant
Content:  The auth middleware looks solid. A few suggestions:
          1. Add rate limiting to token validation
          2. Use constant-time comparison for API key hashes
          3. Consider adding an expiry check for decoded claims
Finish:   stop
```

Codex processes this as a normal LLM response and can act on the suggestions
(e.g., modifying the code, running tests).

---

## Full End-to-End Flow

```
Codex Agent              OpenHuman Server              Alice (Flutter)
    |                          |                            |
    |-- POST /v1/chat/completions -->                      |
    |   (messages, stream:true) |                            |
    |                      Auth + Resolve                    |
    |                      Store Message{Agent}              |
    |                          |-- WS: message.created ---->|
    |                          |                      Alice reads
    |                          |                      Alice types reply
    |<- SSE: keepalive --------|                            |
    |                          |<- WS: message.send --------|
    |                      Store Message{Human}              |
    |                      Update msg status: delivered      |
    |<- SSE: delta(content) ----|                            |
    |<- SSE: delta(content) ----|                            |
    |<- SSE: delta(content) ----|                            |
    |<- SSE: finish_reason=stop|                            |
    |<- SSE: [DONE] -----------|                            |
    |                          |                            |
    Codex acts on the          Alice sees status: delivered
    review feedback            (checkmark on her message)
```

---

## Non-Streaming Alternative

If the agent sent `stream: false`, the response is a single JSON body:

```json
{
  "id": "chatcmpl-cnvtok123",
  "object": "chat.completion",
  "created": 1736936400,
  "model": "openhuman-human",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The auth middleware looks solid. A few suggestions:\n1. Add rate limiting to token validation\n2. Use constant-time comparison for API key hashes\n3. Consider adding an expiry check for decoded claims"
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

In non-streaming mode, the HTTP connection stays open until the human responds
or the reply window elapses (default 300s, configurable). Keepalive is not
possible (no SSE), so prefer `stream: true` for interactive callers.

If the window elapses first, the server responds `202 Accepted` instead of
holding the socket indefinitely:

```json
{
  "id": "chatcmpl-cnvtok123",
  "object": "chat.completion",
  "created": 1736936400,
  "model": "openhuman-human",
  "status": "pending",
  "invocation_id": "inv_01H8X...",
  "poll_url": "/v1/replies/inv_01H8X..."
}
```

Poll `poll_url` — optionally with `?wait=<secs>` to long-poll — until the
reply is ready. A client that knows it will be slow can send
`X-OpenHuman-Mode: async` on the original request and get the `202` immediately.
