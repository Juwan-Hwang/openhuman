/// A small, fast renderer for the text agents actually send.
///
/// Agents write a narrow slice of Markdown: paragraphs, fenced code,
/// `inline code`, **bold**, bullet and numbered lists, and the odd
/// heading. A full Markdown engine costs layout time on every message in
/// a long stream; this covers that slice and leaves anything else as
/// plain text, which is always readable.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/tokens.dart';

/// One parsed block.
sealed class RichBlock {
  const RichBlock();
}

class ParaBlock extends RichBlock {
  const ParaBlock(this.text);
  final String text;
}

class HeadBlock extends RichBlock {
  const HeadBlock(this.text);
  final String text;
}

class ListBlock extends RichBlock {
  const ListBlock(this.items, {required this.ordered});
  final List<String> items;
  final bool ordered;
}

class CodeBlock extends RichBlock {
  const CodeBlock(this.code, this.lang);
  final String code;
  final String lang;
}

final _bullet = RegExp(r'^\s*[-*•]\s+');
final _ordered = RegExp(r'^\s*\d+[.)、]\s+');
final _head = RegExp(r'^#{1,4}\s+');

/// Splits [src] into blocks. Pure, so it is unit-tested.
List<RichBlock> parseBlocks(String src) {
  final out = <RichBlock>[];
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  final para = <String>[];
  List<String>? list;
  var ordered = false;

  void flushPara() {
    if (para.isNotEmpty) {
      out.add(ParaBlock(para.join('\n')));
      para.clear();
    }
  }

  void flushList() {
    if (list != null) {
      out.add(ListBlock(list!, ordered: ordered));
      list = null;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = line.trimLeft();
    if (fence.startsWith('```')) {
      flushPara();
      flushList();
      final lang = fence.substring(3).trim();
      final body = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        body.add(lines[i]);
        i++;
      }
      out.add(CodeBlock(body.join('\n'), lang));
      continue;
    }
    if (line.trim().isEmpty) {
      flushPara();
      flushList();
      continue;
    }
    if (_head.hasMatch(line)) {
      flushPara();
      flushList();
      out.add(HeadBlock(line.replaceFirst(_head, '')));
      continue;
    }
    final isB = _bullet.hasMatch(line);
    final isO = !isB && _ordered.hasMatch(line);
    if (isB || isO) {
      flushPara();
      if (list != null && ordered != isO) flushList();
      ordered = isO;
      list ??= [];
      list!.add(line.replaceFirst(isB ? _bullet : _ordered, ''));
      continue;
    }
    if (list != null && line.startsWith('  ')) {
      list![list!.length - 1] = '${list!.last} ${line.trim()}';
      continue;
    }
    flushList();
    para.add(line);
  }
  flushPara();
  flushList();
  return out;
}

/// Inline spans: `code`, **bold**, @mentions, bare links.
List<InlineSpan> inlineSpans(
  String text, {
  required TextStyle base,
  required Color codeInk,
  required Color codeFloor,
  List<String> mentions = const [],
  Color? mentionInk,
}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'`([^`\n]+)`|\*\*([^*\n]+)\*\*|(https?://[^\s)）]+)');
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.addAll(_mentionSplit(
          text.substring(last, m.start), base, mentions, mentionInk));
    }
    if (m.group(1) != null) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: codeFloor,
            borderRadius: BorderRadius.circular(Rd.xs),
          ),
          child: Text(
            m.group(1)!,
            style: Ty.code.copyWith(
              fontSize: (base.fontSize ?? 14) - 2,
              height: 1.3,
              color: codeInk,
            ),
          ),
        ),
      ));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
        text: m.group(2),
        style: base.copyWith(fontWeight: FontWeight.w700),
      ));
    } else {
      final url = m.group(3)!;
      spans.add(TextSpan(
        text: url,
        style: base.copyWith(
          color: Dk.blue,
          decoration: TextDecoration.underline,
          decorationColor: Dk.blue.withValues(alpha: 0.4),
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => Clipboard.setData(ClipboardData(text: url)),
      ));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.addAll(
        _mentionSplit(text.substring(last), base, mentions, mentionInk));
  }
  return spans;
}

List<InlineSpan> _mentionSplit(
  String text,
  TextStyle base,
  List<String> names,
  Color? ink,
) {
  if (names.isEmpty || !text.contains('@')) {
    return [TextSpan(text: text, style: base)];
  }
  final sorted = [...names]..sort((a, b) => b.length.compareTo(a.length));
  final out = <InlineSpan>[];
  final buf = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i] == '@') {
      String? hit;
      for (final n in sorted) {
        if (text.startsWith(n, i + 1)) {
          hit = n;
          break;
        }
      }
      if (hit != null) {
        if (buf.isNotEmpty) {
          out.add(TextSpan(text: buf.toString(), style: base));
          buf.clear();
        }
        out.add(TextSpan(
          text: '@$hit',
          style: base.copyWith(
            color: ink ?? Dk.signal,
            fontWeight: FontWeight.w700,
          ),
        ));
        i += hit.length + 1;
        continue;
      }
    }
    buf.write(text[i]);
    i++;
  }
  if (buf.isNotEmpty) out.add(TextSpan(text: buf.toString(), style: base));
  return out;
}

/// Renders agent or human text.
class RichMessageText extends StatelessWidget {
  const RichMessageText(
    this.text, {
    super.key,
    required this.style,
    this.codeInk = Dk.signalCode,
    this.codeFloor = Dk.p4,
    this.mentions = const [],
    this.inverted = false,
  });

  final String text;
  final TextStyle style;
  final Color codeInk;
  final Color codeFloor;
  final List<String> mentions;

  /// Rendering on the paper bubble rather than the dark floor.
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(text);
    final children = <Widget>[];
    for (final b in blocks) {
      if (children.isNotEmpty) children.add(const SizedBox(height: Sp.x3));
      children.add(_block(b));
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _rich(String t, TextStyle s) => Text.rich(
        TextSpan(
          children: inlineSpans(
            t,
            base: s,
            codeInk: codeInk,
            codeFloor: codeFloor,
            mentions: mentions,
          ),
        ),
      );

  Widget _block(RichBlock b) {
    switch (b) {
      case ParaBlock(:final text):
        return _rich(text, style);
      case HeadBlock(:final text):
        return _rich(
          text,
          style.copyWith(fontWeight: FontWeight.w700, fontSize: 15.5),
        );
      case ListBlock(:final items, :final ordered):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.x1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        ordered ? '${i + 1}.' : '—',
                        style: Ty.meta.copyWith(
                          fontSize: 12,
                          height: (style.fontSize! * style.height!) / 12,
                          color: inverted ? Dk.mineMuted : Dk.t3,
                        ),
                      ),
                    ),
                    Expanded(child: _rich(items[i], style)),
                  ],
                ),
              ),
          ],
        );
      case CodeBlock(:final code, :final lang):
        return CodePanel(code: code, lang: lang, inverted: inverted);
    }
  }
}

/// A fenced code block with a header and a copy control.
class CodePanel extends StatefulWidget {
  const CodePanel({
    super.key,
    required this.code,
    required this.lang,
    this.inverted = false,
  });

  final String code;
  final String lang;
  final bool inverted;

  @override
  State<CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<CodePanel> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final floor = widget.inverted ? Dk.ink : Dk.codeFloor;
    final lines = widget.code.split('\n');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: floor,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: Dk.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: const BoxDecoration(
              color: Dk.codeHead,
              border: Border(bottom: BorderSide(color: Dk.line)),
            ),
            child: Row(
              children: [
                Text(
                  widget.lang.isEmpty ? '代码' : widget.lang,
                  style: Ty.meta,
                ),
                const Spacer(),
                Text('${lines.length} 行', style: Ty.meta),
                const SizedBox(width: Sp.x2),
                _MiniButton(
                  label: _copied ? '已复制' : '复制',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    await Future<void>.delayed(const Duration(seconds: 2));
                    if (mounted) setState(() => _copied = false);
                  },
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ConstrainedBox(
                // Tinted diff lines run the full width of the panel.
                constraints: BoxConstraints(minWidth: box.maxWidth),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        _codeLine(i + 1, lines[i], lines.length),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeLine(int n, String line, int total) {
    Color? tint;
    Color ink = Ty.code.color!;
    if (widget.lang == 'diff' || widget.lang.isEmpty) {
      if (line.startsWith('+') && !line.startsWith('+++')) {
        tint = Dk.okSoft;
        ink = Dk.diffAdd;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        tint = Dk.dangerSoft;
        ink = Dk.diffDel;
      }
    }
    final w = total >= 100 ? 40.0 : 30.0;
    return Container(
      color: tint,
      padding: const EdgeInsets.only(left: 14, right: 18),
      child: Row(
        children: [
          SizedBox(
            width: w,
            child: Text('$n', style: Ty.code.copyWith(color: Dk.t4)),
          ),
          Text(line, style: Ty.code.copyWith(color: ink)),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xs),
        hoverColor: Dk.p3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(label, style: Ty.small.copyWith(fontSize: 11.5)),
        ),
      ),
    );
  }
}
