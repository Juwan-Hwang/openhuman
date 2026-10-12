# OpenHuman Dart SDK Guide

## Installation

### From Git (recommended for early development)

```yaml
# pubspec.yaml
dependencies:
  openhuman_sdk_dart:
    git:
      url: https://github.com/openhuman/openhuman.git
      path: sdks/dart
```

### From Local Path

```yaml
dependencies:
  openhuman_sdk_dart:
    path: ../sdks/dart
```

## API Overview

### `OpenHumanClient` — High-Level API

The single entry point for the Flutter UI layer.

```dart
final client = OpenHumanClient();
```

#### Typed Event Streams

| Stream | Event Type | Payload Type |
|---|---|---|
| `client.messages` | `message.received` | `MessageReceivedData` |
| `client.replyAcks` | `reply.delivered` | `ReplyDeliveredData` |
| `client.capabilityUpdates` | `capability.updated` | `CapabilityUpdatedData` |
| `client.toolResults` | `tool.result` | `ToolResultData` |
| `client.errors` | `error` | `ErrorData` |
| `client.rawEvents` | (all) | `OpenHumanEvent` |
| `client.connectionState` | (state changes) | `ConnectionState` |

#### Session State

- `client.currentHuman` — `HumanSession?` (set on `session.connected`)
- `client.activeConversations` — `List<String>` (conversation IDs seen)

#### Message Sending

- `client.sendReply(conversationId, text)` — Send a `reply.send`
- `client.updatePresence(status)` — Send a `presence.update`
- `client.publishCapabilityManifest(...)` — Send a `capability.manifest`
- `client.invokeTool(conversationId, toolId, input)` — Send a `tool.invoke`

### `OpenHumanConnection` — Transport Layer

Wraps the raw WebSocket. Usually accessed through `OpenHumanClient`.

```dart
final conn = OpenHumanConnection();
await conn.connect('ws://localhost:8080/ws', 'ohk_xxx');
conn.events.listen((event) => print(event.eventType));
```

## Model Classes

### Event Envelope

- `OpenHumanEvent` — `event_id`, `event_type`, `conversation_id`, `timestamp`, `data`
- `EventType` enum — `sessionConnected`, `messageReceived`, `replyDelivered`, `capabilityUpdated`, `toolResult`, `error`

### Event Payloads

- `SessionConnectedData` — `human_id`, `display_name`
- `MessageReceivedData` — `message_id`, `sender_id`, `sender_type`, `text`
- `ReplyDeliveredData` — `delivered`
- `CapabilityUpdatedData` — `agent_id`, `capabilities[]`, `context?`
- `ToolResultData` — `invocation_id`, `tool_id`, `status`, `output?`, `error?`
- `ErrorData` — `code`, `message`

### Client Messages

Each has a `toWireJson()` method that injects the `event_type` tag:

- `ReplySend` — `reply.send`
- `PresenceUpdate` — `presence.update`
- `CapabilityManifest` — `capability.manifest`
- `ToolInvokeMessage` — `tool.invoke`

### Internal Message Models

- `OpenHumanMessage` — Full message with sender, content, attachments, metadata, status
- `ContentBlock` (sealed union) — `text`, `structured`, `multipart`
- `ParticipantRef` — `participant_id`, `participant_type`
- `Attachment` — File reference with metadata

### Capability Models

- `AgentCapability` — Tool definition with input/output schemas
- `AgentContext` — Agent runtime context (system prompt, model, runtime info)
- `ToolInvoke` — `invocation_id`, `tool_id`, `input`
- `ToolResult` — `invocation_id`, `tool_id`, `status`, `output?`, `error?`
- `InvocationStatus` enum — `pending`, `success`, `error`, `cancelled`, `timeout`

## Version Constants

```dart
import 'package:openhuman_sdk_dart/openhuman.dart';

print(kOpenHumanProtocolVersion); // '1.0.0'
print(kOpenHumanSdkVersion);       // '0.1.0'
print(kOpenHumanSdkUserAgent);     // 'openhuman-sdk-dart/0.1.0 (protocol/1.0.0)'
```

## Testing

```bash
cd sdks/dart
dart test
```

85 protocol conformance tests covering event deserialization, wire-format field names, ContentBlock union decode, enum wire values, and round-trip serialization.
