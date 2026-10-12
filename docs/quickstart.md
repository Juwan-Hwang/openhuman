# OpenHuman Quick Start

Two paths: point your agent at a server someone already runs, or run the
whole stack locally. Path B needs no external services.

---

## Path A — Point your agent at a running server

If someone has already deployed OpenHuman for you, all you need is three
settings — ask them for the base URL and your API key:

| Setting | Value |
|---|---|
| Base URL | `https://YOUR_HOST/v1` |
| WebSocket | `wss://YOUR_HOST/ws` |
| API Key | `YOUR_KEY` |
| Model | `openhuman-human` |

```bash
curl -N https://YOUR_HOST/v1/chat/completions \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openhuman-human","messages":[{"role":"user","content":"Hello human!"}],"stream":true}'
```

The request stays open until a human answers. Continue at [step 4](#4-reply-from-the-human).

## Path B — Run locally

### 1. Start the server

The default backend is in-memory, so no database is required:

```powershell
cd e:\openhuman\server
$env:OPENHUMAN_BACKEND="memory"
$env:OPENHUMAN_PORT="8080"
cargo run
```

The server starts on `http://localhost:8080` with the same demo key `ohk_demo_alice_codex`.

For PostgreSQL persistence:

```powershell
$env:OPENHUMAN_BACKEND="postgres"
$env:DATABASE_URL="postgres://openhuman:openhuman@localhost:5432/openhuman"
cargo run
```

### 2. Start the Flutter client

```powershell
cd e:\openhuman\client
flutter pub get
flutter run -d windows
```

In the AuthScreen:

- **Server URL**: `ws://localhost:8080/ws` (or your deployment's `wss://...`)
- **API Key**: `ohk_demo_alice_codex`

Tap **Connect**.

---

## 3. Send a message from an agent

### PowerShell

```powershell
curl -N http://localhost:8080/v1/chat/completions `
  -H "Authorization: Bearer ohk_demo_alice_codex" `
  -H "Content-Type: application/json" `
  -d '{\"model\":\"openhuman-human\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello human!\"}],\"stream\":true}'
```

### Python

```python
import requests

resp = requests.post(
    "http://localhost:8080/v1/chat/completions",
    headers={"Authorization": "Bearer ohk_demo_alice_codex"},
    json={
        "model": "openhuman-human",
        "messages": [{"role": "user", "content": "Hello human!"}],
        "stream": True,
    },
    stream=True,
)
for line in resp.iter_lines():
    print(line.decode())
```

### Any OpenAI-compatible client

Point any ecosystem tool at the endpoint as if it were an OpenAI model:

| Setting | Value |
|---|---|
| Base URL | `http://localhost:8080/v1` |
| API Key | `ohk_demo_alice_codex` |
| Model | `openhuman-human` |

### Agent settings that matter

Two settings decide whether the conversation survives contact with the agent client.

**1. Use the largest context window available, and disable auto-compaction.**

Set 1M or 2M tokens if the client and model offer it. Turn off automatic compacting / summarization. An LLM loses little when history is summarized; a human loses the conversation. Compaction is invisible to the human endpoint — earlier turns simply stop existing.

**2. Send an explicit conversation id.**

Without one, every request that shares a system prompt shares a conversation, and anything else falls back to a single `default` conversation — so separate chat windows collide. Pass a header and each window gets its own history:

```bash
curl -N http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer ohk_demo_alice_codex" \
  -H "Content-Type: application/json" \
  -H "X-OpenHuman-Conversation-Id: design-review" \
  -d '{"model":"openhuman-human","messages":[{"role":"user","content":"Hello human!"}],"stream":true}'
```

Equivalent body form: `"conversation": {"id": "design-review"}`. See the ["Configuring the Calling Agent"](../README.md#configuring-the-calling-agent) section of the README for the full resolution order.

### When the human is slow: async mode

Non-streaming requests return `202 Accepted` with an `invocation_id` if no reply arrives within the reply window (default 300 s, configurable). Poll for the result:

```bash
curl http://localhost:8080/v1/replies/inv_01H... \
  -H "Authorization: Bearer ohk_demo_alice_codex"
```

Add `?wait=60` to long-poll (server wakes the request the moment the human replies; max 300). To skip the wait entirely, send `X-OpenHuman-Mode: async` on the original request.

---

## 4. Reply from the human

The message appears in the Flutter chat UI. Type a reply and press send.

The agent receives it as SSE chunks:

```
data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"Your"},"index":0}]}
data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"reply"},"index":0}]}
data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"text"},"index":0}]}
data: [DONE]
```

If nobody is connected yet, the caller immediately gets a keepalive notice that the human is offline. As soon as a device connects, the server flushes the pending messages and the normal flow resumes.

Several replies can be sent in one turn. Send `end.turn` from the client to close the turn and finish the request with `finish_reason: stop`.

> **A text reply does not end the turn.** That is deliberate — the human may have more to say — so a streaming request stays open until the human sends `end.turn` or replies with a tool call. A client that waits for `[DONE]` right after the first reply will block.

---

## 5. Use the Dart SDK directly

```dart
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() async {
  final client = OpenHumanClient();

  client.messages.listen((msg) {
    print('From ${msg.senderId}: ${msg.text}');
  });

  await client.connect('ws://localhost:8080/ws', 'ohk_demo_alice_codex');

  // Wait for a message, then reply:
  // await client.sendReply('cnv_xxx', 'I got your message!');

  await client.disconnect();
  client.dispose();
}
```

Run the example:

```powershell
cd e:\openhuman\sdks\dart
dart run example/human_client.dart
```

---

## What happens internally

```
Agent (HTTP POST)
  → Server (store message, push WS event)
    → Flutter (display message in chat)
      → Human (types reply)
        → Server (deliver to SSE)
          → Agent (receives reply)
```

Agent-specific wrapper tags are stripped before the message reaches the human timeline, so a 13,000-character agent payload arrives as a single readable sentence.

---

## Verify end to end without a UI

`server/scripts/` has live probes:

```powershell
cd e:\openhuman\server\scripts
python e2e_live_demo.py            # full agent -> human -> agent loop
python e2e_normalization_probe.py  # replay a real capture, check what the human sees
python e2e_size_threshold.py       # payload size sweep
python e2e_async_toolcall_isolation.py   # async mode + tool_calls + isolation, 17 checks
```

Requires `websockets` and `requests`.

`e2e_async_toolcall_isolation.py` is the post-deploy smoke test. It connects a human
client over WebSocket and replies with a real `tool.invoke`, so it exercises
`parse_reply()` — the function the mock endpoints skip.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Connection refused | Ensure the server is running on port 8080, or use the hosted URL |
| Auth failed | Check the API key is `ohk_demo_alice_codex`; WS accepts `?api_key=`, `?token=`, or `?authorization=` |
| No messages received | The agent must use `stream: true` |
| SSE hangs with no reply | A human must reply over WebSocket to complete the cycle; the default wait is 300s |
| `stream: false` took over 100s and failed | Should be fixed — the non-streaming response now emits keepalive padding. If it still fails, the caller's own HTTP timeout is shorter than the reply window; use `stream: true` or `X-OpenHuman-Mode: async` |
| Human replied but the agent never saw it | The reply arrived after the request ended. It is parked and delivered with the next request for that conversation |
| Got `202` instead of an answer | Async mode — poll `GET /v1/replies/{invocation_id}` from the response |
| Chats from different windows are mixed together | Pass `X-OpenHuman-Conversation-Id` per window; see [above](#agent-settings-that-matter) |
| A tool call was answered by a different client | Callers that send no identifying header are separated by a User-Agent fingerprint. Give each integration a distinct header or `User-Agent` rather than relying on the fallback |
| The human's words arrived but their tool call did not (or vice versa) | Both are submitted together after a short merge window (`OPENHUMAN_MERGE_WINDOW_MS`, default 2000ms). Setting it to `0` restores submit-on-first-action, which strands the second action |
| Human saw only part of what was said | The agent client compacted the context. Raise the context window and disable auto-compaction |
| Human offline | Expected: the caller gets an offline keepalive, then the backlog drains on reconnect |
| `wss://` handshake reset | Transient under rapid reconnects — wait a few seconds and retry with backoff |
| WebSocket over HTTPS | Use `wss://` (not `ws://`) against `https://` origins |
