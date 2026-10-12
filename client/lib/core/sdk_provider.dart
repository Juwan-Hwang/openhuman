/// Riverpod providers for the OpenHuman SDK.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

// ═══════════════════════════════════════════════════════════════
//  OpenHumanClient — singleton, app-lifetime
// ═══════════════════════════════════════════════════════════════

final openHumanClientProvider = Provider<oh.OpenHumanClient>((ref) {
  final client = oh.OpenHumanClient();
  ref.onDispose(client.dispose);
  return client;
});

// ═══════════════════════════════════════════════════════════════
//  Connection state
// ═══════════════════════════════════════════════════════════════

final connectionStateProvider =
    StreamProvider<oh.ConnectionState>((ref) async* {
  final client = ref.watch(openHumanClientProvider);
  // The underlying stream is broadcast and does not replay: a UI that
  // subscribes after the socket connected would wait forever and show
  // "Not connected" while messages arrive just fine.
  yield client.currentState;
  yield* client.connectionState;
});

// ═══════════════════════════════════════════════════════════════
//  Current human identity
// ═══════════════════════════════════════════════════════════════

final currentHumanProvider = StateProvider<oh.HumanSession?>((ref) {
  return null;
});

// ═══════════════════════════════════════════════════════════════
//  Active conversation ID
// ═══════════════════════════════════════════════════════════════

final activeConversationIdProvider = StateProvider<String?>((ref) {
  return null;
});

// ═══════════════════════════════════════════════════════════════
//  Active server connection configuration (URL, API Key)
// ═══════════════════════════════════════════════════════════════

class ServerConfig {
  const ServerConfig({this.serverUrl = '', this.apiKey = ''});

  final String serverUrl;
  final String apiKey;
}

final serverConfigProvider = StateProvider<ServerConfig>((ref) {
  return const ServerConfig();
});

// ═══════════════════════════════════════════════════════════════
//  Capability Cache — always-on, survives panel open/close
// ═══════════════════════════════════════════════════════════════

/// Cached capability updates — always subscribed, even when the
/// Runtime Panel is closed. This prevents missing capability events.
final capabilityCacheProvider =
    StateNotifierProvider<CapabilityCacheNotifier, oh.CapabilityUpdatedData?>((ref) {
  return CapabilityCacheNotifier(ref);
});

class CapabilityCacheNotifier extends StateNotifier<oh.CapabilityUpdatedData?> {
  CapabilityCacheNotifier(this._ref) : super(null) {
    _sub = _ref.read(openHumanClientProvider).capabilityUpdates.listen((data) {
      state = data;
    });
  }

  final Ref _ref;
  late final StreamSubscription _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Conversation list — tracks all conversations seen via WS
// ═══════════════════════════════════════════════════════════════

class ConversationInfo {
  ConversationInfo({
    required this.id,
    required this.agentId,
    required this.agentName,
    this.lastMessage,
    this.lastMessageTime,
  });

  final String id;
  final String agentId;
  final String agentName;
  String? lastMessage;
  DateTime? lastMessageTime;
}

final conversationListProvider =
    StateNotifierProvider<ConversationListNotifier, ConversationListState>((ref) {
  return ConversationListNotifier(ref);
});

class ConversationListNotifier extends StateNotifier<ConversationListState> {
  ConversationListNotifier(this._ref) : super(const ConversationListState()) {
    final client = _ref.read(openHumanClientProvider);

    _msgSub = client.messages.listen((data) {
      final entries = state.entries;
      final existing = entries
          .where((c) => c.id == data.conversationId)
          .firstOrNull;
      if (existing != null) {
        existing.lastMessage = data.text;
        existing.lastMessageTime = DateTime.now();
        state = state.copyWith(entries: [...entries]..sort(_newestFirst));
      } else {
        state = state.copyWith(
          entries: [
            ConversationInfo(
              id: data.conversationId,
              agentId: data.senderId,
              agentName: data.senderName ?? data.senderId,
              lastMessage: data.text,
              lastMessageTime: DateTime.now(),
            ),
            ...entries,
          ],
        );
      }
    });

    // Live events alone start the list empty — the past has to be asked
    // for. Broadcast streams do not replay, so drive this off state
    // changes and cover the already-connected case too.
    _connSub = client.connectionState.listen((connState) {
      if (connState == oh.ConnectionState.connected) {
        _populateFromHistory();
      }
    });
    if (client.currentState == oh.ConnectionState.connected) {
      _populateFromHistory();
    }
  }

  final Ref _ref;
  late final StreamSubscription _msgSub;
  late final StreamSubscription _connSub;
  bool _populated = false;
  bool _loading = false;

  /// Fill the sidebar from the history endpoint.
  ///
  /// Entries already carrying a live message keep their preview; entries
  /// the history does not know about (brand-new conversations) survive.
  Future<void> _populateFromHistory() async {
    if (_populated || _loading) return;
    _populated = true;
    _loading = true;
    _setStatus(ConversationListStatus.loading);

    try {
      final client = _ref.read(openHumanClientProvider);
      final conversations = await client.fetchConversations();
      if (!mounted) return;

      final existing = {for (final c in state.entries) c.id: c};
      final merged = <ConversationInfo>[];
      for (final c in conversations) {
        final old = existing[c.id];
        merged.add(
          ConversationInfo(
            id: c.id,
            agentId: c.agentId ?? '',
            agentName: c.agentName ?? c.agentId ?? 'Agent',
            lastMessage: old?.lastMessage,
            lastMessageTime: old?.lastMessageTime,
          ),
        );
      }
      for (final c in state.entries) {
        if (!merged.any((m) => m.id == c.id)) {
          merged.add(c);
        }
      }

      state = state.copyWith(
        entries: merged..sort(_newestFirst),
        status: ConversationListStatus.ready,
      );
    } catch (e) {
      debugPrint('[Conversations] history populate failed: $e');
      _populated = false; // allow a retry on the next connection
      _setStatus(
        ConversationListStatus.error,
        error: _describeFetchError(e),
      );
    } finally {
      _loading = false;
    }
  }

  /// Ask for the history again after a failure.
  ///
  /// A failed fetch clears `_populated` so the next connection would retry
  /// on its own, but a link that never reconnects leaves the sidebar stuck
  /// on the failure with nothing to trigger it. This is that trigger.
  Future<void> retry() async {
    if (_loading) return;
    _populated = false;
    await _populateFromHistory();
  }

  /// Publish a status change through this notifier's own state.
  ///
  /// Deliberately not a second provider: Riverpod forbids one provider
  /// notifying another from inside its initialization, and this runs while
  /// the constructor is still going. Keeping both halves in one state also
  /// means a status change *cannot* fail to rebuild the widget — which is
  /// how the spinner outlived its request in the first place.
  void _setStatus(ConversationListStatus status, {String? error}) {
    if (!mounted) return;
    state = state.copyWith(status: status, error: error);
  }

  /// The fetch crosses an unreliable link, so the common failure is a
  /// timeout rather than anything the reader can act on. Say that, and
  /// say it can be tried again.
  String _describeFetchError(Object error) {
    final text = error.toString();
    // Raised by the SDK when history is asked for before credentials
    // exist — i.e. the socket never got far enough to register.
    if (text.contains('before connect')) return '还没连接上';
    if (text.contains('Timeout') || text.contains('timed out')) {
      return '加载超时';
    }
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return '网络连不上';
    }
    return '加载失败';
  }

  int _newestFirst(ConversationInfo a, ConversationInfo b) {
    final at = a.lastMessageTime;
    final bt = b.lastMessageTime;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  void selectConversation(String id) {
    _ref.read(activeConversationIdProvider.notifier).state = id;
  }

  /// Rename an agent, updating every conversation it appears in.
  ///
  /// The rename is agent-wide, so it is applied to the whole list rather
  /// than the one tile it was triggered from.
  Future<bool> renameAgent(String agentId, String name) async {
    final client = _ref.read(openHumanClientProvider);
    final ok = await client.renameAgent(agentId, name);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: [
        for (final c in state.entries)
          if (c.agentId == agentId)
            ConversationInfo(
              id: c.id,
              agentId: c.agentId,
              agentName: name,
              lastMessage: c.lastMessage,
              lastMessageTime: c.lastMessageTime,
            )
          else
            c,
      ],
    );
    _ref.invalidate(agentNamesProvider);
    return true;
  }

  /// Put a conversation back into the list, newest first.
  void add(ConversationInfo conversation) {
    if (state.entries.any((c) => c.id == conversation.id)) return;
    state = state.copyWith(entries: [conversation, ...state.entries]);
  }

  /// Move a conversation to the trash and drop it from the list.
  Future<bool> trash(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);
    final ok = await client.deleteConversation(conversationId);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: state.entries.where((c) => c.id != conversationId).toList(),
    );
    _ref.invalidate(trashListProvider);
    return true;
  }

  @override
  void dispose() {
    _msgSub.cancel();
    _connSub.cancel();
    super.dispose();
  }
}

/// Where the conversation list stands.
///
/// A failure is a first-class state rather than an internal flag: the
/// previous flag was cleared without touching anything the sidebar
/// watches, so the list never rebuilt and the spinner stayed on screen
/// long after the request had given up.
///
/// [idle] is deliberately distinct from [loading]. History is only
/// fetched once the socket connects, and on a link that cannot complete a
/// handshake the fetch never starts — calling that "loading" is exactly
/// how a sidebar ends up spinning forever.
enum ConversationListStatus { idle, loading, ready, error }

/// What the sidebar needs to know: the rows, and how they got there.
///
/// Entries and status live in one object so that changing either one
/// rebuilds the widget. When the status was a separate flag, a failed
/// fetch cleared it without replacing any object the sidebar watched —
/// so the screen kept showing "loading" long after the request had
/// already given up.
class ConversationListState {
  const ConversationListState({
    this.entries = const [],
    this.status = ConversationListStatus.idle,
    this.error,
  });

  final List<ConversationInfo> entries;
  final ConversationListStatus status;

  /// Reader-facing wording for a failure, already narrowed to something
  /// actionable. Null unless [status] is [ConversationListStatus.error].
  final String? error;

  ConversationListState copyWith({
    List<ConversationInfo>? entries,
    ConversationListStatus? status,
    String? error,
  }) {
    return ConversationListState(
      entries: entries ?? this.entries,
      status: status ?? this.status,
      // Only carried forward while still failing, so a successful or
      // newly started fetch does not keep showing a stale reason.
      error: status == ConversationListStatus.error ? error : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Trash — discarded but restorable conversations
// ═══════════════════════════════════════════════════════════════

/// Kept separate from the live list so the sidebar never has to filter:
/// opening the trash is the only thing that populates this.
final trashListProvider =
    StateNotifierProvider<TrashListNotifier, TrashListState>((ref) {
  return TrashListNotifier(ref);
});

/// Same shape as [ConversationListState], same reason: a load that fails
/// must replace something the sheet watches, or "empty" is all it can say.
///
/// This one mattered more — a failed load previously read as an empty
/// trash, which invites the reader to conclude their conversations were
/// deleted for good.
class TrashListState {
  const TrashListState({
    this.entries = const [],
    this.status = ConversationListStatus.idle,
    this.error,
  });

  final List<ConversationInfo> entries;
  final ConversationListStatus status;
  final String? error;

  TrashListState copyWith({
    List<ConversationInfo>? entries,
    ConversationListStatus? status,
    String? error,
  }) {
    return TrashListState(
      entries: entries ?? this.entries,
      status: status ?? this.status,
      error: status == ConversationListStatus.error ? error : null,
    );
  }
}

class TrashListNotifier extends StateNotifier<TrashListState> {
  TrashListNotifier(this._ref) : super(const TrashListState());

  final Ref _ref;

  Future<void> refresh() async {
    state = state.copyWith(status: ConversationListStatus.loading);
    try {
      final client = _ref.read(openHumanClientProvider);
      final trashed = await client.fetchTrash();
      if (!mounted) return;
      state = state.copyWith(
        entries: [
          for (final c in trashed)
            ConversationInfo(
              id: c.id,
              agentId: c.agentId ?? '',
              agentName: c.agentName ?? c.agentId ?? 'Agent',
            ),
        ],
        status: ConversationListStatus.ready,
      );
    } catch (e) {
      debugPrint('[Trash] load failed: $e');
      state = state.copyWith(
        status: ConversationListStatus.error,
        error: '加载失败',
      );
    }
  }

  /// Load on first open only; the trash is not something that changes
  /// on its own, so repeated openings need not refetch. A failure is not
  /// cached, so reopening after a drop retries.
  Future<void> loadIfNeeded() async {
    if (state.status == ConversationListStatus.ready) return;
    await refresh();
  }

  Future<bool> restore(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);
    final item = state.entries
        .where((c) => c.id == conversationId)
        .firstOrNull;
    final ok = await client.restoreConversation(conversationId);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: state.entries
          .where((c) => c.id != conversationId)
          .toList(),
    );
    // Put it straight back into the main list rather than refetching:
    // the entry is already to hand, and a refetch is another round trip
    // on a link where those are expensive.
    if (item != null) {
      _ref.read(conversationListProvider.notifier).add(item);
    }
    return true;
  }

  Future<bool> destroy(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);
    final ok = await client.deleteConversationPermanently(conversationId);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: state.entries
          .where((c) => c.id != conversationId)
          .toList(),
    );
    return true;
  }
}

/// Agent display names keyed by id, for whatever needs to look one up.
final agentNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final client = ref.watch(openHumanClientProvider);
  final conversations = await client.fetchConversations();
  return {
    for (final c in conversations)
      if (c.agentId != null) c.agentId!: c.agentName ?? c.agentId!,
  };
});
