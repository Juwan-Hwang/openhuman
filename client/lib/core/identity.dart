/// Who is on the other end of a conversation.
///
/// OpenHuman is two people talking. The caller types in their own AI
/// tool (Claude Code, Cursor, WorkBuddy, Trae…), and that tool is only
/// the transport. But the name the server hands the client is whatever
/// the caller's key or room seat was called, so it arrives in many
/// shapes:
///
/// ```
/// 小明的 Claude Code · a3f9     room caller: person + tool + session tag
/// 许诺 · 1b0e                   display name + session tag
/// Mia Chen (Codex)              person + tool in brackets
/// 周子航 via Cursor              person + tool
/// Claude Code                   a tool and nothing else
/// agt_demo_codex                a bare id
/// ```
///
/// [Caller.parse] pulls the person out of all of these, so the console
/// can lead with the person and mention the tool only as a small tag
/// ("经由 Claude Code"). Pure, and unit-tested.
library;

/// A caller's name split into the parts the UI shows separately.
class Caller {
  const Caller({this.person, this.tool, this.tag, required this.raw});

  /// The person, when the name carries one: "小明", "Mia Chen".
  final String? person;

  /// The AI tool they type in, normalised: "Claude Code", "Cursor".
  final String? tool;

  /// The short per-session tag the server appends to room speech, so
  /// two windows of the same person can be told apart ("a3f9").
  final String? tag;

  /// The name exactly as it arrived.
  final String raw;

  /// What a list row or a title calls this person.
  ///
  /// Without a person in the name there is nobody to name, so the row
  /// says so plainly instead of putting the tool where the person goes.
  String get name => person ?? unnamed;

  /// Whether [person] had to be invented.
  bool get anonymous => person == null;

  /// The secondary line under a name: "经由 Claude Code".
  String? get via => tool == null ? null : '经由 $tool';

  static const String unnamed = '未命名联系人';

  /// Known AI tools, in the casing their makers use. Matched case- and
  /// space-insensitively, longest first, so "Claude Code" wins over
  /// "Claude" and "WorkBuddy CLI" over "WorkBuddy".
  static const List<String> tools = [
    'Claude Agent SDK',
    'Claude Code',
    'Claude',
    'Codex CLI',
    'Codex',
    'Cursor',
    'Windsurf',
    'WorkBuddy CLI',
    'WorkBuddy',
    'CodeBuddy',
    'Trae',
    'Qoder',
    'DeepSeek Harness',
    'DeepSeek',
    'opencode',
    'OpenCode',
    'Copilot',
    'GitHub Copilot',
    'Gemini CLI',
    'Gemini',
    'Cline',
    'Grok',
    'ZCode',
    'Reasonix',
    'Kimi',
    'pi',
  ];

  /// What a detected framework name is shown as.
  static const Map<String, String> _canonical = {
    'claude agent sdk': 'Claude Code',
    'codex cli': 'Codex',
    'workbuddy cli': 'WorkBuddy',
    'opencode': 'OpenCode',
    'github copilot': 'Copilot',
    'gemini cli': 'Gemini',
  };

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

  /// The canonical tool name for [s] when [s] is exactly a known tool.
  static String? toolNamed(String s) {
    final q = _squash(s.trim());
    if (q.isEmpty) return null;
    for (final t in _byLength) {
      if (_squash(t) == q) return _canonical[t.toLowerCase()] ?? t;
    }
    return null;
  }

  static final List<String> _byLength = [...tools]
    ..sort((a, b) => b.length.compareTo(a.length));

  /// A known tool at the end of [s], as (index where it starts, name).
  static (int, String)? _toolSuffix(String s) {
    final lower = s.toLowerCase();
    for (final t in _byLength) {
      final tl = t.toLowerCase();
      if (!lower.endsWith(tl)) continue;
      final at = s.length - t.length;
      // Whole words only: "Hapi" is not "pi".
      if (at > 0) {
        final before = s[at - 1];
        if (RegExp(r'[A-Za-z0-9]').hasMatch(before)) continue;
      }
      return (at, _canonical[tl] ?? t);
    }
    return null;
  }

  static final RegExp _tagRe = RegExp(r'^[0-9a-f]{4,8}$');
  static final RegExp _idRe = RegExp(
    r'^(agt|hum|key|cnv|room|usr|ohk)_[A-Za-z0-9_\-]+$',
  );

  static Caller parse(String? input) {
    final raw = (input ?? '').trim();
    var s = raw;
    String? tag;
    String? tool;

    if (s.isEmpty || _idRe.hasMatch(s)) {
      return Caller(raw: raw);
    }

    // "… · a3f9": the session tag, always last.
    final dot = s.lastIndexOf('·');
    if (dot > 0) {
      final tail = s.substring(dot + 1).trim();
      if (_tagRe.hasMatch(tail)) {
        tag = tail;
        s = s.substring(0, dot).trim();
      }
    }

    // "Mia Chen (Codex)" / "小明（Cursor）".
    final br = RegExp(r'^(.*?)\s*[（(]\s*([^()（）]+?)\s*[)）]$').firstMatch(s);
    if (br != null) {
      final t = toolNamed(br.group(2)!);
      if (t != null) {
        tool = t;
        s = br.group(1)!.trim();
      }
    }

    // "周子航 via Cursor" / "周子航 经由 Cursor" / "周子航 @ Cursor" /
    // "周子航 · Cursor" / "周子航 - Cursor" / "周子航 | Cursor".
    if (tool == null) {
      final sep = RegExp(
        r'^(.*?)\s*(?:\svia\s|经由|\s@\s|·|\s-\s|\s\|\s|/)\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(s);
      if (sep != null) {
        final t = toolNamed(sep.group(2)!);
        if (t != null && sep.group(1)!.trim().isNotEmpty) {
          tool = t;
          s = sep.group(1)!.trim();
        }
      }
    }

    // "小明的 Claude Code" / "Mia's Cursor" / "小明 Claude Code".
    if (tool == null) {
      final whole = toolNamed(s);
      if (whole != null) {
        return Caller(tool: whole, tag: tag, raw: raw);
      }
      final suf = _toolSuffix(s);
      if (suf != null) {
        final (at, name) = suf;
        var head = s.substring(0, at).trim();
        head = head
            .replaceFirst(RegExp(r'\s*的$'), '')
            .replaceFirst(RegExp(r"[’']s$"), '')
            .trim();
        if (head.isNotEmpty) {
          tool = name;
          s = head;
        }
      }
    }

    s = s.trim();
    if (s.isEmpty || _idRe.hasMatch(s)) {
      return Caller(tool: tool, tag: tag, raw: raw);
    }
    return Caller(person: s, tool: tool, tag: tag, raw: raw);
  }

  @override
  String toString() => 'Caller(person: $person, tool: $tool, tag: $tag)';
}

/// The one or two characters an avatar shows for [name].
///
/// Chinese names show the given name (the last two characters of a
/// three-character name, as people are addressed day to day); Latin
/// names show initials.
String initialsOf(String name) {
  final n = name.trim();
  if (n.isEmpty) return '?';
  final cjk = RegExp(r'[\u3400-\u9fff]');
  if (cjk.hasMatch(n[0])) {
    final chars = n.characters;
    if (chars.length == 3) return chars.skip(1).join();
    if (chars.length >= 4) return chars.take(1).join();
    return chars.length == 2 ? chars.join() : chars.first;
  }
  final words = n
      .split(RegExp(r'[\s_\-.]+'))
      .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0]))
      .toList();
  if (words.isEmpty) return n.characters.first.toUpperCase();
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

extension on String {
  _Chars get characters => _Chars(this);
}

/// Just enough of a grapheme view for names (no combining marks in
/// practice), without pulling in package:characters here.
class _Chars {
  _Chars(String s) : _runes = s.runes.map(String.fromCharCode).toList();
  final List<String> _runes;
  int get length => _runes.length;
  String get first => _runes.first;
  Iterable<String> skip(int n) => _runes.skip(n);
  Iterable<String> take(int n) => _runes.take(n);
  String join() => _runes.join();
}
