// Visual check of the console at desktop size, with real fonts.
//
// Not a golden gate (fonts render differently per OS); run on demand:
//   OH_SHOT=1 flutter test test/visual --update-goldens
// and look at test/visual/shots/*.png.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

class _Fake extends oh.OpenHumanClient {
  final msgs = StreamController<oh.MessageReceivedData>.broadcast();
  @override
  oh.HumanSession? get currentHuman =>
      const oh.HumanSession(id: 'hum_me', displayName: '黄治文');
  @override
  Stream<oh.MessageReceivedData> get messages => msgs.stream;
  @override
  Stream<oh.ReplyDeliveredData> get replyAcks => const Stream.empty();
  @override
  Stream<oh.OpenHumanEvent> get rawEvents => const Stream.empty();
  @override
  Stream<oh.CapabilityUpdatedData> get capabilityUpdates =>
      const Stream.empty();
  @override
  oh.ConnectionState get currentState => oh.ConnectionState.connected;
  @override
  Stream<oh.ConnectionState> get connectionState =>
      Stream.value(oh.ConnectionState.connected);
  @override
  List<String> get activeConversations => ['cnv_1'];
  @override
  Future<void> sendReply(String c, String t, {String? invocationId}) async {}
}

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(rootBundle.load(f));
  }
  await l.load();
}

void main() {
  final enabled = Platform.environment['OH_SHOT'] == '1';

  testWidgets('console shot', (tester) async {
    await _font('Manrope', [
      for (final w in [400, 500, 600, 700]) 'assets/fonts/Manrope-$w.ttf',
    ]);
    await _font('GeistMono', [
      'assets/fonts/GeistMono-400.ttf',
      'assets/fonts/GeistMono-500.ttf',
    ]);
    await _font('NotoSansSC', [
      'assets/fonts/NotoSansSC-400.ttf',
      'assets/fonts/NotoSansSC-700.ttf',
    ]);
    await _font('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);

    tester.view.physicalSize = const Size(3200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final fake = _Fake();
    final container = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(fake),
      currentHumanProvider.overrideWith(
          (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文')),
      connectionStateProvider
          .overrideWith((ref) => Stream.value(oh.ConnectionState.connected)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: const ChatScreen(),
      ),
    ));
    await tester.pump();

    void say(String id, String who, String sid, String text) {
      fake.msgs.add(oh.MessageReceivedData(
        conversationId: 'cnv_1',
        messageId: id,
        senderId: sid,
        senderType: sid == 'hum_me' ? 'human' : 'agent',
        senderName: who,
        text: text,
      ));
    }

    // Sample content for the shot only.
    say(
        'm1',
        'Claude Code · a3f9',
        'agt_cc',
        '我在改 `server/src/api/task.rs`，准备把 API 任务的超时从 900 秒改成可配置。'
            '下面是改动，你看行不行：\n\n```diff\n'
            '-const TASK_TIMEOUT: u64 = 900;\n'
            '+fn task_timeout() -> u64 {\n'
            '+    env_u64("OMNI2API_TASK_TIMEOUT").unwrap_or(900)\n'
            '+}\n```\n\n'
            '另外有两个问题：\n1. 环境变量名用这个可以吗？\n'
            '2. 要不要顺便写进 **docs/server-env.md**？');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(EditableText).first, '可以。文档要写，默认值也写上。');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    say(
        'm3',
        'Claude Code · a3f9',
        'agt_cc',
        '好。文档已补，`cargo clippy -- -D warnings` 通过。'
            '最后确认一下：超时之后，任务状态返回 `expired` 还是 `failed`？');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat.png'),
      );
    }
  }, skip: !enabled);
}
