/// Chat controller — manages chat state and SDK interaction.
///
/// ## Architectural Principle
///
/// The [ChatController] timeline **only** accepts `message.received`
/// events. These are genuine communication messages from the agent.
///
/// System events (`session.connected`, `capability.updated`,
/// `reply.delivered`, `error`) are **never** injected into the
/// message timeline. They are handled by separate providers and
/// rendered in independent UI components.
///
/// ## Multi-Conversation Support
///
/// Messages are bucketed per conversation. The [state] reflects ONLY
/// the active conversation (from [activeConversationIdProvider]) —
/// switching the active conversation swaps the visible timeline.
///
/// ## Data Flow
///
/// ```
/// SDK events
///   ├── message.received  → ChatController → per-conversation buckets
///   │                                        └─ active bucket → timeline
///   ├── session.connected → currentHumanProvider (identity only)
///   ├── capability.updated → capabilityCacheProvider (agent runtime)
///   ├── reply.delivered   → internal status update (no new message)
///   └── error             → systemEventsProvider (system event card)
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../core/sdk_provider.dart';
import 'message_adapter.dart';

/// State notifier that manages the chat UI state.
///
/// The state is a list of [types.Message] — **only** real
/// communication messages of the ACTIVE conversation. No system
/// prompts, no agent metadata, no tool definitions, no runtime context.
class ChatController extends StateNotifier<List<types.Message>> {
  ChatController(this._ref) : super(const []) {
    _init();
  }

  final Ref _ref;

  // ── Subscriptions ──────────────────────────────────────────────

  StreamSubscription<oh.MessageReceivedData>? _messageSub;
  StreamSubscription<oh.OpenHumanEvent>? _rawEventSub;
  StreamSubscription<oh.ReplyDeliveredData>? _replyAckSub;
  StreamSubscription<oh.ConnectionState>? _connSub;
  ProviderSubscription<String?>? _activeConvSub;

  /// Whether history has been fetched for the current connection.
  bool _historyLoaded = false;

  // ── Cached user objects ────────────────────────────────────────

  /// The Flyer Chat user for the authenticated human.
  types.User _humanUser = const types.User(id: 'unknown');
  types.User get humanUser => _humanUser;

  // ── Per-conversation message buckets ───────────────────────────
  //
  // Key: conversation ID. Value: messages with the NEWEST FIRST —
  // Flyer Chat renders `reverse: true`, so index 0 appears at the
  // BOTTOM of the viewport (natural chat order).

  final Map<String, List<types.Message>> _byConversation = {};

  // ═════════════════════════════════════════════════════════════
  //  Initialization
  // ═════════════════════════════════════════════════════════════

  void _init() {
    final client = _ref.read(openHumanClientProvider);

    // Only message.received events enter the chat timeline.
    _messageSub = client.messages.listen(_onMessageReceived);

    // Raw events for session.connected (identity extraction only).
    _rawEventSub = client.rawEvents.listen(_onRawEvent);

    // Reply delivery acks — update status of existing messages only.
    _replyAckSub = client.replyAcks.listen(_onReplyDelivered);

    // Switch the visible timeline when the active conversation changes.
    _activeConvSub = _ref.listen<String?>(
      activeConversationIdProvider,
      (prev, next) {
        if (next != null && next != prev) {
          final bucket = _byConversation[next];
          state = bucket != null
              ? List<types.Message>.unmodifiable(bucket)
              : const [];
          // Conversations beyond the up-front limit have a slot but no
          // messages yet; fill it the first time one is opened.
          if (bucket == null || bucket.isEmpty) {
            unawaited(_loadMessages(next));
          }
        }
      },
    );

    // History needs the credentials that `connect` records, and the
    // controller outlives a single connection. Fetching here would run
    // before any connect and find nothing, so wait for a live socket.
    _connSub = client.connectionState.listen((connState) {
      if (connState == oh.ConnectionState.connected) {
        unawaited(_loadHistory());
      } else if (connState == oh.ConnectionState.reconnecting ||
          connState == oh.ConnectionState.disconnected ||
          connState == oh.ConnectionState.error) {
        // The socket dropped — allow a refetch on the next connection.
        // Without this a reconnected console keeps whatever it had, and
        // anything that arrived while offline never appears.
        _historyLoaded = false;
      }
    });

    // Already connected (reconnect into an existing session).
    if (client.currentState == oh.ConnectionState.connected) {
      unawaited(_loadHistory());
    }
  }

  /// Load past conversations and their messages.
  ///
  /// The socket only carries what has not been delivered yet, so without
  /// this a freshly opened console shows an empty timeline even though the
  /// history is sitting on the server.
  Future<void> _loadHistory() async {
    final client = _ref.read(openHumanClientProvider);

    // One load per connection is enough; without this a flapping socket
    // would refetch everything repeatedly.
    if (_historyLoaded) return;
    _historyLoaded = true;

    try {
      // One request. Firing a request per conversation — even in
      // parallel — starves every one of them on a slow link: they all
      // hit the timeout together and the console ends up with nothing
      // at all, which is worse than loading them lazily.
      final conversations = await client.fetchConversations();
      if (conversations.isEmpty) return;

      // Newest activity first, matching what the sidebar implies.
      conversations.sort((a, b) => b.sortKey.compareTo(a.sortKey));

      // Give every conversation a slot so the sidebar can list it.
      // Messages are not fetched here; opening one fetches its messages.
      for (final conversation in conversations) {
        _byConversation.putIfAbsent(conversation.id, () => []);
      }

      // Open the most recent conversation.
      final active = _ref.read(activeConversationIdProvider);
      final first = active ?? conversations.first.id;
      if (active == null) {
        _ref.read(activeConversationIdProvider.notifier).state = first;
      }

      // Messages for the conversation being shown, so the timeline is
      // not empty on arrival.
      await _loadMessages(first);
    } catch (e, st) {
      // History is a nicety and must not take the console down, but
      // swallowing it silently is what let this stay broken — an empty
      // timeline looks identical whether the fetch failed or there was
      // nothing to fetch.
      debugPrint('[Chat] history load failed: $e\n$st');
      _historyLoaded = false; // allow a retry on the next connection
    }
  }

  /// Fetch one conversation's messages and show them if it is still open.
  Future<void> _loadMessages(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);

    try {
      final messages = await client.fetchMessages(conversationId);
      final bucket = _byConversation.putIfAbsent(conversationId, () => []);
      if (bucket.isNotEmpty) return;

      for (final m in messages) {
        bucket.insertAll(
          0,
          historyMessageToMessages(m, humanUser: _humanUser).reversed,
        );
      }

      if (_ref.read(activeConversationIdProvider) == conversationId) {
        state = List<types.Message>.unmodifiable(bucket);
      }
    } catch (e, st) {
      debugPrint('[Chat] failed to load $conversationId: $e\n$st');
    }
  }

  // ═════════════════════════════════════════════════════════════
  //  Event handlers
  // ═════════════════════════════════════════════════════════════

  /// Handle `session.connected` — extract human identity only.
  ///
  /// This does NOT create a chat message. The session connection is
  /// a system event, displayed in the AppBar / AgentRuntimePanel.
  void _onRawEvent(oh.OpenHumanEvent event) {
    if (event.eventType == 'session.connected') {
      final human = _ref.read(openHumanClientProvider).currentHuman;
      if (human != null) {
        _humanUser = humanSessionToUser(human);
        _ref.read(currentHumanProvider.notifier).state = human;
      }
    }
  }

  /// Handle `message.received` — the ONLY event that creates a
  /// chat message in the timeline.
  void _onMessageReceived(oh.MessageReceivedData data) {
    // Convert to Flyer Chat messages — one for the text, plus one per
    // image when the agent sent any.
    final messages = messageReceivedToMessages(
      data,
      eventTimestamp: DateTime.now(),
      humanUser: _humanUser,
    );

    // Bucket by conversation, newest first (see field docs).
    final bucket =
        _byConversation.putIfAbsent(data.conversationId, () => []);

    // Prevent duplicate messages if already present in this conversation
    if (bucket.any((m) => m.id == data.messageId)) {
      return;
    }

    // The human's own replies are echoed back by the server. Drop the
    // optimistic local copy, otherwise the same reply shows twice.
    if (data.senderType.toLowerCase() == 'human') {
      bucket.removeWhere(
        (m) =>
            m.id.startsWith('outgoing_') &&
            m is types.TextMessage &&
            m.text == data.text,
      );
    }

    // Newest first, so later entries are inserted ahead of earlier ones.
    bucket.insertAll(0, messages.reversed);

    // Activate the first conversation we ever see.
    final active = _ref.read(activeConversationIdProvider);
    if (active == null) {
      _ref.read(activeConversationIdProvider.notifier).state =
          data.conversationId;
      state = List<types.Message>.unmodifiable(bucket);
      return;
    }

    // Update the timeline only if this message belongs to the
    // active conversation — other conversations update silently.
    if (data.conversationId == active) {
      state = List<types.Message>.unmodifiable(bucket);
    }
  }

  /// Handle `reply.delivered` — update message status only.
  ///
  /// This does not create a new message. It only updates the delivery
  /// status of the last outgoing message, in both the bucket and the
  /// visible timeline — updating only `state` would lose the status as
  /// soon as the conversation is switched away and back.
  void _onReplyDelivered(oh.ReplyDeliveredData data) {
    final conversationId = _ref.read(activeConversationIdProvider);
    final bucket = conversationId == null
        ? null
        : _byConversation[conversationId];
    if (bucket == null) return;

    for (var i = 0; i < bucket.length; i++) {
      final msg = bucket[i];
      if (msg.author.id == _humanUser.id &&
          msg.status == types.Status.sent) {
        bucket[i] = msg.copyWith(status: types.Status.delivered);
        break;
      }
    }
    state = List<types.Message>.unmodifiable(bucket);
  }

  // ═════════════════════════════════════════════════════════════
  //  Send message
  // ═════════════════════════════════════════════════════════════

  /// Send a reply via the SDK and immediately add it to the UI.
  ///
  /// Returns `false` when the reply could not be sent (no conversation,
  /// or the socket is down) — the optimistic message is rolled back so
  /// the timeline never shows a reply that went nowhere.
  bool sendReply(String text) {
    if (text.trim().isEmpty) return false;

    final client = _ref.read(openHumanClientProvider);
    final conversationId = _ref.read(activeConversationIdProvider) ??
        (client.activeConversations.isNotEmpty
            ? client.activeConversations.first
            : null);
    if (conversationId == null) return false;

    final tempId = 'outgoing_${DateTime.now().microsecondsSinceEpoch}';

    final outgoingMessage = buildOutgoingTextMessage(
      text: text,
      humanUser: _humanUser,
      messageId: tempId,
    );

    // Bucket + timeline (newest first = bottom of the viewport).
    final bucket = _byConversation.putIfAbsent(conversationId, () => []);
    bucket.insert(0, outgoingMessage);

    if (conversationId == _ref.read(activeConversationIdProvider)) {
      state = List<types.Message>.unmodifiable(bucket);
    }

    try {
      unawaited(client.sendReply(conversationId, text));
      return true;
    } on StateError catch (e) {
      // Socket is down: roll the optimistic message back. Showing it as
      // sent would be a lie — the server never saw it.
      debugPrint('[Chat] send failed, rolling back: $e');
      bucket.removeWhere((m) => m.id == tempId);
      if (conversationId == _ref.read(activeConversationIdProvider)) {
        state = List<types.Message>.unmodifiable(bucket);
      }
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════
  //  Cleanup
  // ═════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _messageSub?.cancel();
    _rawEventSub?.cancel();
    _replyAckSub?.cancel();
    _connSub?.cancel();
    _activeConvSub?.close();
    super.dispose();
  }
}

/// Provider for the [ChatController].
final chatControllerProvider =
    StateNotifierProvider<ChatController, List<types.Message>>((ref) {
  return ChatController(ref);
});
