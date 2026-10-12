/// OpenHuman Dart SDK — High-level client API.
///
/// [OpenHumanClient] is the **single entry point** for the Flutter UI
/// layer. It encapsulates [OpenHumanConnection] and provides typed,
/// categorized event streams and message-sending methods.
///
/// ## Architecture
///
/// ```
/// Flutter UI
///     ↓
/// OpenHumanClient (client.dart)
///     ↓
/// OpenHumanConnection (connection.dart)
///     ↓
/// WebSocket
///     ↓
/// Rust Server
/// ```
///
/// The client layer is responsible for:
///
/// - **Connection lifecycle** — connect, disconnect, state tracking
/// - **Event dispatch** — classifying raw [OpenHumanEvent] frames into
///   typed sub-streams (`messages`, `replyAcks`, `capabilityUpdates`,
///   `toolResults`, `errors`)
/// - **Session state** — extracting `human_id` / `display_name` from
///   the `session.connected` event
/// - **Active conversations** — tracking conversation IDs seen in
///   `message.received` events
/// - **Message sending** — delegating to [OpenHumanConnection]'s
///   `sendReply()`, `updatePresence()`, `publishCapabilityManifest()`,
///   and `invokeTool()` methods
///
/// ## Wire Format
///
/// All wire format is handled by `events.dart` (via `toWireJson()`)
/// and `connection.dart` (via `_sendWire()`). This layer never
/// touches JSON encoding directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'capabilities.dart';
import 'connection.dart';
import 'events.dart';
import 'history.dart';

// ═════════════════════════════════════════════════════════════════
//  Human Identity (session state)
// ═════════════════════════════════════════════════════════════════

/// Lightweight human identity extracted from `session.connected`.
///
/// This is not the full `HumanIdentity` model from the Rust server
/// (which includes avatar, capabilities, metadata, timestamps). It
/// contains only the fields the Flutter client needs for display
/// after a WebSocket session is established.
class HumanSession {
  const HumanSession({required this.id, required this.displayName});

  /// The authenticated human's ID (`hum_` prefixed).
  final String id;

  /// The human's display name (shown in the UI).
  final String displayName;
}

// ═════════════════════════════════════════════════════════════════
//  OpenHumanClient
// ═════════════════════════════════════════════════════════════════

/// The high-level OpenHuman client — Flutter UI's single entry point.
///
/// This class wraps [OpenHumanConnection] and provides:
///
/// - Typed event sub-streams for each event type
/// - Session state tracking (`currentHuman`)
/// - Active conversation tracking (`activeConversations`)
/// - Delegated message sending (`sendReply`, `updatePresence`,
///   `publishCapabilityManifest`, `invokeTool`)
///
/// ## Usage
///
/// ```dart
/// final client = OpenHumanClient();
///
/// // Listen to typed event streams
/// client.messages.listen((msg) {
///   print('From ${msg.senderId}: ${msg.text}');
/// });
/// client.connectionState.listen((state) {
///   if (state == ConnectionState.connected) {
///     print('Connected as ${client.currentHuman?.displayName}');
///   }
/// });
///
/// // Connect
/// await client.connect('ws://localhost:8080/ws', 'ohk_xxx');
///
/// // Send a reply
/// await client.sendReply('cnv_xxx', 'Sounds good, let me check.');
///
/// // Disconnect
/// await client.dispose();
/// ```
class OpenHumanClient {
  OpenHumanClient();

  // ── Underlying connection ──────────────────────────────────────

  /// The wrapped WebSocket connection.
  ///
  /// All message sending is delegated to this connection's methods.
  /// The client layer never touches the WebSocket directly.
  final OpenHumanConnection _connection = OpenHumanConnection();

  // ── Subscriptions ──────────────────────────────────────────────

  /// Subscription to the raw events stream from the connection.
  StreamSubscription<OpenHumanEvent>? _eventSub;

  /// Subscription to the connection state stream.
  StreamSubscription<ConnectionState>? _stateSub;

  // ── Typed event controllers (broadcast) ───────────────────────

  /// Controller for `message.received` events (typed).
  final _messagesController =
      StreamController<MessageReceivedData>.broadcast();

  /// Controller for `reply.delivered` events (typed).
  final _replyAcksController =
      StreamController<ReplyDeliveredData>.broadcast();

  /// Controller for `capability.updated` events (typed).
  final _capabilityUpdatesController =
      StreamController<CapabilityUpdatedData>.broadcast();

  /// Controller for `tool.result` events (typed).
  final _toolResultsController =
      StreamController<ToolResultData>.broadcast();

  /// Controller for `async.invocation.created` events (typed).
  final _asyncInvocationsController =
      StreamController<AsyncInvocationCreatedData>.broadcast();

  /// Controller for `error` events (typed).
  final _errorsController = StreamController<ErrorData>.broadcast();

  /// Controller for raw (untyped) events — passthrough.
  final _rawEventsController = StreamController<OpenHumanEvent>.broadcast();

  // ── Session state ──────────────────────────────────────────────

  /// The current human session, set when `session.connected` is received.
  ///
  /// `null` until the server sends `session.connected` after
  /// authentication.
  HumanSession? _currentHuman;
  HumanSession? get currentHuman => _currentHuman;

  // ── Active conversations ───────────────────────────────────────

  /// Set of conversation IDs seen in `message.received` events.
  ///
  /// Maintained automatically as events arrive. Useful for the UI
  /// to display a conversation list.
  final Set<String> _activeConversations = {};
  List<String> get activeConversations =>
      List.unmodifiable(_activeConversations);

  // ── HTTP (history) ─────────────────────────────────────────────

  /// Credentials kept from [connect] so history can be fetched.
  String? _apiKey;
  String? _baseUrl;

  // ═════════════════════════════════════════════════════════════
  //  Public streams
  // ═════════════════════════════════════════════════════════════

  /// Stream of connection state changes.
  ///
  /// Passthrough from [OpenHumanConnection.connectionState].
  Stream<ConnectionState> get connectionState =>
      _connection.connectionState;

  /// The current connection state.
  ConnectionState get currentState => _connection.currentState;

  /// Stream of `message.received` events, typed as
  /// [MessageReceivedData].
  ///
  /// Emitted when `event.eventType == 'message.received'`.
  Stream<MessageReceivedData> get messages => _messagesController.stream;

  /// Stream of `reply.delivered` events, typed as
  /// [ReplyDeliveredData].
  ///
  /// Emitted when `event.eventType == 'reply.delivered'`.
  Stream<ReplyDeliveredData> get replyAcks => _replyAcksController.stream;

  /// Stream of `capability.updated` events, typed as
  /// [CapabilityUpdatedData].
  ///
  /// Emitted when `event.eventType == 'capability.updated'`.
  Stream<CapabilityUpdatedData> get capabilityUpdates =>
      _capabilityUpdatesController.stream;

  /// Stream of `tool.result` events, typed as [ToolResultData].
  ///
  /// Emitted when `event.eventType == 'tool.result'`.
  Stream<ToolResultData> get toolResults => _toolResultsController.stream;

  /// Stream of `async.invocation.created` events.
  ///
  /// Emitted when `event.eventType == 'async.invocation.created'`. The
  /// console echoes [AsyncInvocationCreatedData.invocationId] back on its
  /// `reply.send` so the reply completes that specific invocation.
  Stream<AsyncInvocationCreatedData> get asyncInvocations =>
      _asyncInvocationsController.stream;

  /// Stream of `error` events, typed as [ErrorData].
  ///
  /// Emitted when `event.eventType == 'error'`.
  Stream<ErrorData> get errors => _errorsController.stream;

  /// Stream of raw, untyped [OpenHumanEvent] frames.
  ///
  /// This is a passthrough of all decoded server events. Useful for
  /// debugging or handling event types not yet covered by a typed
  /// sub-stream.
  Stream<OpenHumanEvent> get rawEvents => _rawEventsController.stream;

  // ═════════════════════════════════════════════════════════════
  //  Connection lifecycle
  // ═════════════════════════════════════════════════════════════

  /// Connect to the OpenHuman WebSocket server.
  ///
  /// Creates the underlying [OpenHumanConnection], calls
  /// `connection.connect(url, apiKey)`, and sets up event listeners.
  ///
  /// On success, the server sends a `session.connected` event which
  /// sets [currentHuman].
  Future<void> connect(String url, String apiKey, {String? deviceToken}) async {
    // Remembered so history can be fetched over HTTP: the socket carries
    // only what has not been delivered yet, so a console that wants the
    // past has to ask for it.
    _apiKey = apiKey;
    _baseUrl = _httpBaseFrom(url);

    // Set up event listeners before connecting so we don't miss
    // the `session.connected` event.
    _eventSub = _connection.events.listen(_dispatchEvent);
    _stateSub = _connection.connectionState.listen((_) {});

    await _connection.connect(url, apiKey, deviceToken: deviceToken);
  }

  /// Turn a WebSocket URL into the HTTP base it was reached through.
  ///
  /// `wss://host/ws` → `https://host`. A custom path is preserved so a
  /// deployment served from a sub-path still resolves.
  static String _httpBaseFrom(String wsUrl) {
    final uri = Uri.parse(wsUrl);
    final scheme = uri.scheme == 'wss'
        ? 'https'
        : (uri.scheme == 'ws' ? 'http' : uri.scheme);
    final path = uri.path.replaceFirst(RegExp(r'/ws/?$'), '');
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path.isEmpty ? null : path,
    ).toString();
  }

  /// Disconnect from the server.
  ///
  /// Delegates to [OpenHumanConnection.disconnect].
  Future<void> disconnect() async {
    await _connection.disconnect();
  }

  // ═════════════════════════════════════════════════════════════
  //  Event dispatch
  // ═════════════════════════════════════════════════════════════

  /// Dispatch a raw [OpenHumanEvent] to the appropriate typed
  /// sub-stream.
  ///
  /// This is the central event router. It classifies by
  /// `event.eventType` and forwards the parsed payload to the
  /// corresponding typed stream controller.
  void _dispatchEvent(OpenHumanEvent event) {
    // Always forward to the raw events stream.
    _rawEventsController.add(event);

    // Classify by event type and dispatch to typed streams.
    switch (EventTypeX.fromWireName(event.eventType)) {
      case EventType.sessionConnected:
        _handleSessionConnected(event);
        break;
      case EventType.messageReceived:
        _handleMessageReceived(event);
        break;
      case EventType.replyDelivered:
        _handleReplyDelivered(event);
        break;
      case EventType.capabilityUpdated:
        _handleCapabilityUpdated(event);
        break;
      case EventType.toolResult:
        _handleToolResult(event);
        break;
      case EventType.asyncInvocationCreated:
        _handleAsyncInvocationCreated(event);
        break;
      case EventType.error:
        _handleError(event);
        break;
      case null:
        // Unknown event type — already forwarded to rawEvents.
        break;
    }
  }

  /// Handle `session.connected` — extract `human_id` and
  /// `display_name` into [currentHuman].
  void _handleSessionConnected(OpenHumanEvent event) {
    try {
      final data = SessionConnectedData.fromJson(event.data);
      _currentHuman = HumanSession(
        id: data.humanId,
        displayName: data.displayName,
      );
    } on Object {
      // Malformed payload — ignore. The raw event is still
      // available via [rawEvents].
    }
  }

  /// Handle `message.received` — parse and forward to [messages],
  /// also track the conversation ID.
  void _handleMessageReceived(OpenHumanEvent event) {
    try {
      // Inject conversation_id into the data payload so that
      // MessageReceivedData carries it for downstream consumers.
      final data = Map<String, dynamic>.from(event.data);
      data['conversation_id'] = event.conversationId;
      final parsed = MessageReceivedData.fromJson(data);
      _activeConversations.add(event.conversationId);
      _messagesController.add(parsed);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  /// Handle `reply.delivered` — parse and forward to [replyAcks].
  void _handleReplyDelivered(OpenHumanEvent event) {
    try {
      final data = ReplyDeliveredData.fromJson(event.data);
      _replyAcksController.add(data);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  /// Handle `capability.updated` — parse and forward to
  /// [capabilityUpdates].
  void _handleCapabilityUpdated(OpenHumanEvent event) {
    try {
      final data = CapabilityUpdatedData.fromJson(event.data);
      _capabilityUpdatesController.add(data);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  /// Handle `tool.result` — parse and forward to [toolResults].
  void _handleToolResult(OpenHumanEvent event) {
    try {
      final data = ToolResultData.fromJson(event.data);
      _toolResultsController.add(data);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  /// Handle `async.invocation.created` — parse and forward to
  /// [asyncInvocations].
  void _handleAsyncInvocationCreated(OpenHumanEvent event) {
    try {
      // The envelope carries the conversation id; the payload only the
      // invocation id. Merge them so consumers get both in one object.
      final data = Map<String, dynamic>.from(event.data);
      data['conversation_id'] = event.conversationId;
      final parsed = AsyncInvocationCreatedData.fromJson(data);
      _asyncInvocationsController.add(parsed);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  /// Handle `error` — parse and forward to [errors].
  void _handleError(OpenHumanEvent event) {
    try {
      final data = ErrorData.fromJson(event.data);
      _errorsController.add(data);
    } on Object {
      // Malformed payload — ignore.
    }
  }

  // ═════════════════════════════════════════════════════════════
  //  Message sending (delegated to OpenHumanConnection)
  // ═════════════════════════════════════════════════════════════

  /// Send a `reply.send` message to the server.
  ///
  /// Delegates to [OpenHumanConnection.sendReply]. The server
  /// delivers the reply to the waiting SSE stream and stores it
  /// in the database. A `reply.delivered` ack event will arrive
  /// via [replyAcks].
  ///
  /// Wire format:
  /// ```json
  /// { "event_type": "reply.send", "conversation_id": "...", "text": "..." }
  /// ```
  Future<void> sendReply(
    String conversationId,
    String text, {
    String? invocationId,
  }) async {
    _connection.sendReply(conversationId, text, invocationId: invocationId);
  }

  /// Send a `presence.update` message to the server.
  ///
  /// Delegates to [OpenHumanConnection.updatePresence].
  ///
  /// Wire format:
  /// ```json
  /// { "event_type": "presence.update", "status": "online" }
  /// ```
  Future<void> updatePresence(HumanStatus status) async {
    _connection.updatePresence(status);
  }

  /// Send a `capability.manifest` message to the server.
  ///
  /// Delegates to [OpenHumanConnection.publishCapabilityManifest].
  /// This is an optional native extension — the server stores the
  /// capabilities and forwards a `capability.updated` event to the
  /// bound human's devices.
  ///
  /// Wire format:
  /// ```json
  /// {
  ///   "event_type": "capability.manifest",
  ///   "agent_id": "...",
  ///   "capabilities": [ { "id": "...", "name": "...", ... } ],
  ///   "context": { ... }
  /// }
  /// ```
  Future<void> publishCapabilityManifest({
    required String agentId,
    required List<AgentCapability> capabilities,
    AgentContext? context,
  }) async {
    _connection.publishCapabilityManifest(
      agentId: agentId,
      capabilities: capabilities,
      context: context,
    );
  }

  /// Send a `tool.invoke` message to the server.
  ///
  /// Delegates to [OpenHumanConnection.invokeTool]. The server
  /// validates the tool exists and routes the request to the
  /// agent's SSE stream. The result will arrive via [toolResults].
  ///
  /// Wire format:
  /// ```json
  /// {
  ///   "event_type": "tool.invoke",
  ///   "conversation_id": "...",
  ///   "invocation_id": "...",
  ///   "tool_id": "...",
  ///   "input": { ... }
  /// }
  /// ```
  Future<void> invokeTool(
    String conversationId,
    String toolId,
    dynamic input, {
    String? text,
  }) async {
    _connection.invokeTool(
      conversationId: conversationId,
      invocationId: 'inv_${DateTime.now().microsecondsSinceEpoch}',
      toolId: toolId,
      input: input,
      text: text,
    );
  }

  /// Send an `end.turn` message to the server.
  ///
  /// In multi-turn mode the SSE stream stays open between replies so the
  /// human can send several messages (and make several tool calls) per
  /// agent request. This method terminates the turn — the server closes
  /// the SSE stream with `finish_reason: stop` + `[DONE]`.
  ///
  /// Wire format:
  /// ```json
  /// { "event_type": "end.turn", "conversation_id": "..." }
  /// ```
  Future<void> endTurn(String conversationId) async {
    _connection.endTurn(conversationId);
  }

  // ═════════════════════════════════════════════════════════════
  //  Cleanup
  // ═════════════════════════════════════════════════════════════

  // ═════════════════════════════════════════════════════════════
  //  History
  // ═════════════════════════════════════════════════════════════

  /// The human's conversations, newest activity first.
  ///
  /// A freshly connected console has no messages: the socket backlog only
  /// carries what has not been delivered yet. Call this to populate the
  /// conversation list on startup.
  Future<List<HistoryConversation>> fetchConversations({
    int limit = 50,
  }) async {
    final body = await _getJson('/v1/conversations?limit=$limit');
    final data = (body['data'] as List?) ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HistoryConversation.fromJson)
        .toList();
  }

  /// The human's discarded conversations, most recently discarded first.
  Future<List<HistoryConversation>> fetchTrash({int limit = 50}) async {
    final body = await _getJson(
      '/v1/conversations?limit=$limit&deleted=true',
    );
    return (body['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HistoryConversation.fromJson)
        .toList();
  }

  /// Rename an agent.
  ///
  /// The name the seed data or the issuing tool chose is rarely what the
  /// human calls it. Scoped server-side to the agent this key was issued
  /// under, so it cannot rename another agent's.
  Future<bool> renameAgent(String agentId, String name) async {
    return _send(
      '/v1/agents/$agentId',
      method: 'PATCH',
      body: {'name': name},
    );
  }

  /// Move a conversation to the trash. It stays restorable.
  Future<bool> deleteConversation(String conversationId) async {
    return _send('/v1/conversations/$conversationId', method: 'DELETE');
  }

  /// Take a conversation back out of the trash.
  Future<bool> restoreConversation(String conversationId) async {
    return _send(
      '/v1/conversations/$conversationId/restore',
      method: 'POST',
    );
  }

  /// Destroy a conversation for good. Not reversible.
  Future<bool> deleteConversationPermanently(String conversationId) async {
    return _send(
      '/v1/conversations/$conversationId/permanent',
      method: 'DELETE',
    );
  }

  /// A conversation's messages, oldest first.
  ///
  /// [limit] caps how many of the most recent messages come back.
  Future<List<HistoryMessage>> fetchMessages(
    String conversationId, {
    int limit = 100,
  }) async {
    final body = await _getJson(
      '/v1/conversations/$conversationId/messages?limit=$limit',
    );
    final data = (body['data'] as List?) ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HistoryMessage.fromJson)
        .toList();
  }

  /// How long a history request may take before it is abandoned.
  ///
  /// Generous on purpose: history is fetched in the background and never
  /// blocks the UI, so waiting beats giving up on a slow link — the
  /// console keeps working either way and retries on the next connection.
  static const Duration _httpTimeout = Duration(seconds: 30);

  /// Send a request that is not a plain GET.
  ///
  /// Returns false rather than throwing for a failed rename or delete:
  /// the caller is a button handler, and a 404 on someone else's
  /// conversation is a result to show, not an exception to unwind.
  Future<bool> _send(
    String path, {
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final base = _baseUrl;
    final key = _apiKey;
    if (base == null || key == null) return false;

    final client = HttpClient();
    try {
      final request = await client
          .openUrl(method, Uri.parse('$base$path'))
          .timeout(_httpTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_httpTimeout);
      await response.drain<void>().timeout(_httpTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('[OpenHuman] $method $path failed: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final base = _baseUrl;
    final key = _apiKey;
    if (base == null || key == null) {
      throw StateError('fetch called before connect()');
    }

    final client = HttpClient();
    try {
      // Bounded: a request that never completes would leave the caller
      // waiting forever with no error to report, and the caller is the
      // thing that decides whether history ever appears.
      final request = await client
          .getUrl(Uri.parse('$base$path'))
          .timeout(_httpTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.contentType = ContentType.json;
      final response = await request.close().timeout(_httpTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_httpTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GET $path failed with ${response.statusCode}: $text',
          uri: Uri.parse('$base$path'),
        );
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } finally {
      client.close(force: true);
    }
  }

  /// Release all resources.
  ///
  /// Cancels all subscriptions, closes all stream controllers,
  /// and disposes the underlying connection.
  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _stateSub?.cancel();
    _stateSub = null;

    _messagesController.close();
    _replyAcksController.close();
    _capabilityUpdatesController.close();
    _toolResultsController.close();
    _asyncInvocationsController.close();
    _errorsController.close();
    _rawEventsController.close();

    _connection.dispose();
  }
}
