# Changelog

All notable changes to the OpenHuman Dart SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `asyncInvocations` stream + `AsyncInvocationCreatedData`: the client can
  now receive `async.invocation.created` and echo the invocation id back,
  which is what makes async turns answerable.
- `sendReply(..., invocationId: ...)` — complete a specific async turn.
- `invokeTool(..., text: ...)` — companion prose rides alongside the call.

### Fixed

- `MessageReceivedData` test fixture now includes `conversation_id`, which
  the client injects from the event envelope (the regenerated serializer
  rejects its absence).

## [0.1.0] — 2026-08-25

### Added

- Initial release of the OpenHuman Dart SDK.
- `OpenHumanClient` — high-level API with typed event sub-streams
  (`messages`, `replyAcks`, `capabilityUpdates`, `toolResults`, `errors`,
  `rawEvents`).
- `OpenHumanConnection` — WebSocket transport layer with auto-reconnect
  (exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s cap).
- `OpenHumanEvent` — event envelope (de)serialization aligned 1:1 with
  Rust `server/src/model/event.rs`.
- `SessionConnectedData`, `MessageReceivedData`, `ReplyDeliveredData`,
  `CapabilityUpdatedData`, `ToolResultData`, `ErrorData` — typed event payloads.
- `ReplySend`, `PresenceUpdate`, `CapabilityManifest`, `ToolInvokeMessage` —
  Client→Server message classes with `toWireJson()`.
- `ContentBlock` sealed union (`text`, `structured`, `multipart`) with
  `@Freezed(unionKey: 'type')` discriminator matching Rust's `#[serde(tag = "type")]`.
- `ParticipantRef`, `ParticipantType`, `MessageStatus`, `Attachment`,
  `OpenHumanMessage` — internal message models.
- `AgentCapability`, `AgentContext`, `ToolInvoke`, `ToolResult`,
  `InvocationStatus` — capability and tool invocation models.
- `EventType` enum with `wireName` / `fromWireName` bidirectional mapping.
- `ConnectionState` enum (idle, connecting, connected, reconnecting,
  disconnected, error).
- `HumanSession` — lightweight session identity for Flutter UI.
- Protocol conformance tests: 85 tests covering event deserialization,
  wire-format field names, snake_case mapping, ContentBlock union decode,
  enum wire values, round-trip serialization, Client→Server `toWireJson`.

### Protocol Version

- Protocol version: `1.0.0`
- SDK version: `0.1.0`
- Minimum server version: `0.1.0`
