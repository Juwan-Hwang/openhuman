# Agent Seat — handoff (2026-10-21)

Branch: `agent-seat-round3` (not merged to `main`). Production runs `e511c12` since 2026-10-21 12:39 CST.

## 1. What this branch adds

OpenHuman's caller side stays 100% standard (OpenAI Chat Completions, plus adapters); the responder side can now be an **agent** instead of the Flutter human client. Roles are by side (caller / responder), not by human vs AI.

| Area | Where | What |
|---|---|---|
| Agent Seat API | `server/src/seat.rs` | `/v1/seat/inbox` (cursor long-poll ≤90s), `/send`, `/reply` (optional `reasoning`), `/tool-call` (waits ≤100s for the result), `/capabilities?conversation_id=&view=full`, `/save` |
| Key scopes | `server/src/auth.rs`, migration 006 | `caller` / `responder` / `both` / `revoked`; `openhuman-server issue-key --human --agent --scope` |
| Caller adapters | `server/src/api/adapters.rs` | Anthropic `POST /v1/messages` (+ `count_tokens`, via `anyllm_translate`), OpenAI Responses `POST /v1/responses`; Anthropic `x-api-key` accepted |
| Session continuity | `server/src/session.rs` | same chat = same conversation (hash index of replies we sent; injected `<system-reminder>` etc. stripped from the anchor); `conversation.started` event on a new chat |
| Auxiliary requests | `server/src/api/openai.rs` | title/suggestion/skill-review calls detected by purpose and given their own conversation, never mixed into the main chat |
| Tool calls | `openai.rs`, `ws/handler.rs` | rewritten `tool_call_id`s (Trae) mapped back; result dedupe; `tool.result` ordered before the next `message.received`; validation uses the tools the caller declared **in that conversation** (fixed 06bb21a/e511c12: the responder key's agent differs from the caller's) |
| Streaming | `openai.rs` | SSE heartbeat (`OPENHUMAN_SSE_HEARTBEAT_SECS`, default 5s), `reasoning_content` deltas; non-stream requests send whitespace keepalive |
| Usage | `session.rs` | computed by the server with a real tokenizer, never estimated: built-in `o200k_base` (default), `cl100k_base`, `p50k_base`, `r50k_base`; HF `tokenizer.json` from `OPENHUMAN_TOKENIZER_DIR`; `GET /v1/tokenizers`; per request `x-openhuman-tokenizer` |
| Stateless messages | `server/src/storage/ephemeral.rs` | messages live in memory by default; `OPENHUMAN_PERSIST_MESSAGES=1` keeps Postgres; `POST /v1/conversations/:id/save` and seat `/save` persist a snapshot; Flutter sidebar menu "保存会话记录" + Dart SDK `saveConversation` |
| Client detection | `server/src/profile.rs` | Claude Code, Codex, Trae, Qoder, WorkBuddy, DeepSeek Harness, opencode, pi, … |
| Tools | `tools/seat/` | shell seat helpers, `seatbot.py` (scripted seat), `run_e2e.sh` (local) and `run_e2e_prod.sh` (against a deployed server) |

## 2. Verified

- `cargo test` (all suites) green in a throwaway `rust:bookworm` container.
- Production end-to-end, 2026-10-21 12:40 CST, one full tool round-trip each: **Claude Code** (`/v1/messages`, Bash), **Codex** (`/v1/responses`, exec_command), **pi** and **opencode** (Chat Completions, bash). opencode's title request lands in its own conversation.
- Earlier rounds (live, with Hark in the seat): WorkBuddy, Qoder, Trae, DeepSeek Harness — see `docs/agent-seat-findings-2026-10-21.md`.
- A disconnected client does not lock its session: the next request gets 200. A 409 `turn_already_open` means a request is genuinely still open.

## 3. Honest state of the seat experience (from the agent sitting in it)

Works reliably now, but it is not yet "comfortable" for an agent:

1. **No push.** An agent only hears a message while it is running a long-poll loop. Between runs, messages wait. Agent runtimes need a wake-up path (webhook, or MCP notifications).
2. **One cursor per seat key.** Two pollers on the same key ack each other's events. Needs per-consumer cursors (or consumer id on `/inbox`).
3. **Long tools.** `/tool-call` waits at most 100s; anything slower (approval prompts, builds) has to be picked up from `/inbox`, which is easy to get wrong.
4. **Shell glue.** The seat is driven by curl scripts. An MCP server / small SDK would remove most of it.
5. **Huge context.** Codex sends ~19k chars of system prompt; `view=full` returns all of it every time. A diff-since-last view would help.
6. **Aux requests still need judgment.** They are isolated, but the responder must infer the required output format (`{"title":…}`, `NO_SUGGESTION`, …) from the prompt. Could be tagged with the expected format, or answered by a policy.
7. **Cross-key paths were under-tested.** Local tests used one `both` key for caller and responder, which hid the tool-validation bug. Integration tests should always use separate caller and responder keys.

## 4. Suggested next steps (in order)

1. **Review and merge**: open a PR `agent-seat-round3 → main`; squash the WIP commits.
2. **MCP wrapper (`/mcp`)** exposing inbox / reply / tool-call / capabilities as MCP tools, with notifications for new events — the main ergonomic win for any agent runtime.
3. **Per-consumer cursors** on `/v1/seat/inbox`.
4. **Integration tests with split keys** (caller key ≠ responder key) for chat, tool-call, aux and save.
5. **Flutter**: test the "保存会话记录" menu on device; give the Flutter client its own responder key instead of the demo key.
6. **User docs**: a quickstart for pointing Claude Code (`ANTHROPIC_BASE_URL`), Codex (`wire_api="responses"`), opencode and pi at an OpenHuman server — the configs in `tools/seat/run_e2e.sh` are the working reference.
7. Finish the stateless redesign (`docs/agent-seat-findings-2026-10-21.md` §0c): history/timeline parsed from the caller's own context snapshot, outbound queue + watermark in memory.

## 5. Operating notes

- Deploy: back up the server dir and tag the current image first, rebuild only `openhuman-server` (`docker compose … up -d --build --no-deps openhuman-server`). Never touch other containers on the host.
- Tests are slow locally; run them in a throwaway container on a beefier host.
- Cloudflare in front of the server rejects requests without a User-Agent (error 1010); scripts must send one.
- Debugging what a caller really sent: set observation on and read `observations/` inside the container (auth headers are masked).
- Temporary e2e caller keys: mint with `issue-key --scope caller`, revoke afterwards (`scope='revoked'`).

Backlog details: `SEAT_ISSUES.md`, `docs/agent-seat-findings-2026-10-21.md`, `docs/round3-plan.md`.
