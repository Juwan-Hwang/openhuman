// OpenHuman is two people talking. The console never calls the other
// person "AI": they are someone writing from their own tool. This scans
// every word the console itself draws — not what people wrote — in the
// main states.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:openhuman_client/core/sdk_provider.dart';
import 'package:openhuman_client/features/auth/auth_screen.dart';
import 'package:openhuman_client/features/chat/chat_screen.dart';
import 'package:openhuman_client/features/chat/stream/message_stream.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import 'visual/harness.dart';

final _ai = RegExp(r'(^|[^A-Za-z])AI([^A-Za-z]|$)');

/// Words on screen outside the message stream.
List<String> _chromeWords(WidgetTester tester) {
  final stream = find.byType(MessageStream).evaluate().toSet();
  bool inStream(Element e) {
    var hit = false;
    e.visitAncestorElements((a) {
      if (stream.contains(a)) {
        hit = true;
        return false;
      }
      return true;
    });
    return hit;
  }

  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    if (inStream(e)) continue;
    out.add((e.widget as RichText).text.toPlainText());
  }
  for (final e in find.byType(EditableText).evaluate()) {
    if (inStream(e)) continue;
    final w = e.widget as EditableText;
    out.add(w.controller.text);
  }
  for (final e in find.byType(Tooltip).evaluate()) {
    out.add((e.widget as Tooltip).message ?? '');
  }
  return out;
}

void _expectNoAi(WidgetTester tester, String where) {
  final words = _chromeWords(tester);
  // A scan that sees nothing would pass for the wrong reason.
  expect(words.join().length, greaterThan(20), reason: 'nothing scanned');
  final hits = words.where(_ai.hasMatch).toList();
  expect(hits, isEmpty, reason: '"AI" on screen in $where: $hits');
}

void main() {
  testWidgets('the console never calls anyone AI', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeClient();
    final c = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(fake),
      currentHumanProvider.overrideWith(
        (ref) => const oh.HumanSession(id: 'hum_me', displayName: '黄治文'),
      ),
      connectionStateProvider
          .overrideWith((ref) => Stream.value(oh.ConnectionState.connected)),
      serverConfigProvider.overrideWith(
        (ref) => const ServerConfig(
          serverUrl: 'wss://oh.example.com/ws',
          apiKey: 'ohk_x',
        ),
      ),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: darkTheme, home: const ChatScreen()),
    ));
    await tester.pumpAndSettle();
    _expectNoAi(tester, 'the empty console');

    for (final id in ['cnv_lin', 'cnv_mia', 'room_1']) {
      c.read(activeConversationIdProvider.notifier).state = id;
      await tester.pumpAndSettle();
      _expectNoAi(tester, id);
    }

    // Details, with the technical fold open and the tools reported.
    c.read(activeConversationIdProvider.notifier).state = 'cnv_lin';
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    fake.caps.add(sampleCaps);
    await tester.pumpAndSettle();
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
    _expectNoAi(tester, 'details');

    await tester.tap(find.byTooltip('分享联系方式'));
    await tester.pumpAndSettle();
    _expectNoAi(tester, 'the share sheet');
  });

  testWidgets('nor does the sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      openHumanClientProvider.overrideWithValue(FakeClient()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: darkTheme, home: const AuthScreen()),
    ));
    await tester.pumpAndSettle();
    _expectNoAi(tester, 'sign-in');
  });
}
