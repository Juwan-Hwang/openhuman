# OpenHuman Client

Flutter implementation of the **Human Endpoint Runtime** — the official client that lets a real human participate as an API endpoint.

## Stack

| Component | Technology |
|---|---|
| Framework | Flutter |
| State Management | Riverpod |
| UI | Material 3 |
| Chat UI | Flyer Chat |
| Interactive UI | JSON Schema Renderer |
| Protocol | OpenHuman Dart SDK |

## Structure (planned)

```
client/
├── lib/
│   ├── main.dart
│   ├── app/               # App-level config, routing, theming
│   ├── features/          # Feature modules (chat, identity, capabilities)
│   ├── core/              # Core utilities, constants
│   └── sdk/               # OpenHuman Dart SDK bridge
├── assets/
└── test/
```

## Run

```bash
flutter pub get
flutter run
```

## Status

**Phase 1 — Skeleton only.** No business logic implemented.
