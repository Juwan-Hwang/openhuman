# OpenHuman Flutter Client Guide

## Overview

The Flutter client is the official Human Endpoint Runtime UI. It provides:

- Connection management (AuthScreen)
- Chat interface (ChatScreen + Flyer Chat)
- Realtime message display
- Reply sending

## Project Structure

```
client/
  lib/
    main.dart                          — Entry point (ProviderScope + OpenHumanApp)
    app/
      app.dart                         — MaterialApp.router
      routes.dart                      — GoRouter config (/auth, /)
      theme.dart                       — Material 3 light/dark themes
    core/
      sdk_provider.dart                — Riverpod providers (client, state, messages)
    features/
      auth/
        auth_screen.dart               — URL + API key input, connect
      chat/
        chat_screen.dart               — Flyer Chat UI, AppBar with state
        chat_controller.dart           — StateNotifier managing messages
        message_adapter.dart           — SDK → Flyer Chat type mapping
  test/
    auth_screen_test.dart              — 7 widget tests
    chat_screen_test.dart              — 6 widget tests
  pubspec.yaml
```

## Riverpod Providers

```dart
// Singleton client (app lifetime)
final openHumanClientProvider = Provider<OpenHumanClient>((ref) { ... });

// Connection state stream
final connectionStateProvider = StreamProvider<ConnectionState>(...);

// Current human session
final currentHumanProvider = StateProvider<HumanSession?>((ref) => null);

// Incoming messages stream
final messagesProvider = StreamProvider<MessageReceivedData>(...);

// Active conversation ID
final activeConversationIdProvider = StateProvider<String?>((ref) => null);

// Chat state (message list)
final chatControllerProvider =
    StateNotifierProvider<ChatController, List<types.Message>>(...);

// Router
final routerProvider = Provider<GoRouter>((ref) => ...);
```

## Data Flow

### Receiving a Message

```
Server → WebSocket → OpenHumanConnection._handleTextFrame()
  → OpenHumanEvent.fromJson()
  → OpenHumanClient._dispatchEvent()
  → MessageReceivedData.fromJson()
  → _messagesController.add(data)
  → ChatController._onMessageReceived()
  → messageReceivedToTextMessage()
  → state = [...state, message]
  → Chat widget rebuilds
```

### Sending a Reply

```
User taps send → Chat widget onSendPressed
  → ChatController.sendReply(text)
  → buildOutgoingTextMessage() → state = [...state, msg]
  → OpenHumanClient.sendReply(conversationId, text)
  → OpenHumanConnection.sendReply()
  → ReplySend.toWireJson()
  → _sendWire() → WebSocket → Server
```

## Architecture Constraints

- **No direct WebSocket imports** in `client/lib/` — all network logic in SDK
- **No direct JSON encoding** in `client/lib/` — handled by SDK's `toWireJson()`
- **All SDK access via Riverpod providers** — no direct instantiation
- **Message adapter is the only boundary** between SDK types and Flyer Chat types

## Testing

```bash
cd client
flutter test
```

13 widget tests covering AuthScreen (UI rendering, validation, connect) and ChatScreen (UI rendering, message display, send reply).
