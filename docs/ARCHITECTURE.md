# OpenHuman Architecture

## Overview & Core Mission

OpenHuman is a **Human-as-an-API** platform that establishes a **novel interpersonal communication medium for the AI era**.

It allows a real human to become a standard, programmable API endpoint (`Base URL` + `API Key`) accessible by existing AI agents and applications. 

### Why OpenHuman?
In modern workflows, people spend their time inside AI Agent environments (Trae, Cursor, WorkBuddy, Claude Code, etc.). OpenHuman allows **other people to reach you directly through their own agents**, eliminating context-switching to traditional chat apps.
- **External Caller**: Uses their own AI agent to send messages/inquiries to your endpoint.
- **Universal Reach**: OpenHuman routes incoming messages to your client (desktop/web/mobile) with real-time WebSocket and native Google FCM offline push notifications.
- **Human Response**: Your replies stream back to the caller's agent conversation in real time.
- **Clarification**: OpenHuman is *not* an approval gate for your own local IDE agent (which can talk to you locally). It is a universal contact endpoint for *others* to reach you.

```
Other Person's Agent Client (Trae / Cursor / WorkBuddy / etc.)
                          │  (OpenAI Compatible HTTP/SSE)
                          ▼
                  OpenHuman Protocol
                          │  (WebSocket + FCM Push)
                          ▼
                    Human Endpoint (You)
```

## Design Principles

1. **Human as Endpoint & Communication Medium** — The human is the actual participant and recipient, not an AI model or local tool approval system.
2. **Protocol Normalization & Cognitive Protection** — External people contact you via diverse software (WorkBuddy, Trae, Cursor, Claude Code), each wrapping the message in massive system prompts, tool schemas, and custom XML tags (e.g. `<user_query>`). Because humans cannot parse token floods like an LLM can, the server normalizes these payloads using real-world observation fixtures: peeling away agent noise so the human sees clean, readable text, while keeping runtime metadata accessible in a separate panel.
3. **Protocol First** — The protocol and core runtime do not depend on any specific UI implementation.
4. **Open Ecosystem** — SDKs enable third-party clients, integrations, and automation.

## System Architecture

```
                    Agent Clients
                         |
              OpenHuman API Layer
                         |
              OpenHuman Server Core
        ┌────────────────────────────────┐
        │  API Gateway                   │
        │  Identity                      │
        │  Messaging                     │
        │  Synchronization               │
        │  Capability Discovery          │
        └────────────────────────────────┘
                         |
          PostgreSQL
                         |
                  WebSocket
                         |
                Human Client (Flutter)
```

## Core-UI Separation (TDLib Pattern)

```
OpenHuman Core (Rust Server + Dart SDK)
        |
Client Implementations
        |
Flutter / Web / Desktop / Third-party Clients
```

Future clients can replace the UI without changing the protocol core.

## Technology Stack

### Backend

| Component | Technology |
|---|---|
| API Service | Rust + Axum |
| Async Runtime | Tokio |
| Serialization | Serde |
| Database | PostgreSQL (production) / In-Memory (dev/test) |
| Realtime | WebSocket |
| Auth | API Key |
| Deployment | Docker / Kubernetes |

### Client

| Component | Technology |
|---|---|
| Framework | Flutter |
| State Management | Riverpod |
| UI | Material 3 |
| Chat UI | Flyer Chat (flutter_chat_ui) |
| Navigation | go_router |
| SDK | openhuman_sdk_dart |

## Component Layers

### Rust Server (`server/`)

| Module | Path | Responsibility |
|---|---|---|
| API Gateway | `src/api/` | HTTP routes, OpenAI-compatible endpoints |
| Identity | `src/identity/` | Human/agent identity, API keys |
| Messaging | `src/messaging/` | Conversation and message management |
| WebSocket | `src/ws/` | Realtime transport, event protocol |
| Storage | `src/storage/` | Memory/PostgreSQL persistence |
| OpenAI Compat | `src/api/openai_compat.rs` | `/v1/chat/completions` endpoint |
| Capability | `src/capability/` | Tool manifest, context storage |

### Dart SDK (`sdks/dart/`)

| Module | Path | Responsibility |
|---|---|---|
| Client | `lib/src/client.dart` | High-level API, event dispatch, session state |
| Connection | `lib/src/connection.dart` | WebSocket lifecycle, auto-reconnect |
| Events | `lib/src/events.dart` | Event envelope, Client→Server messages |
| Messages | `lib/src/messages.dart` | Internal message model, ContentBlock |
| Capabilities | `lib/src/capabilities.dart` | AgentCapability, ToolInvoke, ToolResult |
| Version | `lib/src/version.dart` | Protocol/SDK version constants |

### Flutter Client (`client/`)

| Module | Path | Responsibility |
|---|---|---|
| App Shell | `lib/app/` | MaterialApp, router, theme |
| Providers | `lib/core/sdk_provider.dart` | Riverpod dependency injection |
| Auth | `lib/features/auth/` | Connection screen (URL + API key) |
| Chat | `lib/features/chat/` | Chat screen, controller, message adapter |

## Data Flow

### Agent → Human

```
Agent: POST /v1/chat/completions (HTTP, OpenAI format)
  → Server: stores message, pushes via WebSocket
    → SDK: OpenHumanConnection receives event
      → Client: OpenHumanClient dispatches to messages stream
        → Flutter: ChatController updates UI
```

### Human → Agent

```
Human: types reply in Chat input
  → Flutter: ChatController.sendReply()
    → Client: OpenHumanClient.sendReply()
      → SDK: OpenHumanConnection._sendWire()
        → Server: receives reply.send, delivers to SSE stream
          → Agent: receives SSE chunks + [DONE]
```

## Versioning

| Component | Version |
|---|---|
| Protocol | `1.0.0` |
| Dart SDK | `0.1.0` |
| Rust Server | `0.1.0` |
| Flutter Client | `0.1.0` |

See `protocol.md` for compatibility strategy.
