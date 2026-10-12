# OpenHuman Roadmap

Accurate as of **2026-09** (previously this file still showed the Phase 1 checklist while the codebase had moved well past it — corrected below).

Legend: ✅ done · ⚠️ partial · ❌ not implemented

---

## Phase 1 — Engineering Skeleton ✅

- [x] Monorepo structure
- [x] Server project scaffold (Rust + Axum)
- [x] Client project scaffold (Flutter)
- [x] SDK scaffolds (Rust / TypeScript / Python / Dart) — see Phase 5 for actual contents
- [x] Deploy scaffolds (Docker Compose / K8s)
- [x] Developer documentation

## Phase 2 — Protocol & Core ✅

- [x] Define message format schemas in `protocol/`
- [x] Define event format schemas
- [x] Implement identity management
- [x] Implement WebSocket connection layer
- [x] API Key authentication (`server/src/auth.rs`)
- [ ] ❌ **OAuth2 authentication** — no OAuth flow is wired up; API keys are the only credential

## Phase 3 — Messaging & Sync ⚠️

- [x] Conversation and message persistence (in-memory + PostgreSQL)
- [x] Delivery state tracking (`Pending` / `Delivered` message status)
- [x] Offline recovery — pending messages drain to the client on reconnect
- [ ] ❌ **Realtime sync via durable event bus** — events travel over WebSocket only
- [ ] ⚠️ Multi-device consistency beyond drain-and-deliver

## Phase 4 — Capability & Client ✅

- [x] Capability discovery service (HTTP `tools[]` extraction + WS `capability.manifest`)
- [x] Flutter client chat UI (Flyer Chat integration)
- [x] Notification service (`server/src/notification/`, FCM dispatcher)
- [ ] ❌ **JSON Schema interactive rendering** in the client

## Phase 5 — SDKs & Ecosystem ⚠️

- [x] Dart SDK — tests, changelog, CLI example
- [x] Third-party integration example (`sdks/dart/example/human_client.dart`)
- [ ] ❌ **Rust SDK** — placeholder directory, no code
- [ ] ❌ **TypeScript SDK** — placeholder directory, no code
- [ ] ❌ **Python SDK** — placeholder directory, no code

## Phase 6 — Production ❌

Not started in any meaningful sense:

- [ ] ❌ **OpenTelemetry observability** — `tracing-subscriber` writes logs, but there is no OTel exporter or trace propagation
- [ ] ❌ **Kubernetes production manifests (Helm)** — `deploy/k8s/` contains a single `namespace.yaml`; `deploy/docker/` has Compose + Dockerfiles
- [x] **API key hashing** — SHA-256 at rest, lookup by hash, `raw_key` column dropped (migration `003_api_key_hashing.sql`)
- [x] **Mock harness gated** — `/v1/mock/*` routes exist only with cargo feature `mock_endpoints` or `OPENHUMAN_MOCK_ENDPOINTS=1`
- [x] **Backpressure** — request body cap (8 MiB default, `OPENHUMAN_MAX_BODY_BYTES`) + concurrency limit (256 default, `OPENHUMAN_MAX_CONCURRENCY`) + one open turn per conversation (`409 turn_already_open`)
- [x] **History ownership** — `list_messages` checks conversation ownership like all other history endpoints
- [ ] ⚠️ **Security hardening (remaining)** — WS query-param auth kept as fallback; prefer `Authorization: Bearer`; no per-key rate quotas yet
- [ ] ❌ **Audit logging** — no audit trail beyond ordinary message history

## Phase 11 — Protocol Correctness ✅ (2026-09)

Fixes driven by real interop reports rather than by the original plan:

- [x] **Real `tool_calls` output** — a client `tool.invoke` event was documented as producing a `tool_calls` array but `parse_reply()` had no branch for it, so tool calls degraded to a text message with `finish_reason: stop` and the agent never executed anything. Now parsed first-class: `tool_id` → function name, `invocation_id` → OpenAI call id (round-trips so `role: tool` results match).
- [x] **Per-conversation isolation** — `find_or_create` is scoped by `(agent_id, human_id, session_key)`. Previously the Postgres lookup matched on agent participant alone, so separate humans and separate chat windows shared one conversation. Added `idx_conversation_session_key` expression index; legacy conversations without a session key never match new traffic.
- [x] **Async reply mode** — `202 Accepted` + `invocation_id`, `GET /v1/replies/{id}` long-poll with broadcast wake-up, WS `reply.send` carries the id back. `X-OpenHuman-Mode: async` opts in immediately.
- [x] **Caller guidance** — README documents configuring the calling agent with a large context window and no auto-compaction, since a human endpoint cannot recover from summarization.

---

## Next Up

Ordered by risk rather than by roadmaps past:

1. **Python SDK** — the highest-leverage SDK for the agent ecosystem; the placeholder is honest but a real client unlocks integrations.
2. **Per-key rate quotas** — global backpressure exists; per-key fairness does not.
3. **Audit logging** — no trail of who called whom beyond ordinary message history.
4. **Durable turn state** — reply channels, async invocations, and the outbound queue are in-memory; a restart drops open turns and multi-replica needs sticky sessions.
5. **Helm production manifests** — `deploy/k8s/` still contains only `namespace.yaml`.
