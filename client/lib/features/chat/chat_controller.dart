/// Chat controller — one timeline per conversation, and everything I
/// send into it.
///
/// Only `message.received` creates timeline entries: those are what
/// people wrote. System events (`session.connected`, `capability.updated`,
/// `reply.delivered`, `error`) never become messages; they update state
/// shown elsewhere.
///
/// The visible [state] is the ACTIVE conversation's timeline, newest
/// first. Other conversations fill silently in their own buckets.
///
/// What I send:
///
/// * **Replies** go over the socket (`reply.send`). They show as
///   "发送中" until the send completes, "已发出" after, and "已送达" once
///   the server confirms the waiting tool got them (`reply.delivered`).
///   A send that fails stays in the timeline marked as failed, with a
///   retry, instead of silently disappearing.
/// * **Task answers** (a picture, a recording, a verdict…) go through
///   `POST /v1/seat/reply`, which takes the files and checks the answer
///   against the task the way the endpoint will; a refusal comes back
///   with its reason.
/// * **Ending the turn** (`end.turn`) tells the other person's tool that
///   I am done for now, so their window stops waiting.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../core/sdk_provider.dart';
import '../../core/tasks.dart';
import 'message_adapter.dart';

/// Where a task stands, beyond what its card can work out from the clock.
class TaskOutcome {
  const TaskOutcome(this.state, {this.note});
  final TaskState state;

  /// The server's reason for a refusal, or what happened.
  final String? note;
}

/// Outcomes by the id of the message that carried the task.
final taskOutcomesProvider =
    StateProvider<Map<String, TaskOutcome>>((ref) => const {});

/// Conversations where I said I was done (`end.turn`). A new message
/// from the other side clears the mark.
final turnEndedProvider = StateProvider<Set<String>>((ref) => const {});

class ChatController extends StateNotifier<List<types.Message>> {
  ChatController(this._ref) : super(const []) {
    _init();
  }

  final Ref _ref;

  StreamSubscription<oh.MessageReceivedData>? _messageSub;
  StreamSubscription<oh.OpenHumanEvent>? _rawEventSub;
  StreamSubscription<oh.ReplyDeliveredData>? _replyAckSub;
  StreamSubscription<oh.ConnectionState>? _connSub;
  StreamSubscription<oh.AsyncInvocationCreatedData>? _asyncSub;
  ProviderSubscription<String?>? _activeConvSub;

  bool _historyLoaded = false;

  types.User _humanUser = const types.User(id: 'unknown');
  types.User get humanUser => _humanUser;

  /// Messages by conversation, newest first.
  final Map<String, List<types.Message>> _byConversation = {};

  /// Request shapes seen on raw events, by message id. The raw event is
  /// dispatched before the typed one, so the typed handler finds it here.
  final Map<String, Map<String, dynamic>> _requests = {};

  /// A non-streaming request that went async leaves an invocation id; the
  /// reply must carry it to reach the parked caller.
  final Map<String, String> _invocations = {};

  void _init() {
    final client = _ref.read(openHumanClientProvider);
    final me = client.currentHuman ?? _ref.read(currentHumanProvider);
    if (me != null) _humanUser = humanSessionToUser(me);

    _messageSub = client.messages.listen(_onMessageReceived);
    _rawEventSub = client.rawEvents.listen(_onRawEvent);
    _replyAckSub = client.replyAcks.listen(_onReplyDelivered);
    _asyncSub = client.asyncInvocations.listen(
      (a) => _invocations[a.conversationId] = a.invocationId,
    );

    _activeConvSub = _ref.listen<String?>(
      activeConversationIdProvider,
      (prev, next) {
        if (next != null && next != prev) {
          final bucket = _byConversation[next];
          state = bucket != null
              ? List<types.Message>.unmodifiable(bucket)
              : const [];
          if (bucket == null || bucket.isEmpty) {
            unawaited(_loadMessages(next));
          }
        }
      },
    );

    _connSub = client.connectionState.listen((connState) {
      if (connState == oh.ConnectionState.connected) {
        unawaited(_loadHistory());
      } else if (connState == oh.ConnectionState.reconnecting ||
          connState == oh.ConnectionState.disconnected ||
          connState == oh.ConnectionState.error) {
        // Refetch on the next connection, so what arrived while offline
        // is not missed.
        _historyLoaded = false;
      }
    });

    if (client.currentState == oh.ConnectionState.connected) {
      unawaited(_loadHistory());
    }
  }

  Future<void> _loadHistory() async {
    final client = _ref.read(openHumanClientProvider);
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      // One request for the list; messages are fetched when a
      // conversation is opened, so a slow link is not flooded.
      final conversations = await client.fetchConversations();
      if (conversations.isEmpty) return;
      conversations.sort((a, b) => b.sortKey.compareTo(a.sortKey));
      for (final conversation in conversations) {
        _byConversation.putIfAbsent(conversation.id, () => []);
      }
      final active = _ref.read(activeConversationIdProvider);
      final first = active ?? conversations.first.id;
      if (active == null) {
        _ref.read(activeConversationIdProvider.notifier).state = first;
      }
      await _loadMessages(first);
    } catch (e, st) {
      debugPrint('[Chat] history load failed: $e\n$st');
      _historyLoaded = false;
    }
  }

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
      _publish(conversationId);
      // The open conversation and its row must agree on whose turn it is.
      if (messages.isNotEmpty) {
        _ref.read(conversationListProvider.notifier).applyLastMessage(
              conversationId,
              messages.last,
              me: _ref.read(currentHumanProvider)?.id ??
                  client.currentHuman?.id,
            );
      }
    } catch (e, st) {
      debugPrint('[Chat] failed to load $conversationId: $e\n$st');
    }
  }

  void _publish(String conversationId) {
    if (_ref.read(activeConversationIdProvider) == conversationId) {
      state = List<types.Message>.unmodifiable(
        _byConversation[conversationId] ?? const [],
      );
    }
  }

  void _onRawEvent(oh.OpenHumanEvent event) {
    switch (event.eventType) {
      case 'session.connected':
        final human = _ref.read(openHumanClientProvider).currentHuman;
        if (human != null) {
          _humanUser = humanSessionToUser(human);
          _ref.read(currentHumanProvider.notifier).state = human;
        }
      case 'message.received':
        final r = event.data['request'];
        final id = event.data['message_id'];
        if (r is Map<String, dynamic> && id is String) _requests[id] = r;
    }
  }

  void _onMessageReceived(oh.MessageReceivedData data) {
    final messages = messageReceivedToMessages(
      data,
      eventTimestamp: DateTime.now(),
      humanUser: _humanUser,
      request: _requests.remove(data.messageId),
    );
    final bucket = _byConversation.putIfAbsent(data.conversationId, () => []);
    if (bucket.any((m) => m.id == data.messageId)) return;

    final mine = data.senderId == _humanUser.id;
    if (mine) {
      // The server echoes my own replies back: drop the local copy.
      bucket.removeWhere(
        (m) =>
            m.id.startsWith('outgoing_') &&
            m is types.TextMessage &&
            m.text == data.text,
      );
    } else {
      // They wrote again: the turn is open again.
      final ended = _ref.read(turnEndedProvider);
      if (ended.contains(data.conversationId)) {
        _ref.read(turnEndedProvider.notifier).state = {...ended}
          ..remove(data.conversationId);
      }
    }

    bucket.insertAll(0, messages.reversed);

    final active = _ref.read(activeConversationIdProvider);
    if (active == null) {
      _ref.read(activeConversationIdProvider.notifier).state =
          data.conversationId;
      state = List<types.Message>.unmodifiable(bucket);
      return;
    }
    _publish(data.conversationId);
  }

  /// `reply.delivered`: my newest "已发出" reply here reached them.
  void _onReplyDelivered(oh.ReplyDeliveredData data) {
    final conversationId = _ref.read(activeConversationIdProvider);
    final bucket =
        conversationId == null ? null : _byConversation[conversationId];
    if (bucket == null) return;
    for (var i = 0; i < bucket.length; i++) {
      final msg = bucket[i];
      if (msg.author.id == _humanUser.id && msg.status == types.Status.sent) {
        bucket[i] = msg.copyWith(status: types.Status.delivered);
        break;
      }
    }
    _publish(conversationId!);
  }

  String? _conversationForSend() {
    final client = _ref.read(openHumanClientProvider);
    return _ref.read(activeConversationIdProvider) ??
        (client.activeConversations.isNotEmpty
            ? client.activeConversations.first
            : null);
  }

  void _replace(String conversationId, String id,
      types.Message Function(types.Message) f) {
    final bucket = _byConversation[conversationId];
    if (bucket == null) return;
    final i = bucket.indexWhere((m) => m.id == id);
    if (i < 0) return;
    bucket[i] = f(bucket[i]);
    _publish(conversationId);
  }

  /// Send a reply. Returns false when there is nowhere to send it.
  bool sendReply(String text) {
    if (text.trim().isEmpty) return false;
    final conversationId = _conversationForSend();
    if (conversationId == null) return false;
    final tempId = 'outgoing_${DateTime.now().microsecondsSinceEpoch}';
    final bucket = _byConversation.putIfAbsent(conversationId, () => []);
    bucket.insert(
      0,
      buildOutgoingTextMessage(
        text: text,
        humanUser: _humanUser,
        messageId: tempId,
      ),
    );
    _publish(conversationId);
    _ref
        .read(conversationListProvider.notifier)
        .markAnswered(conversationId, text);
    _deliver(conversationId, tempId, text);
    return true;
  }

  void _deliver(String conversationId, String id, String text) {
    final client = _ref.read(openHumanClientProvider);
    final inv = _invocations.remove(conversationId);
    Future<void> send() async =>
        client.sendReply(conversationId, text, invocationId: inv);
    final list = _ref.read(conversationListProvider.notifier);
    send().then(
      (_) {
        _replace(
          conversationId,
          id,
          (m) => m.status == types.Status.delivered
              ? m
              : m.copyWith(status: types.Status.sent),
        );
        list.markSent(conversationId);
      },
      onError: (Object e) {
        debugPrint('[Chat] send failed: $e');
        if (inv != null) _invocations[conversationId] = inv;
        list.markFailed(conversationId);
        _replace(
          conversationId,
          id,
          (m) => m.copyWith(
            status: types.Status.error,
            metadata: {...?m.metadata, kFailure: _why(e)},
          ),
        );
      },
    );
  }

  String _why(Object e) {
    final t = e.toString();
    if (t.contains('not connected') || t.contains('StateError')) {
      return '未连接，无法发送';
    }
    return '未发送';
  }

  /// Send a failed reply again.
  void retry(String messageId) {
    final conversationId = _conversationForSend();
    if (conversationId == null) return;
    final bucket = _byConversation[conversationId];
    final m = bucket?.where((m) => m.id == messageId).firstOrNull;
    if (m is! types.TextMessage) return;
    _replace(
      conversationId,
      messageId,
      (m) => m.copyWith(
        status: types.Status.sending,
        metadata: {...?m.metadata}..remove(kFailure),
      ),
    );
    _deliver(conversationId, messageId, m.text);
  }

  /// Tell the other person's tool I am done for now (`end.turn`).
  bool endTurn() {
    final conversationId = _conversationForSend();
    if (conversationId == null) return false;
    try {
      _ref.read(openHumanClientProvider).endTurn(conversationId);
    } catch (e) {
      debugPrint('[Chat] end.turn failed: $e');
      return false;
    }
    _ref.read(turnEndedProvider.notifier).state = {
      ..._ref.read(turnEndedProvider),
      conversationId,
    };
    return true;
  }

  /// Undo [endTurn] locally (keep replying into the same turn).
  void reopenTurn() {
    final conversationId = _conversationForSend();
    if (conversationId == null) return;
    _ref.read(turnEndedProvider.notifier).state = {
      ..._ref.read(turnEndedProvider),
    }..remove(conversationId);
  }

  void _setOutcome(String taskMessageId, TaskOutcome o) {
    _ref.read(taskOutcomesProvider.notifier).state = {
      ..._ref.read(taskOutcomesProvider),
      taskMessageId: o,
    };
  }

  /// Answer the task carried by [taskMessageId]: [text] and [files], or
  /// a decline (text only, which the task contract reads as a refusal).
  ///
  /// The answer is checked here first (see `checkAnswer`), then by the
  /// server; either refusal keeps the task open with the reason.
  Future<TaskOutcome> answerTask({
    required String taskMessageId,
    required ApiTask task,
    String text = '',
    List<OutgoingFile> files = const [],
    bool decline = false,
  }) async {
    final conversationId = _conversationForSend();
    if (conversationId == null) {
      return const TaskOutcome(TaskState.failed, note: '未选择对话');
    }
    if (!decline) {
      final check = checkAnswer(task, text, [for (final f in files) f.draft]);
      if (!check.ok) {
        return TaskOutcome(TaskState.open, note: check.error);
      }
    }
    final body = decline && text.trim().isEmpty ? '无法完成此请求。' : text.trim();
    _setOutcome(taskMessageId, const TaskOutcome(TaskState.sending));

    // Show my answer at once, the way it will read to them.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final bucket = _byConversation.putIfAbsent(conversationId, () => []);
    final ids = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final mime = f.mime ?? mimeForName(f.name);
      final uri = 'data:$mime;base64,${base64Encode(f.bytes)}';
      final id = 'outgoing_${stamp}_f$i';
      ids.add(id);
      final meta = {kAnswerOf: taskMessageId};
      bucket.insert(
        0,
        mediaOf(mime: mime, name: f.name) == AnswerMedia.image
            ? types.ImageMessage(
                author: _humanUser,
                createdAt: now,
                id: id,
                uri: uri,
                name: f.name,
                size: f.bytes.length,
                status: types.Status.sending,
                metadata: meta,
              )
            : types.FileMessage(
                author: _humanUser,
                createdAt: now,
                id: id,
                uri: uri,
                name: f.name,
                mimeType: mime,
                size: f.bytes.length,
                status: types.Status.sending,
                metadata: meta,
              ),
      );
    }
    if (body.isNotEmpty) {
      final id = 'outgoing_${stamp}_t';
      ids.add(id);
      bucket.insert(
        0,
        buildOutgoingTextMessage(
          text: body,
          humanUser: _humanUser,
          messageId: id,
          answerOf: taskMessageId,
        ),
      );
    }
    _publish(conversationId);

    void mark(types.Status s, [String? why]) {
      for (final id in ids) {
        _replace(
          conversationId,
          id,
          (m) => m.copyWith(
            status: s,
            metadata: {
              ...?m.metadata,
              if (why != null) kFailure: why,
            },
          ),
        );
      }
    }

    try {
      final r = await _ref.read(openHumanClientProvider).answer(
            conversationId,
            text: body,
            attachments: [
              for (final f in files)
                oh.ReplyAttachment(
                  name: f.name,
                  bytes: f.bytes,
                  mime: f.mime ?? mimeForName(f.name),
                ),
            ],
            invocationId: _invocations.remove(conversationId),
          );
      final TaskOutcome out;
      if (!r.ok) {
        // Refused: take my answer back out, keep the task open.
        bucket.removeWhere((m) => ids.contains(m.id));
        _publish(conversationId);
        out = TaskOutcome(
          TaskState.open,
          note: r.errorCode == 'bad_answer'
              ? '服务器拒绝：${r.errorMessage ?? '格式不对'}'
              : (r.errorMessage ?? '未发送'),
        );
      } else if (r.abandoned) {
        mark(types.Status.error, '对方已离开，未送达');
        out = const TaskOutcome(
          TaskState.expired,
          note: '对方已离开，回答未送达。',
        );
      } else {
        mark(types.Status.delivered);
        out = TaskOutcome(decline ? TaskState.declined : TaskState.answered);
        _ref
            .read(conversationListProvider.notifier)
            .markAnswered(conversationId, body.isEmpty ? '[文件]' : body);
      }
      _setOutcome(taskMessageId, out);
      return out;
    } catch (e) {
      debugPrint('[Chat] task answer failed: $e');
      bucket.removeWhere((m) => ids.contains(m.id));
      _publish(conversationId);
      final out = TaskOutcome(TaskState.open, note: '未发送：${_short(e)}');
      _setOutcome(taskMessageId, out);
      return out;
    }
  }

  String _short(Object e) {
    final t = e.toString();
    if (t.contains('before connect')) return '未连接服务器';
    if (t.contains('SocketException') || t.contains('Connection')) {
      return '无法连接网络';
    }
    if (t.contains('Timeout')) return '超时';
    return '出现错误';
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _rawEventSub?.cancel();
    _replyAckSub?.cancel();
    _connSub?.cancel();
    _asyncSub?.cancel();
    _activeConvSub?.close();
    super.dispose();
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, List<types.Message>>((ref) {
  return ChatController(ref);
});
