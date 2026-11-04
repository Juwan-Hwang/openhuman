import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/features/chat/stream/message_stream.dart';
import 'package:openhuman_client/features/chat/stream/rich_text.dart';

types.TextMessage _m(String id, String who, DateTime t) => types.TextMessage(
      id: id,
      author: types.User(id: who),
      text: id,
      createdAt: t.millisecondsSinceEpoch,
    );

void main() {
  group('parseBlocks', () {
    test('fenced code keeps its language and body', () {
      final b = parseBlocks('看这里：\n```diff\n-a\n+b\n```\n好了');
      expect(b.length, 3);
      expect(b[1], isA<CodeBlock>());
      expect((b[1] as CodeBlock).lang, 'diff');
      expect((b[1] as CodeBlock).code, '-a\n+b');
    });

    test('an unclosed fence still renders its body as code', () {
      final b = parseBlocks('```\nx = 1');
      expect((b.single as CodeBlock).code, 'x = 1');
    });

    test('ordered and bullet lists split apart', () {
      final b = parseBlocks('1. 甲\n2. 乙\n- 丙');
      expect(b.length, 2);
      expect((b[0] as ListBlock).ordered, isTrue);
      expect((b[0] as ListBlock).items, ['甲', '乙']);
      expect((b[1] as ListBlock).ordered, isFalse);
    });

    test('blank lines separate paragraphs, single breaks do not', () {
      final b = parseBlocks('一\n二\n\n三');
      expect(b.length, 2);
      expect((b[0] as ParaBlock).text, '一\n二');
    });
  });

  group('buildRows', () {
    final t0 = DateTime(2026, 11, 4, 10);

    test('same author within the window folds into one turn', () {
      final rows = buildRows([
        _m('c', 'a', t0.add(const Duration(minutes: 2))),
        _m('b', 'a', t0.add(const Duration(minutes: 1))),
        _m('a', 'a', t0),
      ]);
      expect(rows.map((r) => r.head), [false, false, true]);
    });

    test('a new speaker or a long pause starts a turn', () {
      final rows = buildRows([
        _m('c', 'a', t0.add(const Duration(minutes: 30))),
        _m('b', 'h', t0.add(const Duration(minutes: 1))),
        _m('a', 'a', t0),
      ]);
      expect(rows.map((r) => r.head), [true, true, true]);
    });

    test('a new calendar day breaks the stream', () {
      final rows = buildRows([
        _m('b', 'a', t0.add(const Duration(days: 1))),
        _m('a', 'a', t0),
      ]);
      expect(rows.map((r) => r.dayBreak), [true, true]);
    });
  });

  test('dayLabel speaks Chinese', () {
    final now = DateTime(2026, 11, 4, 12);
    expect(dayLabel(DateTime(2026, 11, 4, 1), now), '今天');
    expect(dayLabel(DateTime(2026, 11, 3, 23), now), '昨天');
    expect(dayLabel(DateTime(2026, 2, 1), now), '2 月 1 日');
    expect(dayLabel(DateTime(2025, 2, 1), now), '2025 年 2 月 1 日');
  });
}
