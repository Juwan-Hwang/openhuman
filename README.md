<div align="center">

# OpenHuman

### Human-as-an-API Runtime

</div>

---

## What is OpenHuman

OpenHuman is **not** a chatbot, a digital human, an AI-replacement platform, or a local copilot approval tool.

OpenHuman is an open protocol and runtime that turns a **real human into a programmable API endpoint (Human-as-an-API)** — creating a **novel communication medium for the AI era**.

### The Core Vision: two people, one conversation

Everyone already has an AI tool open — an IDE, a CLI, a workspace like Trae, Cursor, WorkBuddy or Claude Code. OpenHuman lets that tool double as a **direct line to another person**.

You configure OpenHuman once in your own AI client (`Base URL` + `API Key` + `model: openhuman-human`). From then on it is just a conversation between two people:

1. **You type.** You write to Alice exactly as you would write to a model — no new app, no leaving your workspace to open email, Slack or WeChat.
2. **Your words arrive verbatim.** OpenHuman peels off the agent wrapper — system prompts, tool schemas, memory reminders — so Alice reads what *you* actually typed, not a token flood.
3. **Alice answers.** Her client (desktop or mobile) receives it over WebSocket in real time, or by push notification when she is away, and she replies in her own words.
4. **Her reply streams back** into your window as it is written.

There is no AI in the middle. Your tool is the transport; the person on the other end is a real human who answers for themselves.

Because the ingress is plain OpenAI Chat Completions, the same endpoint also works one step removed — someone can have their agent dispatch a message on their behalf (*"ask Alice about the API design"*). What reaches Alice is still a person's request, and what comes back is still a person's answer.

```
You, in your own AI tool ──(OpenAI-compatible HTTP/SSE)──▶ OpenHuman Server
                                                                  │
                                                      (WebSocket + FCM push)
                                                                  ▼
                                                      Alice's OpenHuman client
                                                        (desktop / mobile)
     ◀────────────────────── her reply streams back ──────────────┘
```

> **What OpenHuman is not**: it is not a chatbot, and it does not answer for you — nothing here generates a reply, every answer comes from a person. It is also not an approval gate for your own local agent, which can already talk to you in its own window. OpenHuman is the line to *someone else*.

---

## Protocol Normalization — the real differentiator

External callers reach you from diverse agent ecosystems, each wrapping the message in massive system prompts, tool schemas, and environment dumps. **Humans cannot parse token floods the way an LLM can.**

OpenHuman's server core peels the agent wrapper off before the message reaches your screen, using real captured request fixtures for regression testing.

Measured against a live deployment by replaying a **real WorkBuddy capture**:

| Metric | Raw agent request | Rendered to the human |
|---|---|---|
| Whole request body | 199,861 chars (24 tools declared) | — |
| Last user turn | 13,131 chars (`<system-reminder>`, identity files, memory reminders) | — |
| **What Alice sees** | — | **12 chars**: `请继续完成未完成的任务。` |

Those real traffic captures live in `server/observations/` and are intentionally excluded from version control (see `.gitignore`).

---

## Monorepo Structure

```
openhuman/
├── protocol/          # Protocol specification (language-agnostic)
├── server/            # Rust + Axum server core
├── client/            # Flutter human-endpoint client
├── sdks/              # Official SDKs
│   ├── dart/          # Dart SDK          — usable        (91 tests)
│   ├── python/        # Python SDK        — not implemented (placeholder)
│   ├── rust/          # Rust SDK          — not implemented (placeholder)
│   └── typescript/    # TypeScript SDK    — not implemented (placeholder)
├── deploy/            # Docker Compose, K8s manifests, nginx, Anthropic bridge
└── docs/              # Architecture & developer docs
```

---

## Design Principles

- **Human as Endpoint** — the human is the actual participant, not an AI model.
- **Protocol First** — the protocol and core runtime are UI-agnostic.
- **Cognitive Protection** — clean human-readable text on the primary timeline; agent capability manifests are surfaced separately.
- **Open Ecosystem** — the protocol is SDK-driven so third parties can build their own clients and integrations. In practice only the Dart SDK is implemented today; the Python, Rust and TypeScript directories are placeholders.

---

## Technology Stack

| Layer | Technology |
|---|---|
| API Server | Rust + Axum + Tokio |
| Database | PostgreSQL + SQLx (production) / in-memory (dev) |
| Realtime | WebSocket |
| Client | Flutter + Riverpod + Material 3 + Flyer Chat |
| Auth | API Key (`Authorization: Bearer`) |
| Deploy | Docker / Kubernetes / nginx (Cloudflare in front) |
| Notifications | Firebase Cloud Messaging (mobile offline push) |

---

## Status

**Phase 10 — Release Hardening** ✅ (2026-09)

| Capability | State |
|---|---|
| OpenAI-compatible ingress `/v1/chat/completions` (SSE + non-streaming) | ✅ |
| Human WebSocket gateway with pending-message drain | ✅ |
| Multi-turn turns (`reply.send` → `end.turn`) | ✅ |
| Tool-call return path (`tool_calls` → `role: tool`) | ✅ |
| Agent capability discovery (HTTP `tools[]` + WS `capability.manifest`) | ✅ |
| Protocol normalization for real agent wrappers | ✅ |
| PostgreSQL persistence layer | ✅ |
| Dart SDK — tests + changelog + CLI example | ✅ |
| Flutter desktop client | ✅ |
| FCM offline push | 📱 Android path configured |
| Python / Rust / TypeScript SDKs | ❌ **not implemented** — placeholder directories, no code |
| Async reply mode for non-streaming requests | ✅ `202` + `GET /v1/replies/{id}` |
| Real tool calls (protocol `tool.invoke` → `tool_calls` array) | ✅ |
| Per-conversation session isolation (`(agent, human, session)`) | ✅ |
| API keys hashed with SHA-256 (no plaintext at rest) | ✅ |
| Per-agent normalization (WorkBuddy / Trae / Claude Code) | ✅ envelope-aware, newest-turn-wins |
| Mock harness disabled by default | ✅ `mock_endpoints` feature or `OPENHUMAN_MOCK_ENDPOINTS=1` |
| Concurrent-turn protection | ✅ second turn on one conversation gets `409` |
| Kubernetes Helm production manifests | 🔜 |

Test suites: **91** Dart SDK tests, **27** Flutter widget tests, Rust server tests (unit + integration; PostgreSQL cases need `DATABASE_URL`) — all passing.

---

## Known Limitations

These are real gaps, not footnotes. Read them before deploying anything beyond a demo.

### Three of the four SDKs are empty

Only the Dart SDK has working logic. The Python, Rust and TypeScript directories are placeholders with no code.

### Other notes

- Turn state (reply channels, async invocations, outbound queue) is in-memory: a restart drops open turns, and multi-replica deploys need sticky sessions.
- The WebSocket handshake accepts the API key as a query parameter fallback for clients that cannot set headers. Prefer `Authorization: Bearer` — query strings leak into access logs.
- Under rapid reconnects the WebSocket handshake intermittently resets. Clients should retry with backoff.
- `server/observations/` holds real captured requests and is deliberately kept out of version control.

---

## Quick Start

### Connect to a running instance

If someone already runs OpenHuman for you, you need three settings — ask
them for the host and your key:

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

The request holds open. Reply from the OpenHuman client and the answer streams back as SSE chunks ending with `data: [DONE]`.

### Run it locally

The server needs no external services in its default in-memory mode:

```powershell
cd server
$env:OPENHUMAN_BACKEND="memory"
$env:OPENHUMAN_PORT="8080"
cargo run
```

Then start the client and connect it to `ws://localhost:8080/ws`:

```powershell
cd client
flutter pub get
flutter run -d windows
```

For PostgreSQL persistence set `OPENHUMAN_BACKEND=postgres` and point `DATABASE_URL` at your database; see `server/.env.example`.

See `docs/quickstart.md` for the full walkthrough including the Dart SDK example.

---

## Configuring the Calling Agent

### Give the agent the largest context window it supports

A human endpoint does not get faster or cheaper when you shrink context — it just loses history. An LLM summarizer can throw away earlier turns and still answer; **a human cannot**, because the thing being thrown away is the conversation itself. If the caller's client compacts mid-thread, the human on the other end silently loses what was said before the compaction, and the only recovery is someone pasting the context back by hand.

Set the calling agent's context to the maximum your client and model offer — **1M or 2M tokens** where available — and turn off automatic compacting / summarization for sessions that talk to OpenHuman.

| What to look for | Where it usually lives |
|---|---|
| Context window size | Model selector / "Max mode" / "long context" toggle, or `contextWindow` in the client's model config |
| Auto-compact / auto-summarize | A "compact conversation" threshold, `/compact` automation, or a max-context setting that triggers summarization |
| Max output tokens | Leave generous; a human reply is short, but the agent's own reasoning is not |

Practical notes:

- **You are not paying the human's token cost.** The wrapper your agent sends is normalized away before delivery (199,861 chars in → 12 chars shown), so a big context costs you model tokens, not human attention.
- **Prefer a new conversation over compaction.** When a thread gets long, start a fresh conversation id (below) rather than letting the client compress the old one in place. Human memory across turns is preserved server-side per conversation; compaction is the thing that breaks it.
- **Verify after changing settings.** Send one long multi-turn thread and confirm the human still sees the earlier turns verbatim.

### Keep conversations separate

Every request is scoped by a three-part key: **(agent, human, session)**. Two different chat windows or two different agents that share one key get one shared conversation; give them different keys and they are isolated, with independent history.

The session key is resolved in this order — first match wins:

| Source | Example |
|---|---|
| `X-OpenHuman-Conversation-Id` (or `X-Conversation-Id`) header | `X-OpenHuman-Conversation-Id: design-review` |
| `conversation` field in the JSON body | `"conversation": {"id": "design-review"}` |
| `X-OpenHuman-Session-Id` (or `X-Session-Id`) header | `X-OpenHuman-Session-Id: alice-phone` |
| `user` field in the body | `"user": "bob"` |
| `metadata.conversation_id` / `metadata.session_id` | `"metadata": {"conversation_id": "design-review"}` |
| Fingerprint of the system prompt | automatic, stable per distinct system prompt |
| `default` | fallback when nothing above is present |

If you do nothing, requests that carry the same system prompt land in the same conversation and everything else shares `default` — which is the "all my chats got mixed together" behaviour. Passing an explicit conversation id is the fix, and it is the recommended default for any client that has more than one chat window.

```bash
curl -N http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer ohk_demo_alice_codex" \
  -H "Content-Type: application/json" \
  -H "X-OpenHuman-Conversation-Id: design-review" \
  -d '{"model":"openhuman-human","messages":[{"role":"user","content":"Got 10 minutes for the API design?"}],"stream":true}'
```

---

## API Surface

### HTTP

| Route | Auth | Purpose |
|---|---|---|
| `POST /v1/chat/completions` | Bearer key | OpenAI-compatible ingress; SSE when `stream: true` |
| `GET /v1/replies/{invocation_id}` | Bearer key | Long-poll an async reply (`?wait=<secs>`, max 300) |
| `GET /v1/models` | Bearer key | Lists the `openhuman-human` model |
| `GET /health` | public | Liveness probe |
| `GET /ws` | `Authorization: Bearer` (or `?api_key=`) | Human WebSocket gateway |

Non-streaming requests return `202 Accepted` with an `invocation_id` when the human does not answer inside the reply window; poll `GET /v1/replies/{invocation_id}` for the result. Send `X-OpenHuman-Mode: async` to opt in immediately instead of waiting.

### WebSocket events

Server → client: `session.connected`, `message.received`, `reply.delivered`, `capability.updated`, `tool.result`, `async.invocation.created`, `error`.

Client → server: `reply.send` (carries an optional `invocation_id` to complete an async request), `presence.update`, `capability.manifest`, `tool.invoke`, `end.turn`.

The `tool.invoke` event is what produces a real `tool_calls` array on the OpenAI side — the `tool_id` becomes the function name and `invocation_id` becomes the OpenAI call id, so the client can match the `role: tool` result back to the original call.

The full wire specification is in `docs/protocol.md` and `protocol/`.

---

## End-to-End Verification

`server/scripts/` contains live probes used against a deployed instance:

| Script | Purpose |
|---|---|
| `e2e_live_demo.py` | Full loop: agent request → human WS reply → SSE chunks → `[DONE]` |
| `e2e_normalization_probe.py` | Replays a real capture to verify what the human actually receives |
| `e2e_size_threshold.py` | Sweeps payload sizes to confirm delivery headroom |
| `e2e_async_toolcall_isolation.py` | Live probe for the three interop fixes: async mode, real WS `tool.invoke` → `tool_calls`, and per-conversation isolation |
| `e2e_live_fixes.py` | Live probe for tool-result write-back, companion prose with a tool call, parked replies, and a non-streaming request held past the CDN idle timeout (~2 min) |
| `e2e_session_and_vision.py` | Live probe for cross-client conversation isolation, prose and tool calls merging into one response, and image input reaching the human |
| `shot_window.py` | Captures the client window to PNG (ctypes based) |

`e2e_async_toolcall_isolation.py` is the one to run after a deploy — it drives the human side over the WebSocket gateway with a genuine `tool.invoke` event rather than going through `/v1/mock/*`, because the mock endpoints bypass `parse_reply()` and are exactly what hid the tool-call downgrade. Defaults to the hosted instance:

```powershell
cd server\scripts
python e2e_async_toolcall_isolation.py          # 17 checks
python e2e_async_toolcall_isolation.py http://127.0.0.1:8080 ws://127.0.0.1:8080
```

A typical verified round trip completes in about **5 seconds**, including the offline→online drain path: with nobody connected, the server keeps the turn alive and tells the caller the human is offline, then flushes the backlog the moment a device connects.

---

## License

MIT — see [LICENSE](LICENSE).
