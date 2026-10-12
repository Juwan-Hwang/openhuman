# OpenHuman Dart SDK

Official Dart SDK for [OpenHuman](https://github.com/openhuman/openhuman) — the Human-as-an-API platform.

## Overview

OpenHuman allows a real human to become a standard API endpoint accessible by AI agents and applications. This SDK provides the WebSocket transport layer, typed protocol models, and event dispatch for Dart/Flutter clients.

## Installation

```yaml
dependencies:
  openhuman_sdk_dart:
    git:
      url: https://github.com/openhuman/openhuman.git
      path: sdks/dart
```

## Quick Start

```dart
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() async {
  final client = OpenHumanClient();

  // Listen for incoming messages
  client.messages.listen((msg) {
    print('From ${msg.senderId}: ${msg.text}');
  });

  // Listen for connection state changes
  client.connectionState.listen((state) {
    print('Connection: $state');
  });

  // Connect to the server
  await client.connect('ws://localhost:8080/ws', 'ohk_your_api_key');

  // Send a reply
  await client.sendReply('cnv_xxx', 'I received your message.');

  // Disconnect when done
  await client.disconnect();
}
```

## Architecture

```
Flutter UI
    ↓
OpenHumanClient (client.dart)
    ↓
OpenHumanConnection (connection.dart)
    ↓
WebSocket
    ↓
Rust Server
```

### Layers

| Layer | File | Responsibility |
|---|---|---|
| High-level API | `client.dart` | Event dispatch, session state, typed streams |
| Transport | `connection.dart` | WebSocket lifecycle, auth, auto-reconnect |
| Events | `events.dart` | Event envelope, Client→Server messages |
| Messages | `messages.dart` | Internal message model, ContentBlock union |
| Capabilities | `capabilities.dart` | AgentCapability, ToolInvoke, ToolResult |

## Protocol

All JSON fields use `snake_case` wire format. Dart fields use `camelCase` with `@JsonKey` annotations for mapping.

### Server → Client Events

| `event_type` | Payload |
|---|---|
| `session.connected` | `SessionConnectedData` |
| `message.received` | `MessageReceivedData` |
| `reply.delivered` | `ReplyDeliveredData` |
| `capability.updated` | `CapabilityUpdatedData` |
| `tool.result` | `ToolResultData` |
| `error` | `ErrorData` |

### Client → Server Messages

| `event_type` | Method |
|---|---|
| `reply.send` | `client.sendReply()` |
| `presence.update` | `client.updatePresence()` |
| `capability.manifest` | `client.publishCapabilityManifest()` |
| `tool.invoke` | `client.invokeTool()` |

## Testing

```bash
cd sdks/dart
dart test
```

## License

TBD
