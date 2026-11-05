// ═════════════════════════════════════════════════════════════════
// Flutter Widget Test: ChatScreen
//
// Tests:
//   - Renders AppBar with human display name
//   - Renders Flyer Chat widget (message list + input)
//   - Displays incoming messages via ChatController
//   - onSendPressed calls client.sendReply
// ═════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/room_composer.dart';
import 'package:openhuman_client/features/chat/stream/message_stream.dart';
import 'package:openhuman_client/features/chat/stream/task_card.dart';

/// A fake OpenHumanClient that allows injecting events.
class _FakeClient extends oh.OpenHumanClient {
  final _messagesController =
      StreamController<oh.MessageReceivedData>.broadcast();
  final _replyAcksController =
      StreamController<oh.ReplyDeliveredData>.broadcast();
  final _rawEventsController = StreamController<oh.OpenHumanEvent>.broadcast();
  final _capabilityUpdatesController =
      StreamController<oh.CapabilityUpdatedData>.broadcast();

  String? sentConversationId;
  String? sentText;

  /// Fail this many sends before letting them through.
  int failSends = 0;
  int sends = 0;

  @override
  oh.HumanSession? get currentHuman => const oh.HumanSession(
        id: 'hum_demo_alice',
        displayName: 'Alice Chen',
      );

  @override
  Stream<oh.MessageReceivedData> get messages => _messagesController.stream;

  @override
  Stream<oh.ReplyDeliveredData> get replyAcks => _replyAcksController.stream;

  @override
  Stream<oh.OpenHumanEvent> get rawEvents => _rawEventsController.stream;

  @override
  Stream<oh.CapabilityUpdatedData> get capabilityUpdates =>
      _capabilityUpdatesController.stream;

  @override
  oh.ConnectionState get currentState => oh.ConnectionState.connected;

  @override
  Stream<oh.ConnectionState> get connectionState =>
      Stream.value(oh.ConnectionState.connected);

  @override
  List<String> get activeConversations => ['cnv_demo_001'];

  @override
  Future<void> sendReply(String conversationId, String text,
      {String? invocationId}) async {
    sends++;
    if (failSends > 0) {
      failSends--;
      throw StateError('not connected');
    }
    sentConversationId = conversationId;
    sentText = text;
  }

  void injectMessage(oh.MessageReceivedData data) {
    _messagesController.add(data);
  }

  /// A message with its request shape, the way the server sends both.
  void injectWithRequest(
    oh.MessageReceivedData data,
    Map<String, dynamic> request,
  ) {
    _rawEventsController.add(oh.OpenHumanEvent(
      eventId: 'evt_${data.messageId}',
      eventType: 'message.received',
      conversationId: data.conversationId,
      timestamp: DateTime.now(),
      data: {'message_id': data.messageId, 'request': request},
    ));
    _messagesController.add(data);
  }

  final ended = <String>[];

  @override
  Future<void> endTurn(String conversationId) async =>
      ended.add(conversationId);

  @override
  void dispose() {
    _messagesController.close();
    _replyAcksController.close();
    _rawEventsController.close();
    _capabilityUpdatesController.close();
  }
}

void main() {
  late _FakeClient fakeClient;
  late ProviderContainer container;

  setUp(() {
    fakeClient = _FakeClient();
    container = ProviderContainer(
      overrides: [
        openHumanClientProvider.overrideWithValue(fakeClient),
        currentHumanProvider.overrideWith((ref) => const oh.HumanSession(
              id: 'hum_demo_alice',
              displayName: 'Alice Chen',
            )),
        connectionStateProvider.overrideWith((ref) => Stream.value(
              oh.ConnectionState.connected,
            )),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    fakeClient.dispose();
  });

  Future<void> pumpChatScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  group('ChatScreen UI', () {
    testWidgets('renders AppBar with human display name', (tester) async {
      await pumpChatScreen(tester);
      expect(find.text('Alice Chen'), findsOneWidget);
    });

    testWidgets('renders connection state indicator', (tester) async {
      await pumpChatScreen(tester);
      expect(find.textContaining('已连接'), findsWidgets);
    });

    testWidgets('renders chat input field', (tester) async {
      await pumpChatScreen(tester);
      expect(find.byType(EditableText), findsWidgets);
    });
  });

  group('ChatScreen message display', () {
    testWidgets('displays incoming agent message', (tester) async {
      await pumpChatScreen(tester);

      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_001',
        senderId: 'agt_demo_codex',
        senderType: 'agent',
        senderName: 'Codex',
        text: 'Hello human! Can you review my PR?',
      ));

      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('Hello human! Can you review my PR?'), findsOneWidget);
    });

    testWidgets('displays multiple messages in order', (tester) async {
      await pumpChatScreen(tester);

      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_001',
        senderId: 'agt_demo_codex',
        senderType: 'agent',
        senderName: 'Codex',
        text: 'First message',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_002',
        senderId: 'agt_demo_codex',
        senderType: 'agent',
        senderName: 'Codex',
        text: 'Second message',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
    });
  });

  group('ChatScreen send message', () {
    testWidgets('onSendPressed calls client.sendReply', (tester) async {
      await pumpChatScreen(tester);

      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_001',
        senderId: 'agt_demo_codex',
        senderType: 'agent',
        senderName: 'Codex',
        text: 'Review my PR',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      // Type a message into the chat input.
      final input = find.byType(EditableText);
      expect(input, findsWidgets);
      await tester.enterText(input.first, 'Looks good!');

      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(fakeClient.sentText, 'Looks good!');
      // The reply goes to the conversation the request came from.
      expect(fakeClient.sentConversationId, 'cnv_test');
    });
  });

  group('ChatScreen peer layout', () {
    testWidgets('the other person leads with their name, not the tool',
        (tester) async {
      await pumpChatScreen(tester);
      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_lin',
        messageId: 'msg_lin_1',
        senderId: 'agt_lin',
        senderType: 'agent',
        senderName: '林晓的 Claude Code · a3f9',
        text: '周末有空吗？',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      // Name in the header and on the run.
      expect(find.text('林晓'), findsWidgets);
      expect(find.text('经由 Claude Code'), findsWidgets);
      expect(find.text('a3f9'), findsOneWidget);
      expect(find.text('林晓的 Claude Code · a3f9'), findsNothing);
      for (final part in [MessageStream, Composer]) {
        expect(
          find.descendant(
            of: find.byType(part),
            matching: find.textContaining('AI'),
          ),
          findsNothing,
        );
      }
      // It is my move.
      expect(find.text('对方在等你回复'), findsOneWidget);
    });

    testWidgets('an API request shows as a task card', (tester) async {
      await pumpChatScreen(tester);
      fakeClient.injectWithRequest(
        const oh.MessageReceivedData(
          conversationId: 'cnv_task',
          messageId: 'msg_task_1',
          senderId: 'agt_mia',
          senderType: 'agent',
          senderName: 'Mia Chen (WorkBuddy)',
          text: '帮我画一张海边日落，暖色调。',
        ),
        {
          'kind': 'api',
          'api': 'images.generations',
          'expected_format': '1 png image(s), 1024x1024',
          'wants_files': true,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'timeout_secs': 900,
        },
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TaskCard), findsOneWidget);
      expect(find.textContaining('请你生成一张图片'), findsWidgets);
    });

    testWidgets('a failed send says why and retries', (tester) async {
      await pumpChatScreen(tester);
      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_001',
        senderId: 'agt_zhou',
        senderType: 'agent',
        senderName: '周子航 via Cursor',
        text: '那个 PR 你看了吗',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      fakeClient.failSends = 1;
      await tester.enterText(find.byType(EditableText).first, '看了，晚点回你');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('没连上，没发出去'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-retry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('message-retry')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(fakeClient.sends, 2);
      expect(fakeClient.sentText, '看了，晚点回你');
      expect(find.byKey(const ValueKey('message-retry')), findsNothing);
      expect(find.textContaining('已发出'), findsOneWidget);
    });

    testWidgets('Ctrl+Enter ends the turn and the composer can reopen',
        (tester) async {
      await pumpChatScreen(tester);
      fakeClient.injectMessage(const oh.MessageReceivedData(
        conversationId: 'cnv_test',
        messageId: 'msg_001',
        senderId: 'agt_zhou',
        senderType: 'agent',
        senderName: '周子航 via Cursor',
        text: '好的，那就这样',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.byType(EditableText).first);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(fakeClient.ended, ['cnv_test']);
      expect(find.byKey(const ValueKey('composer-ended')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-reopen')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('composer-ended')), findsNothing);
    });
  });
}
