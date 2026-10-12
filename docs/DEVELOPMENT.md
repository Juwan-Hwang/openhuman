# Development Guide

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Rust | 1.75+ | Server |
| Flutter | 3.19+ | Client |
| Dart | 3.x | Dart SDK (the only implemented SDK) |
| Docker | 24+ | Local infra |
| PostgreSQL | 15+ | Primary DB (production backend; dev uses in-memory) |

> Only the Dart SDK has working logic today. The Python, Rust and TypeScript
> directories are placeholders with no code. See `README.md → Known Limitations`.

---

## Repository Layout

```
openhuman/
├── protocol/          # Protocol spec & schemas (source of truth)
├── server/            # Rust + Axum API server
├── client/            # Flutter human-endpoint client
├── sdks/              # Multi-language SDKs
│   ├── rust/
│   ├── typescript/
│   ├── python/
│   └── dart/
├── deploy/            # Docker Compose & K8s manifests
└── docs/              # Architecture & dev docs
```

---

## Local Development

### 1. Start infrastructure

```bash
cd deploy/docker
docker compose up -d
```

This starts PostgreSQL.

### 2. Run the server

```bash
cd server
cp .env.example .env
cargo run
```

### 3. Run the client

```bash
cd client
flutter pub get
flutter run
```

---

## Conventions

- **Protocol first**: any wire-format change starts in `protocol/`.
- **No business logic in SDKs**: SDKs are thin transport layers.
- **Core/UI separation**: server is the permanent core; client UI is replaceable.
- **Capability, not tool approval**: OpenHuman discovers human capabilities; it does not approve agent tool calls.
