import 'package:flutter_test/flutter_test.dart';
import 'package:openhuman_client/core/identity.dart';

void main() {
  group('Caller.parse', () {
    void expectParse(String input,
        {String? person, String? tool, String? tag}) {
      final c = Caller.parse(input);
      expect(c.person, person, reason: 'person of "$input"');
      expect(c.tool, tool, reason: 'tool of "$input"');
      expect(c.tag, tag, reason: 'tag of "$input"');
    }

    test('room caller: person 的 tool · tag', () {
      expectParse('小明的 Claude Code · a3f9',
          person: '小明', tool: 'Claude Code', tag: 'a3f9');
      expectParse('林晓 的 Codex · 1b0e',
          person: '林晓', tool: 'Codex', tag: '1b0e');
    });

    test('display name · tag', () {
      expectParse('许诺 · 1b0e', person: '许诺', tag: '1b0e');
    });

    test('brackets, full-width brackets', () {
      expectParse('Mia Chen (Codex)', person: 'Mia Chen', tool: 'Codex');
      expectParse('周子航（Cursor）', person: '周子航', tool: 'Cursor');
    });

    test('separators: via, 经由, @, ·, -', () {
      expectParse('周子航 via Cursor', person: '周子航', tool: 'Cursor');
      expectParse('周子航 经由 Trae', person: '周子航', tool: 'Trae');
      expectParse('Mia @ WorkBuddy', person: 'Mia', tool: 'WorkBuddy');
      expectParse('陈一鸣 · Claude Code', person: '陈一鸣', tool: 'Claude Code');
      expectParse('Leo - opencode', person: 'Leo', tool: 'OpenCode');
    });

    test("possessive English and bare suffix", () {
      expectParse("Mia's Cursor", person: 'Mia', tool: 'Cursor');
      expectParse('小明 Claude Code', person: '小明', tool: 'Claude Code');
    });

    test('a tool alone has no person', () {
      expectParse('Claude Code', tool: 'Claude Code');
      expectParse('WorkBuddy', tool: 'WorkBuddy');
      expectParse('claude-code', tool: 'Claude Code');
      expectParse('Claude Code · a3f9', tool: 'Claude Code', tag: 'a3f9');
      expectParse('Codex CLI', tool: 'Codex');
      expectParse('pi', tool: 'pi');
      final c = Caller.parse('Claude Code');
      expect(c.anonymous, isTrue);
      expect(c.name, Caller.unnamed);
      expect(c.via, '经由 Claude Code');
    });

    test('ids and blanks have nobody to name', () {
      expectParse('agt_demo_codex');
      expectParse('');
      expect(Caller.parse(null).name, Caller.unnamed);
    });

    test('plain names stay whole', () {
      expectParse('李思远', person: '李思远');
      expectParse('Alice Chen', person: 'Alice Chen');
      // "pi" must match as a whole word only.
      expectParse('Hapi', person: 'Hapi');
      // A dot followed by something that is not a tag or a tool.
      expectParse('设计组 · 周会', person: '设计组 · 周会');
    });
  });

  group('initialsOf', () {
    test('Chinese names show the given name', () {
      expect(initialsOf('林晓'), '林晓');
      expect(initialsOf('陈一鸣'), '一鸣');
      expect(initialsOf('欧阳娜娜'), '欧');
      expect(initialsOf('妈'), '妈');
    });
    test('Latin names show initials', () {
      expect(initialsOf('Mia Chen'), 'MC');
      expect(initialsOf('leo'), 'LE');
      expect(initialsOf(''), '?');
    });
  });
}
