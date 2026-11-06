/// Riverpod providers for the OpenHuman SDK.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'identity.dart';
import 'tasks.dart';

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
    StateNotifierProvider<CapabilityCacheNotifier, oh.CapabilityUpdatedData?>(
        (ref) {
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
    this.isGroup = false,
    this.title,
    this.memberCount,
    this.unread = 0,
    this.waiting = false,
    this.task,
    this.origin,
    this.lastFromMe = false,
    this.lastFailed = false,
  });

  final String id;
  final String agentId;

  /// The name the server knows the caller by — whatever their key or
  /// seat was called ("林晓的 Claude Code", "Codex"). [caller] splits it
  /// into the person and the tool.
  final String agentName;
  String? lastMessage;
  DateTime? lastMessageTime;

  /// Group room marker (§10.3).
  final bool isGroup;

  /// Room title (groups only).
  final String? title;

  /// Participant count (groups only).
  final int? memberCount;

  /// Messages that arrived while this conversation was not open.
  int unread;

  /// The newest message is theirs and nobody has answered it yet.
  bool waiting;

  /// When the conversation carries an API task: what was asked for.
  ApiTask? task;

  /// The stateful API a conversation was opened for (assistants, agents,
  /// chatkit, evals), from the request's `origin`.
  String? origin;

  /// The newest message is mine.
  bool lastFromMe;

  /// My newest message never left: the row says so instead of "你：…".
  bool lastFailed;

  /// Who is on the other end.
  Caller get caller => Caller.parse(agentName);

  /// What the list and the header call this conversation.
  String get displayName => isGroup ? (title ?? agentName) : caller.name;

  ConversationInfo copyWith({
    String? agentName,
    String? title,
    int? memberCount,
  }) =>
      ConversationInfo(
        id: id,
        agentId: agentId,
        agentName: agentName ?? this.agentName,
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        isGroup: isGroup,
        title: title ?? this.title,
        memberCount: memberCount ?? this.memberCount,
        unread: unread,
        waiting: waiting,
        task: task,
        origin: origin,
        lastFromMe: lastFromMe,
        lastFailed: lastFailed,
      );
}

/// What a conversation's origin is called.
String? originLabel(String? origin) => switch (origin) {
      'assistants' => 'Assistants 线程',
      'agents' => 'Agents 会话',
      'chatkit' => '来自 ChatKit',
      'evals' => '评测',
      _ => null,
    };

/// Detail of one group room (members, roles, settings metadata), fetched
/// on demand when a group conversation is open. `null` when the id is not
/// a room or the fetch failed — the UI degrades to the plain chat then.
final roomInfoProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, roomId) async {
  final info = ref
      .watch(conversationListProvider)
      .entries
      .where((c) => c.id == roomId)
      .firstOrNull;
  if (info == null || !info.isGroup) return null;
  try {
    final client = ref.read(openHumanClientProvider);
    return await client.getRoom(roomId);
  } catch (_) {
    return null;
  }
});

/// Whether the signed-in human owns this room (§10.6: owner-only controls
/// are guidance; the server enforces the rule regardless).
/// A room member's id. The server calls it `participant_id`; older
/// builds and fixtures said `human_id`.
String? memberId(Map<String, dynamic> m) =>
    (m['participant_id'] ?? m['human_id']) as String?;

final roomOwnershipProvider = Provider.family<bool, String>((ref, roomId) {
  final room = ref.watch(roomInfoProvider(roomId)).valueOrNull;
  if (room == null) return false;
  final me = ref.watch(currentHumanProvider)?.id;
  if (me == null) return false;
  final members = (room['members'] as List?) ?? const [];
  return members.whereType<Map<String, dynamic>>().any(
        (m) => memberId(m) == me && m['role'] == 'owner',
      );
});

final conversationListProvider =
    StateNotifierProvider<ConversationListNotifier, ConversationListState>(
        (ref) {
  return ConversationListNotifier(ref);
});

class ConversationListNotifier extends StateNotifier<ConversationListState> {
  ConversationListNotifier(this._ref) : super(const ConversationListState()) {
    final client = _ref.read(openHumanClientProvider);

    _msgSub = client.messages.listen((data) {
      final entries = state.entries;
      final me = _ref.read(currentHumanProvider)?.id ?? client.currentHuman?.id;
      final mine = data.senderId == me;
      final active = _ref.read(activeConversationIdProvider);
      final existing =
          entries.where((c) => c.id == data.conversationId).firstOrNull;
      final c = existing ??
          ConversationInfo(
            id: data.conversationId,
            agentId: data.senderId,
            agentName: data.senderName ?? data.senderId,
          );
      c.lastMessage = data.text;
      c.lastMessageTime = DateTime.now();
      c.lastFromMe = mine;
      c.lastFailed = false;
      c.waiting = !mine;
      if (!mine && data.conversationId != active) c.unread++;
      state = state.copyWith(
        entries: existing == null
            ? [c, ...entries]
            : ([...entries]..sort(_newestFirst)),
      );
    });

    // The request shape rides on the raw event: API tasks and where a
    // conversation came from.
    _rawSub = client.rawEvents.listen((e) {
      if (e.eventType == 'conversation.started') {
        // A new chat from someone: make sure the list knows it.
        if (!state.entries.any((c) => c.id == e.conversationId)) retry();
        return;
      }
      if (e.eventType.startsWith('room.member_')) {
        _ref.invalidate(roomInfoProvider(e.conversationId));
        return;
      }
      if (e.eventType != 'message.received') return;
      final r = e.data['request'];
      if (r is! Map<String, dynamic>) return;
      final hit =
          state.entries.where((c) => c.id == e.conversationId).firstOrNull;
      if (hit == null) return;
      hit.task = ApiTask.fromRequest(r, receivedAt: DateTime.now()) ?? hit.task;
      hit.origin = r['origin'] as String? ?? hit.origin;
      state = state.copyWith(entries: [...state.entries]);
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
  late final StreamSubscription _rawSub;
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
            agentName: c.agentName ?? c.agentId ?? '',
            lastMessage: old?.lastMessage,
            // History knows when the last message landed even before
            // this session has seen one, so the row can show a time.
            lastMessageTime: old?.lastMessageTime ?? c.lastMessageAt,
            isGroup: c.isGroup,
            title: c.title,
            memberCount: c.memberCount,
            unread: old?.unread ?? 0,
            waiting: old?.waiting ?? false,
            task: old?.task,
            origin: old?.origin,
            lastFromMe: old?.lastFromMe ?? false,
            lastFailed: old?.lastFailed ?? false,
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
      // Background: the list endpoint carries no preview, so without
      // this every row reads blank and nobody can tell who is waiting.
      unawaited(_fillPreviews());
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

  /// How many rows get their last message fetched up front.
  static const int _previewBudget = 40;

  /// Fetch the newest message of each row that has none yet, so the list
  /// shows what was said last and who is waiting on whom — the same rule
  /// the open conversation's header uses (the newest message is theirs).
  Future<void> _fillPreviews() async {
    final client = _ref.read(openHumanClientProvider);
    final me = _ref.read(currentHumanProvider)?.id ?? client.currentHuman?.id;
    final todo = state.entries
        .where((c) => c.lastMessage == null)
        .take(_previewBudget)
        .toList();
    // A few at a time: a long list must not open forty sockets at once.
    for (var i = 0; i < todo.length; i += 6) {
      final batch = todo.skip(i).take(6);
      await Future.wait(batch.map((c) async {
        try {
          final last = await client.fetchMessages(c.id, limit: 1);
          if (last.isEmpty || !mounted) return;
          applyLastMessage(c.id, last.last, me: me);
        } catch (_) {
          // A row without a preview is fine; the list must not fail.
        }
      }));
      if (!mounted) return;
    }
  }

  /// Bring a row up to date with a message from history: its preview,
  /// whose turn it is. Live messages that arrived since win.
  void applyLastMessage(String id, oh.HistoryMessage m, {String? me}) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null) return;
    final at = m.createdAt;
    if (c.lastMessage != null &&
        at != null &&
        c.lastMessageTime != null &&
        c.lastMessageTime!.isAfter(at.add(const Duration(seconds: 1)))) {
      return;
    }
    final mine = me != null ? m.senderId == me : m.senderType == 'human';
    c.lastMessage = m.text.isNotEmpty
        ? m.text
        : (m.images.isNotEmpty ? '[图片]' : c.lastMessage);
    c.lastFromMe = mine;
    c.lastFailed = false;
    c.waiting = !mine;
    if (at != null) c.lastMessageTime = at;
    state = state.copyWith(entries: [...state.entries]);
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
    if (text.contains('before connect')) return '未连接';
    if (text.contains('Timeout') || text.contains('timed out')) {
      return '连接超时';
    }
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return '无法连接网络';
    }
    return '无法加载';
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
    markRead(id);
  }

  /// Clear a conversation's unread count (it is open now).
  void markRead(String id) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null || c.unread == 0) return;
    c.unread = 0;
    state = state.copyWith(entries: [...state.entries]);
  }

  /// Record that I answered: nobody is waiting on me here any more.
  void markAnswered(String id, String text) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null) return;
    c.waiting = false;
    c.lastFromMe = true;
    c.lastFailed = false;
    c.lastMessage = text.isEmpty ? c.lastMessage : text;
    c.lastMessageTime = DateTime.now();
    state = state.copyWith(entries: [...state.entries]..sort(_newestFirst));
  }

  /// I ended the turn: the row stops asking for a reply. [ended] false
  /// undoes it, and the row asks again when their message is newest.
  void markTurnEnded(String id, {bool ended = true}) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null) return;
    c.waiting = ended ? false : (!c.lastFromMe || c.lastFailed);
    state = state.copyWith(entries: [...state.entries]);
  }

  /// My reply did not go out: they are still waiting, and the row shows
  /// the failure rather than the text as if it had been said.
  void markFailed(String id) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null || !c.lastFromMe) return;
    c.lastFailed = true;
    c.waiting = true;
    state = state.copyWith(entries: [...state.entries]);
  }

  /// A failed reply went out on retry.
  void markSent(String id) {
    final c = state.entries.where((c) => c.id == id).firstOrNull;
    if (c == null || !c.lastFailed) return;
    c.lastFailed = false;
    c.waiting = false;
    state = state.copyWith(entries: [...state.entries]);
  }

  /// How many people are waiting on me.
  int get waitingCount => state.entries.where((c) => c.waiting).length;

  /// Save a conversation's messages on the server (see
  /// `OpenHumanClient.saveConversation`).
  Future<bool> saveConversation(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);
    return client.saveConversation(conversationId);
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
          if (c.agentId == agentId) c.copyWith(agentName: name) else c,
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

  /// Move several conversations to the trash at once. Returns how many
  /// went; the ones the server refused stay in the list.
  Future<int> trashMany(Iterable<String> ids) async {
    final client = _ref.read(openHumanClientProvider);
    final list = ids.toList();
    final results = await Future.wait(
      list.map((id) => client.deleteConversation(id).catchError((_) => false)),
    );
    final gone = {
      for (var i = 0; i < list.length; i++)
        if (results[i]) list[i],
    };
    if (!mounted) return gone.length;
    if (gone.isNotEmpty) {
      state = state.copyWith(
        entries: state.entries.where((c) => !gone.contains(c.id)).toList(),
      );
      _ref.invalidate(trashListProvider);
    }
    return gone.length;
  }

  /// Undo a move to the trash: restore on the server, put the row back
  /// where it was.
  Future<bool> untrash(ConversationInfo conversation, {int? at}) async {
    final client = _ref.read(openHumanClientProvider);
    final ok = await client
        .restoreConversation(conversation.id)
        .catchError((_) => false);
    if (!ok || !mounted) return false;
    if (state.entries.any((c) => c.id == conversation.id)) return true;
    final entries = [...state.entries];
    entries.insert((at ?? 0).clamp(0, entries.length), conversation);
    state = state.copyWith(entries: entries);
    _ref.invalidate(trashListProvider);
    return true;
  }

  /// Clear the unread count on several rows.
  void markReadMany(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      for (final c in state.entries) {
        if (c.id == id && c.unread > 0) {
          c.unread = 0;
          changed = true;
        }
      }
    }
    if (changed) state = state.copyWith(entries: [...state.entries]);
  }

  @override
  void dispose() {
    _msgSub.cancel();
    _connSub.cancel();
    _rawSub.cancel();
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
              agentName: c.agentName ?? c.agentId ?? '',
            ),
        ],
        status: ConversationListStatus.ready,
      );
    } catch (e) {
      debugPrint('[Trash] load failed: $e');
      state = state.copyWith(
        status: ConversationListStatus.error,
        error: '无法加载',
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
    final item = state.entries.where((c) => c.id == conversationId).firstOrNull;
    final ok = await client.restoreConversation(conversationId);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: state.entries.where((c) => c.id != conversationId).toList(),
    );
    // Put it straight back into the main list rather than refetching:
    // the entry is already to hand, and a refetch is another round trip
    // on a link where those are expensive.
    if (item != null) {
      _ref.read(conversationListProvider.notifier).add(item);
    }
    return true;
  }

  /// Restore everything in the trash. Returns how many came back.
  Future<int> restoreAll() async {
    final items = [...state.entries];
    final client = _ref.read(openHumanClientProvider);
    final results = await Future.wait(
      items.map(
        (c) => client.restoreConversation(c.id).catchError((_) => false),
      ),
    );
    if (!mounted) return 0;
    final back = [
      for (var i = 0; i < items.length; i++)
        if (results[i]) items[i],
    ];
    final ids = {for (final c in back) c.id};
    state = state.copyWith(
      entries: state.entries.where((c) => !ids.contains(c.id)).toList(),
    );
    final list = _ref.read(conversationListProvider.notifier);
    for (final c in back.reversed) {
      list.add(c);
    }
    return back.length;
  }

  /// Empty the trash for good. Returns how many were destroyed.
  Future<int> destroyAll() async {
    final items = [...state.entries];
    final client = _ref.read(openHumanClientProvider);
    final results = await Future.wait(
      items.map(
        (c) =>
            client.deleteConversationPermanently(c.id).catchError((_) => false),
      ),
    );
    if (!mounted) return 0;
    final gone = {
      for (var i = 0; i < items.length; i++)
        if (results[i]) items[i].id,
    };
    state = state.copyWith(
      entries: state.entries.where((c) => !gone.contains(c.id)).toList(),
    );
    return gone.length;
  }

  Future<bool> destroy(String conversationId) async {
    final client = _ref.read(openHumanClientProvider);
    final ok = await client.deleteConversationPermanently(conversationId);
    if (!ok || !mounted) return false;

    state = state.copyWith(
      entries: state.entries.where((c) => c.id != conversationId).toList(),
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

// ═══════════════════════════════════════════════════════════════
//  Server notices — the `error` event, in words a person reads
// ═══════════════════════════════════════════════════════════════

/// What to tell the person when the server turns a step down. `null`
/// for codes that need no word from us (the step is retried, or another
/// part of the screen already shows it).
String? serverNotice(String code, String message) {
  switch (code) {
    case 'not_a_member':
      return '你已不在此群聊中';
    case 'owner_only':
      return '仅群主可执行此操作';
    case 'tool_not_found':
      return '对方没有此工具';
    case 'target_not_found':
      return '对方不在线';
    case 'target_required':
      return '请选择要调用的成员';
    case 'queued':
      return '将在对方下次发送消息时送达';
    case 'serialize_failed':
      return '服务器错误';
    default:
      return '操作未完成';
  }
}

/// Each `error` event the server sends, already in words.
final serverNoticeProvider = StreamProvider.autoDispose<String>((ref) {
  final client = ref.watch(openHumanClientProvider);
  return client.rawEvents
      .where((e) => e.eventType == 'error')
      .map((e) {
        final code = e.data['code'] as String? ?? '';
        final message = e.data['message'] as String? ?? '';
        return serverNotice(code, message);
      })
      .where((t) => t != null)
      .cast<String>();
});
