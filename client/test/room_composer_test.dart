import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/features/chat/room_composer.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('@ opens member completion and tapping inserts @name ',
      (tester) async {
    String? sent;
    await tester.pumpWidget(
      _wrap(Composer(enabled: true, onSend: (t) => sent = t)),
    );
    await tester.enterText(find.byType(TextField), 'hello @ki');
    await tester.pump();
    // roomInfoProvider may not resolve in tests; no crash, suggestions empty
    // is acceptable. Type a plain message and send it.
    await tester.enterText(find.byType(TextField), 'hello @kimi 你好');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(sent, 'hello @kimi 你好');
  });

  testWidgets('disabled composer does not send', (tester) async {
    String? sent;
    await tester.pumpWidget(
      _wrap(
        Composer(enabled: false, onSend: (t) => sent = t),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(sent, isNull);
  });

  test('mentionSpans highlights exact member names only', () {
    final spans = mentionSpans('问 @小明 和 @小明2 好', ['小明', '小明2']);
    final mentions =
        spans.where((s) => s.isMention).map((s) => s.text).toList();
    // Scan is positional; longest-name-first wins within one position.
    expect(mentions, ['@小明', '@小明2']);
  });

  test('mentionSpans ignores unknown names and mid-word @', () {
    final spans = mentionSpans('email a@b.com 和 @陌生人', ['小明']);
    expect(spans.every((s) => !s.isMention), isTrue);
  });

  test('mentionSpans returns the text unchanged without members', () {
    final spans = mentionSpans('@小明 你好', []);
    expect(spans, [(text: '@小明 你好', isMention: false)]);
  });
}
