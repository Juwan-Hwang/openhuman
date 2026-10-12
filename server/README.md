# OpenHuman Server

Rust + Axum implementation of the OpenHuman server core.

## Stack

| Component | Technology |
|---|---|
| API Framework | Axum |
| Async Runtime | Tokio |
| Serialization | Serde / serde_json |
| Database | PostgreSQL + SQLx (production) / in-memory (dev) |
| Realtime | WebSocket (via axum) |
| Auth | API Key (`Authorization: Bearer`, SHA-256 at rest) |
| Logging | tracing |

## Server Components

```
server/src/
├── api/            # HTTP routes: OpenAI-compat, history, async replies, mock (gated)
├── ws/             # WebSocket human gateway: handler, protocol, registry
├── storage/        # Repository traits + memory / PostgreSQL backends
├── model/          # Internal data model (role-neutral)
├── normalize.rs    # Per-agent inbound normalization
├── profile.rs      # Agent profile + client-type detection
├── async_reply.rs  # Async invocations + outbound queue
├── auth.rs         # Bearer API key middleware
├── openai_compat.rs# OpenAI request/response types
├── notification/   # FCM + webhook offline push
├── observation.rs  # Raw-request capture middleware
├── crypto.rs       # SHA-256 key hashing
└── main.rs         # Entry point
```

Turn state (reply channels, async invocations, outbound queue) is
in-memory: a restart drops open turns, and multi-replica deploys need
sticky sessions.

## Run

```bash
cp .env.example .env
cargo run
```
