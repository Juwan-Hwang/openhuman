// Visual check of the console at desktop size, with real fonts.
//
// Not a golden gate (fonts render differently per OS); run on demand:
//   OH_SHOT=1 flutter test test/visual --update-goldens
// and look at test/visual/shots/*.png.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/auth/auth_screen.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/features/chat/room_composer.dart';
import 'package:openhuman_client/widgets/window_chrome.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

Future<void> _open(
  WidgetTester tester,
  ProviderContainer c,
  String id,
) async {
  c.read(activeConversationIdProvider.notifier).state = id;
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await settleImages(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  final enabled = Platform.environment['OH_SHOT'] == '1';

  testWidgets('console shot', (tester) async {
    await loadFonts();
    WindowChrome.enabled = true;
    addTearDown(() => WindowChrome.enabled = false);
    tester.view.physicalSize = const Size(3200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final fake = FakeClient();
    final container = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(fake),
      currentHumanProvider.overrideWith(
          (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文')),
      connectionStateProvider
          .overrideWith((ref) => Stream.value(oh.ConnectionState.connected)),
      serverConfigProvider.overrideWith(
        (ref) => const ServerConfig(
          serverUrl: 'wss://oh.example.com/ws',
          apiKey: 'ohk_live_7d2f9a41c0e84b6e',
        ),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: const WindowChrome(child: ChatScreen()),
      ),
    ));
    await tester.pump();
    await _open(tester, container, 'cnv_lin');

    // A reply that does not go out.
    fake.failNext = true;
    await tester.enterText(
      find.descendant(
        of: find.byType(Composer),
        matching: find.byType(EditableText),
      ),
      '定了，七点半在老地方，我先去占座。',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await settleImages(tester);

    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat.png'),
      );
    }

    // An open picture task.
    await _open(tester, container, 'cnv_mia');
    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat_task.png'),
      );
    }

    // A room: four people, @mentions.
    await _open(tester, container, 'room_1');
    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat_room.png'),
      );
    }

    // The details pane open beside the stream.
    await _open(tester, container, 'cnv_lin');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    fake.caps.add(sampleCaps);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat_runtime.png'),
      );
    }

    // The technical fold opened, a tool expanded, and the row menu.
    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('读取文件'));
    await tester.pumpAndSettle();
    // The row menu shows on hover.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('conv-cnv_lin'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('conv-menu-cnv_lin')));
    await tester.pumpAndSettle();
    if (enabled) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/chat_menu.png'),
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The same pane on a room: members, invite, settings.
    await _open(tester, container, 'room_1');
    if (enabled) {
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('shots/chat_room_details.png'),
      );
    }

    await tester.tap(find.byTooltip('让别人联系你'));
    await tester.pumpAndSettle();
    if (enabled) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/share.png'),
      );
    }
    // A key for someone new: shown once, with the words to send them.
    await tester.enterText(find.byKey(const ValueKey('share-new-name')), '周叙白');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-make-key')));
    await tester.pumpAndSettle();
    if (enabled) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/share_fresh.png'),
      );
    }

    // The file library.
    Navigator.of(tester.element(find.byType(ChatScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-files')));
    await tester.pumpAndSettle();
    if (enabled) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/files.png'),
      );
    }
  }, skip: !enabled);

  testWidgets('auth shot', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
    WindowChrome.enabled = true;
    addTearDown(() => WindowChrome.enabled = false);
    tester.view.physicalSize = const Size(3200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(FakeClient()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: const WindowChrome(child: AuthScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    await settleImages(tester);
    await expectLater(
      find.byType(WindowChrome),
      matchesGoldenFile('shots/auth.png'),
    );
  }, skip: !enabled);
}
