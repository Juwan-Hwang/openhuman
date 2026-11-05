import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/features/chat/room_composer.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

const _send = ValueKey('composer-send');

void main() {
  testWidgets('the send button sends what is typed', (tester) async {
    String? sent;
    await tester.pumpWidget(
      _wrap(Composer(enabled: true, onSend: (t) => sent = t)),
    );
    await tester.enterText(find.byType(TextField), 'hello @kimi 你好');
    await tester.pump();
    await tester.tap(find.byKey(_send));
    await tester.pump();
    expect(sent, 'hello @kimi 你好');
  });

  testWidgets('Enter sends; Shift+Enter does not', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(Composer(enabled: true, onSend: sent.add)),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '晚上一起吃饭？');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sent, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, ['晚上一起吃饭？']);
  });

  testWidgets('Ctrl+Enter sends the draft, then ends the turn', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      _wrap(Composer(
        enabled: true,
        onSend: (t) => log.add('send:$t'),
        onEndTurn: () => log.add('end'),
      )),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '就这些，回头聊');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(log, ['send:就这些，回头聊', 'end']);
  });

  testWidgets('发送完毕 ends the turn with an empty draft', (tester) async {
    var ended = 0;
    await tester.pumpWidget(
      _wrap(Composer(
        enabled: true,
        onSend: (_) {},
        onEndTurn: () => ended++,
      )),
    );
    expect(find.text('发送完毕'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('composer-end-turn')));
    await tester.pump();
    expect(ended, 1);
  });

  testWidgets('after the turn ends the composer offers to reopen',
      (tester) async {
    String? sent;
    var reopened = 0;
    await tester.pumpWidget(
      _wrap(Composer(
        enabled: false,
        onSend: (t) => sent = t,
        onReopen: () => reopened++,
      )),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('这一轮你说完了'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('composer-reopen')));
    await tester.pump();
    expect(reopened, 1);
    expect(sent, isNull);
  });

  testWidgets('waiting on me says so; offline holds the send', (tester) async {
    String? sent;
    await tester.pumpWidget(
      _wrap(Composer(
        enabled: true,
        waitingOnMe: true,
        offline: true,
        to: '林晓',
        onSend: (t) => sent = t,
      )),
    );
    // Offline outranks "your move": the field says why nothing sends.
    expect(find.text('对方在等你回复'), findsNothing);
    await tester.enterText(find.byType(TextField), '在吗');
    await tester.pump();
    await tester.tap(find.byKey(_send));
    await tester.pump();
    expect(sent, isNull);

    await tester.pumpWidget(
      _wrap(Composer(
        enabled: true,
        waitingOnMe: true,
        to: '林晓',
        onSend: (t) => sent = t,
      )),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('对方在等你回复'), findsOneWidget);
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
