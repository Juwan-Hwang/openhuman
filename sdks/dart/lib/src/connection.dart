/// OpenHuman Dart SDK — WebSocket connection layer.
///
/// This file implements the WebSocket lifecycle, authentication,
/// event receiving, and client message sending for the OpenHuman
/// realtime protocol.
///
/// Aligned with the Rust server WebSocket handler:
///
///   - `server/src/ws/handler.rs`   — connection lifecycle, auth, message loop
///   - `server/src/ws/protocol.rs`   — ClientMessage tagged union, Event envelope
///
/// and the protocol specification:
///
///   - `protocol/internal-model/event.md` — event envelope, delivery semantics
///
/// # Connection Lifecycle (from handler.rs)
///
/// 1. **Connect** — client opens `ws://host/ws?api_key=ohk_xxx`
/// 2. **Authenticate** — server resolves the API key → `AuthPrincipal`
/// 3. **Connected** — server sends `session.connected` event
/// 4. **Drain pending** — all `Pending` messages pushed to the client
/// 5. **Message loop** — server pushes events; client sends messages
/// 6. **Disconnect** — unregister; connection closed
///
/// # Auto-Reconnect
///
/// On unexpected disconnect, the connection automatically retries with
/// exponential backoff: 1s, 2s, 4s, 8s, 16s, ... capped at 30s.
///
/// # Authentication
///
/// The server expects the API key as a query parameter:
/// ```
/// GET /ws?api_key=ohk_xxx
/// ```
/// The key can also be passed as `?token=...` or `?authorization=...`
/// (with or without `Bearer ` prefix), but `api_key` is the canonical form.
library;

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'capabilities.dart';
import 'events.dart';

// ═════════════════════════════════════════════════════════════════
//  Constants
// ═════════════════════════════════════════════════════════════════

/// Exponential backoff sequence in seconds: 1, 2, 4, 8, 16, 30, 30, ...
const List<int> _backoffSeconds = [1, 2, 4, 8, 16, 30];

/// Maximum reconnect delay in seconds.
const int _maxBackoffSeconds = 30;

/// How long to wait for `session.connected` before treating the
/// handshake as failed.
///
/// A socket can be accepted and then go quiet — an intermediary holding
/// the connection open without the server ever seeing it. In that case
/// there is no error and no stream completion, so nothing would ever
/// trigger a retry: the state sits at `connecting` indefinitely. The
/// only way out is to give the handshake a deadline.
const Duration _handshakeTimeout = Duration(seconds: 25);

// ═════════════════════════════════════════════════════════════════
//  OpenHumanConnection
// ═════════════════════════════════════════════════════════════════

/// Manages a single WebSocket connection to the OpenHuman server.
///
/// This class is the transport layer between the Dart SDK and the
/// Rust server's `/ws` endpoint. It handles:
///
/// - **Lifecycle**: connect, disconnect, auto-reconnect with backoff
/// - **Authentication**: API key via query parameter
/// - **Receiving events**: `Stream<OpenHumanEvent>` from server JSON
/// - **Sending messages**: `reply.send`, `presence.update`,
///   `capability.manifest`, `tool.invoke`
/// - **Connection state**: `Stream<ConnectionState>` for UI binding
///
/// ## Usage
///
/// ```dart
/// final conn = OpenHumanConnection();
/// conn.connectionState.listen((state) {
///   print('Connection: $state');
/// });
/// conn.events.listen((event) {
///   print('Event: ${event.eventType}');
/// });
/// await conn.connect('ws://localhost:8080/ws', 'ohk_xxx');
/// ```
///
/// ## Wire Format
///
/// ### Server → Client (events)
///
/// The server sends JSON text frames using the `OpenHumanEvent`
/// envelope:
/// ```json
/// {
///   "event_id": "evt_0189abc",
///   "event_type": "message.received",
///   "conversation_id": "cnv_xxx",
///   "timestamp": "2025-01-15T09:28:00.123Z",
///   "data": { ... }
/// }
/// ```
///
/// Each frame is decoded via `OpenHumanEvent.fromJson()`.
///
/// ### Client → Server (messages)
///
/// The client sends JSON text frames using the `ClientMessage`
/// tagged union with `event_type` discriminator:
/// ```json
/// { "event_type": "reply.send", "conversation_id": "...", "text": "..." }
/// ```
///
/// Each message uses the corresponding `toWireJson()` method from
/// `events.dart`.
class OpenHumanConnection {
  OpenHumanConnection();

  // ── Internal state ─────────────────────────────────────────────

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;

  /// Deadline for the current handshake — see [_handshakeTimeout].
  Timer? _handshakeTimer;

  /// The URL we connected to (for reconnect).
  String? _url;

  /// The API key we connected with (for reconnect).
  String? _apiKey;

  /// Whether disconnect was user-initiated (suppresses reconnect).
  bool _userDisconnected = false;

  /// Current reconnect attempt count (resets on successful connect).
  int _reconnectAttempts = 0;

  // ── Stream controllers ─────────────────────────────────────────

  /// Controller for the public events stream.
  ///
  /// Events from the server are decoded and added to this stream.
  /// It's a broadcast stream so multiple listeners can subscribe.
  final _eventsController =
      StreamController<OpenHumanEvent>.broadcast();

  /// Controller for connection state changes.
  final _stateController =
      StreamController<ConnectionState>.broadcast();

  // ── Public API ─────────────────────────────────────────────────

  /// Stream of decoded server events.
  ///
  /// Each event is an [OpenHumanEvent] parsed from the server's JSON
  /// text frame. The stream is a broadcast stream — multiple listeners
  /// can subscribe.
  ///
  /// Example:
  /// ```dart
  /// conn.events.listen((event) {
  ///   if (event.eventType == 'message.received') {
  ///     final data = MessageReceivedData.fromJson(event.data);
  ///     print('Message from ${data.senderId}: ${data.text}');
  ///   }
  /// });
  /// ```
  Stream<OpenHumanEvent> get events => _eventsController.stream;

  /// Stream of connection state changes.
  ///
  /// States follow the lifecycle:
  /// ```
  /// idle → connecting → connected
  ///                 ↓              ↑
  ///            reconnecting ───────┘ (auto-reconnect with backoff)
  ///                 ↓
  ///            disconnected / error
  /// ```
  Stream<ConnectionState> get connectionState => _stateController.stream;

  /// The current connection state.
  ConnectionState _currentState = ConnectionState.idle;
  ConnectionState get currentState => _currentState;

  // ── Connect / Disconnect ───────────────────────────────────────

  /// Connect to the OpenHuman WebSocket server.
  ///
  /// The [apiKey] is sent as a query parameter (`?api_key=...`),
  /// matching the server's `WsQuery` struct in `handler.rs`:
  /// ```rust
  /// pub struct WsQuery {
  ///     pub api_key: Option<String>,
  ///     pub token: Option<String>,
  ///     pub authorization: Option<String>,
  /// }
  /// Cached device token for mobile push notifications.
  String? _deviceToken;

  /// Connect to the OpenHuman WebSocket server.
  ///
  /// Connects to [url] using [apiKey] for authentication, optionally
  /// registering [deviceToken] for push notifications.
  ///
  /// ```dart
  /// await conn.connect('ws://localhost:8080/ws', 'ohk_demo_alice_codex');
  /// ```
  ///
  /// On successful connection, the server sends a `session.connected`
  /// event which transitions the state to [ConnectionState.connected].
  ///
  /// If the connection drops unexpectedly, auto-reconnect with
  /// exponential backoff is attempted.
  Future<void> connect(String url, String apiKey, {String? deviceToken}) async {
    _url = url;
    _apiKey = apiKey;
    _deviceToken = deviceToken;
    _userDisconnected = false;
    _reconnectAttempts = 0;

    await _doConnect();
  }

  /// Internal connect — establishes the WebSocket and sets up listeners.
  Future<void> _doConnect() async {
    assert(_url != null && _apiKey != null);

    _setState(ConnectionState.connecting);

    try {
      // Build the WebSocket URI with api_key and optional device_token query parameter.
      final uri = _buildWsUri(_url!, _apiKey!, deviceToken: _deviceToken);

      _channel = WebSocketChannel.connect(uri);

      // Listen for incoming JSON text frames.
      _socketSub = _channel!.stream.listen(
        (data) {
          if (data is String) {
            _handleTextFrame(data);
          }
        },
        onError: (Object error) {
          _handleError(error);
        },
        onDone: () {
          _handleDone();
        },
        cancelOnError: true,
      );

      // Note: The state transitions to `connected` when the server
      // sends the `session.connected` event, not immediately upon
      // TCP/TLS handshake. However, if we're reconnecting, we reset
      // the attempt counter here since the handshake succeeded.
      _reconnectAttempts = 0;
      _startHandshakeWatchdog();
    } on Object catch (e) {
      _handleError(e);
    }
  }

  /// Arms the handshake deadline, cleared once the server confirms.
  void _startHandshakeWatchdog() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(_handshakeTimeout, _onHandshakeTimeout);
  }

  /// Called when `session.connected` never arrived.
  ///
  /// The socket is torn down rather than left open: a connection that
  /// looks alive but carries no traffic is worse than a closed one,
  /// because nothing downstream can tell the difference.
  Future<void> _onHandshakeTimeout() async {
    if (_userDisconnected || _currentState == ConnectionState.connected) {
      return;
    }
    print('[OpenHuman WS] handshake timed out after '
        '${_handshakeTimeout.inSeconds}s — retrying');

    _handshakeTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;

    _scheduleReconnect();
  }

  /// Build the WebSocket URI with `api_key` and optional `device_token` query parameter.
  ///
  /// If the URL already contains query parameters, `api_key` and `device_token`
  /// are appended with `&`.
  Uri _buildWsUri(String url, String apiKey, {String? deviceToken}) {
    final base = Uri.parse(url);
    final params = Map<String, String>.from(base.queryParameters);
    params['api_key'] = apiKey;
    if (deviceToken != null && deviceToken.isNotEmpty) {
      params['device_token'] = deviceToken;
    }
    return base.replace(queryParameters: params);
  }

  /// Disconnect from the server.
  ///
  /// This is a **user-initiated disconnect** — auto-reconnect is
  /// suppressed. The [connectionState] stream emits
  /// [ConnectionState.disconnected].
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _reconnectAttempts = 0;

    await _socketSub?.cancel();
    _socketSub = null;

    await _channel?.sink.close();
    _channel = null;

    _setState(ConnectionState.disconnected);
  }

  // ── Frame handling ────────────────────────────────────────────

  /// Handle an incoming JSON text frame from the server.
  ///
  /// The server sends `OpenHumanEvent` envelopes as JSON text.
  /// We decode and forward to the events stream.
  void _handleTextFrame(String text) {
    print('[OpenHuman WS RECV] $text');
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;

      // If we're still in `connecting` state, the first event from
      // the server is `session.connected` — transition to `connected`.
      if (_currentState == ConnectionState.connecting) {
        _handshakeTimer?.cancel();
        _handshakeTimer = null;
        _setState(ConnectionState.connected);
      }

      final event = OpenHumanEvent.fromJson(json);
      _eventsController.add(event);
    } on Object catch (e) {
      print('[OpenHuman WS JSON ERROR] $e');
      _eventsController.addError(
        FormatException('Failed to decode server event: $e', text),
      );
    }
  }

  /// Handle a WebSocket error.
  void _handleError(Object error) {
    print('[OpenHuman WS ERROR] $error');
    _setState(ConnectionState.error);

    if (!_userDisconnected) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket stream completion (server closed connection).
  void _handleDone() {
    print('[OpenHuman WS DONE] stream closed, userDisconnected=$_userDisconnected');
    if (_userDisconnected) {
      // disconnect() already set the state.
      return;
    }

    // Unexpected close — attempt reconnect.
    _scheduleReconnect();
  }

  // ── Auto-reconnect ────────────────────────────────────────────

  /// Schedule a reconnection attempt with exponential backoff.
  ///
  /// Backoff sequence: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, ...
  void _scheduleReconnect() {
    _setState(ConnectionState.reconnecting);

    final delaySeconds = _reconnectAttempts < _backoffSeconds.length
        ? _backoffSeconds[_reconnectAttempts]
        : _maxBackoffSeconds;

    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: delaySeconds),
      _doReconnect,
    );
  }

  /// Attempt a reconnection.
  Future<void> _doReconnect() async {
    if (_userDisconnected) return;

    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;

    await _doConnect();
  }

  // ── State management ────────────────────────────────────────────

  void _setState(ConnectionState state) {
    if (_currentState == state) return;
    _currentState = state;
    _stateController.add(state);
  }

  // ── Send: reply.send ───────────────────────────────────────────

  /// Send a `reply.send` message to the server.
  ///
  /// This is the human's reply to an agent's message. The server
  /// delivers it to the waiting SSE stream and stores it in the
  /// database.
  ///
  /// Wire format (aligned with `protocol.rs::ClientMessage::ReplySend`):
  /// ```json
  /// {
  ///   "event_type": "reply.send",
  ///   "conversation_id": "cnv_xxx",
  ///   "text": "the reply text",
  ///   "invocation_id": "inv_xxx" // optional, async mode only
  /// }
  /// ```
  void sendReply(String conversationId, String text, {String? invocationId}) {
    _sendWire(ReplySend(
      conversationId: conversationId,
      text: text,
      invocationId: invocationId,
    ).toWireJson());
  }

  // ── Send: presence.update ──────────────────────────────────────

  /// Send a `presence.update` message to the server.
  ///
  /// Updates the human's presence status. The server logs this
  /// (and in the future will broadcast a `presence.changed` event).
  ///
  /// Wire format:
  /// ```json
  /// {
  ///   "event_type": "presence.update",
  ///   "status": "online"
  /// }
  /// ```
  void updatePresence([HumanStatus status = HumanStatus.online]) {
    _sendWire(PresenceUpdate(status: status.name).toWireJson());
  }

  // ── Send: capability.manifest ──────────────────────────────────

  /// Send a `capability.manifest` message to the server.
  ///
  /// This is an **optional native extension** — agents that connect
  /// via WS using the OpenHuman SDK can publish their tool manifest.
  /// The server stores it and forwards a `capability.updated` event
  /// to the bound human's devices.
  ///
  /// Wire format:
  /// ```json
  /// {
  ///   "event_type": "capability.manifest",
  ///   "agent_id": "agt_xxx",
  ///   "capabilities": [ { "id": "...", "name": "...", ... } ],
  ///   "context": { "agent_id": "...", "system_prompt": "...", ... }
  /// }
  /// ```
  ///
  /// The [capabilities] should be a list of [AgentCapability] objects
  /// serialized to JSON maps. The [context] is optional.
  void publishCapabilityManifest({
    required String agentId,
    required List<AgentCapability> capabilities,
    AgentContext? context,
  }) {
    final manifest = CapabilityManifest(
      agentId: agentId,
      capabilities: capabilities
          .map((c) => c.toJson())
          .toList(),
      context: context?.toJson(),
    );
    _sendWire(manifest.toWireJson());
  }

  // ── Send: tool.invoke ──────────────────────────────────────────

  /// Send a `tool.invoke` message to the server.
  ///
  /// This is an **optional native extension** — the human can request
  /// that the agent invoke one of its own tools. The server validates
  /// the tool exists and routes the request to the agent's SSE stream.
  ///
  /// Wire format:
  /// ```json
  /// {
  ///   "event_type": "tool.invoke",
  ///   "conversation_id": "cnv_xxx",
  ///   "invocation_id": "inv_xxx",
  ///   "tool_id": "github_create_issue",
  ///   "input": { "repo": "...", "title": "..." }
  /// }
  /// ```
  void invokeTool({
    required String conversationId,
    required String invocationId,
    required String toolId,
    required dynamic input,
    String? text,
  }) {
    _sendWire(ToolInvokeMessage(
      conversationId: conversationId,
      invocationId: invocationId,
      toolId: toolId,
      input: input,
      text: text,
    ).toWireJson());
  }

  // ── Send: end.turn ──────────────────────────────────

  /// Send an `end.turn` message to the server.
  ///
  /// Multi-turn mode: the SSE stream stays open between replies so the
  /// human can send several messages (and make several tool calls) per
  /// agent request. This terminates the turn — the server closes the
  /// waiting SSE stream with `finish_reason: stop` + `[DONE]`.
  ///
  /// Wire format:
  /// ```json
  /// { "event_type": "end.turn", "conversation_id": "cnv_xxx" }
  /// ```
  void endTurn(String conversationId) {
    _sendWire({
      'event_type': 'end.turn',
      'conversation_id': conversationId,
    });
  }

  // ── Low-level send ─────────────────────────────────────────────

  /// Send a raw JSON map to the server via the WebSocket sink.
  ///
  /// The map is encoded as a JSON text frame. This is the single
  /// point of egress for all client → server messages.
  void _sendWire(Map<String, dynamic> json) {
    final channel = _channel;
    if (channel == null || _currentState != ConnectionState.connected) {
      throw StateError(
        'Cannot send: WebSocket is not connected '
        '(current state: $_currentState)',
      );
    }
    channel.sink.add(jsonEncode(json));
  }

  // ── Cleanup ────────────────────────────────────────────────────

  /// Release all resources.
  ///
  /// Call this when the connection is no longer needed to close
  /// the stream controllers and cancel timers.
  Future<void> dispose() async {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    await disconnect();
    await _eventsController.close();
    await _stateController.close();
  }
}
