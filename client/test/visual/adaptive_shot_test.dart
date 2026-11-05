// Visual check of the phone and tablet layouts, and the empty and
// disconnected states. Run on demand:
//   OH_SHOT=1 flutter test test/visual --update-goldens

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/adaptive.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/auth/auth_screen.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/widgets/window_chrome.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

Future<(FakeClient, ProviderContainer)> _boot(
  WidgetTester tester, {
  required Size size,
  required double dpr,
  bool touch = false,
  bool chrome = false,
  oh.ConnectionState conn = oh.ConnectionState.connected,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  await loadFonts();
  Touch.debugOverride = touch;
  WindowChrome.enabled = chrome;
  addTearDown(() {
    Touch.debugOverride = false;
    WindowChrome.enabled = false;
  });
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = FakeViewPadding(
    top: padding.top * dpr,
    bottom: padding.bottom * dpr,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: padding.top * dpr,
    bottom: padding.bottom * dpr,
  );
  addTearDown(tester.view.reset);

  final fake = FakeClient();
  final container = ProviderContainer(overrides: [
    openHumanClientProvider.overrideWithValue(fake),
    currentHumanProvider.overrideWith(
      (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文'),
    ),
    connectionStateProvider.overrideWith((ref) => Stream.value(conn)),
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
  return (fake, container);
}

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

  testWidgets('phone shots', (tester) async {
    final (fake, container) = await _boot(
      tester,
      size: const Size(390, 844),
      dpr: 3,
      touch: true,
      padding: const EdgeInsets.only(top: 47, bottom: 34),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/phone_list.png'),
    );

    await tester.tap(find.byKey(const ValueKey('conv-cnv_zhou')));
    await tester.pumpAndSettle();
    await _open(tester, container, 'cnv_zhou');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/phone_chat.png'),
    );

    await tester.tap(find.byTooltip('对话详情'));
    await tester.pumpAndSettle();
    fake.caps.add(sampleCaps);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/phone_runtime.png'),
    );
  }, skip: !enabled);

  testWidgets('tablet shots', (tester) async {
    final (fake, container) = await _boot(
      tester,
      size: const Size(1024, 768),
      dpr: 2,
      touch: true,
      padding: const EdgeInsets.only(top: 24),
    );
    await _open(tester, container, 'room_1');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/tablet.png'),
    );
    await tester.tap(find.byTooltip('对话详情'));
    await tester.pumpAndSettle();
    fake.caps.add(sampleCaps);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/tablet_runtime.png'),
    );
  }, skip: !enabled);

  testWidgets('empty and offline', (tester) async {
    final (_, container) = await _boot(
      tester,
      size: const Size(1440, 900),
      dpr: 2,
      chrome: true,
      conn: oh.ConnectionState.disconnected,
    );
    container.read(activeConversationIdProvider.notifier).state = 'cnv_anon';
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/empty_offline.png'),
    );
  }, skip: !enabled);

  testWidgets('phone auth', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
    Touch.debugOverride = true;
    addTearDown(() => Touch.debugOverride = false);
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(FakeClient()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: const AuthScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/auth_phone.png'),
    );
  }, skip: !enabled);
}
