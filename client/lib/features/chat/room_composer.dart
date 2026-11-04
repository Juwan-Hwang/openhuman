/// The composer, and room mention helpers (design doc §10.4).
///
/// One composer for 1:1 and group rooms. In a room, typing "@" opens
/// member completion above the field; picking a name inserts "@名字 ".
/// Enter sends, Shift+Enter breaks the line, Ctrl/⌘+Enter ends the turn.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/adaptive.dart';
import '../../app/tokens.dart';

/// Member display names of a room, for completion + highlight.
List<String> roomMemberNames(Map<String, dynamic>? room) {
  final members = (room?['members'] as List?) ?? const [];
  return members
      .whereType<Map<String, dynamic>>()
      .map((m) => m['display_name'] as String? ?? '')
      .where((n) => n.isNotEmpty)
      .toList();
}

/// The composer at the foot of the stream.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.enabled,
    required this.onSend,
    this.onEndTurn,
    this.mentionNames = const [],
  });

  /// False after the human ended the turn.
  final bool enabled;
  final void Function(String text) onSend;

  /// Null hides the end-turn control (non-owners in a room, §10.6).
  final VoidCallback? onEndTurn;

  /// Room member names for "@" completion; empty in 1:1 chats.
  final List<String> mentionNames;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  int _pick = 0;

  /// The "@..." token under the caret, if any: (start index, query).
  (int, String)? _activeToken() {
    final text = _controller.text;
    var caret = _controller.selection.baseOffset;
    if (caret < 0 || caret > text.length) caret = text.length;
    final before = text.substring(0, caret);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
    final query = before.substring(at + 1);
    if (query.contains(' ') || query.contains('\n')) return null;
    return (at, query);
  }

  List<String> _suggestions() {
    final token = _activeToken();
    if (token == null) return const [];
    final q = token.$2.toLowerCase();
    return widget.mentionNames
        .where((n) => q.isEmpty || n.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  void _insert(String name) {
    final token = _activeToken();
    if (token == null) return;
    final (at, _) = token;
    final text = _controller.text;
    var caret = _controller.selection.baseOffset;
    if (caret < 0 || caret > text.length) caret = text.length;
    final replaced = '${text.substring(0, at)}@$name ${text.substring(caret)}';
    _controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: at + name.length + 2),
    );
    _focus.requestFocus();
    setState(() => _pick = 0);
  }

  void _send() {
    if (!widget.enabled) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final sugg = _suggestions();
    if (sugg.isNotEmpty) {
      if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() => _pick = (_pick + 1) % sugg.length);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() => _pick = (_pick - 1 + sugg.length) % sugg.length);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.tab ||
          (e.logicalKey == LogicalKeyboardKey.enter && !keys.isShiftPressed)) {
        _insert(sugg[_pick.clamp(0, sugg.length - 1)]);
        return KeyEventResult.handled;
      }
    }
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (keys.isControlPressed || keys.isMetaPressed) {
        widget.onEndTurn?.call();
        return KeyEventResult.handled;
      }
      if (keys.isShiftPressed) return KeyEventResult.ignored;
      // An IME composing a word owns Enter.
      if (_controller.value.composing.isValid &&
          !_controller.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sugg = _suggestions();
    final canSend = widget.enabled && _controller.text.trim().isNotEmpty;
    final focused = _focus.hasFocus;

    final g = StreamScope.of(context);
    final touch = Touch.primary;
    final phone = !g.rail;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        phone ? Sp.x3 : g.gutter,
        0,
        phone ? Sp.x3 : g.right,
        // Clear a phone's home indicator.
        (phone ? Sp.x3 : Sp.x5) + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sugg.isNotEmpty)
            _Suggestions(names: sugg, picked: _pick, onPick: _insert),
          Focus(
            canRequestFocus: false,
            onFocusChange: (_) => setState(() {}),
            child: AnimatedContainer(
              duration: Mo.fast,
              decoration: BoxDecoration(
                color: widget.enabled ? Dk.p2 : Dk.p1,
                borderRadius: BorderRadius.circular(Rd.xl),
                border: Border.all(
                  color: focused && widget.enabled ? Dk.t4 : Dk.line2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Dk.bgFade,
                    blurRadius: 50,
                    offset: Offset(0, -20),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 14, 20, 0),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: phone ? 5 : 8,
                      textInputAction: touch
                          ? TextInputAction.newline
                          : TextInputAction.none,
                      style: Ty.prose.copyWith(color: Dk.t1),
                      cursorColor: Dk.signal,
                      cursorWidth: 2,
                      onChanged: (_) => setState(() => _pick = 0),
                      decoration: InputDecoration(
                        hintText: widget.enabled
                            ? (widget.mentionNames.isEmpty
                                ? '回复 AI 的请求…'
                                : '回复…  输入 @ 提及成员')
                            : '本轮已结束，下一条请求到达时自动恢复',
                        hintStyle: Ty.prose.copyWith(color: Dk.t3),
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(phone ? 12 : 20, 8, 10, 10),
                    child: Row(
                      children: [
                        // Keyboard hints only where there is a keyboard,
                        // and only when there is room to read them.
                        if (!touch && !phone) ...[
                          const _Kbd('↵', '发送'),
                          const SizedBox(width: Sp.x4),
                          const _Kbd('Shift ↵', '换行'),
                          if (widget.onEndTurn != null && g.gutter > 90) ...[
                            const SizedBox(width: Sp.x4),
                            const _Kbd('Ctrl ↵', '结束本轮'),
                          ],
                        ],
                        const Spacer(),
                        if (widget.onEndTurn != null && widget.enabled) ...[
                          _GhostButton(
                            key: const ValueKey('composer-end-turn'),
                            label: '结束本轮',
                            onTap: widget.onEndTurn!,
                          ),
                          const SizedBox(width: Sp.x2),
                        ],
                        _SendButton(
                          key: const ValueKey('composer-send'),
                          enabled: canSend,
                          onTap: _send,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.keys, this.label);
  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: Dk.line2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(keys, style: Ty.meta.copyWith(fontSize: 10.5)),
        ),
        const SizedBox(width: 6),
        Text(label, style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3)),
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.md),
        hoverColor: Dk.p3,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: Touch.primary ? 13 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.md),
            border: Border.all(color: Dk.line2),
          ),
          child: Text(
            label,
            style: Ty.name.copyWith(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '发送',
      child: AnimatedContainer(
        duration: Mo.fast,
        decoration: BoxDecoration(
          color: enabled ? Dk.signal : Dk.p3,
          borderRadius: BorderRadius.circular(Rd.md),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(Rd.md),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, Touch.primary ? 13 : 8, 14, Touch.primary ? 13 : 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '发送',
                    style: Ty.name.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: enabled ? Dk.signalInk : Dk.t3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 15,
                    color: enabled ? Dk.signalInk : Dk.t3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.names,
    required this.picked,
    required this.onPick,
  });
  final List<String> names;
  final int picked;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x2),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(maxWidth: 320),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Dk.p2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line2),
        boxShadow: const [
          BoxShadow(color: Dk.shadow, blurRadius: 24),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < names.length; i++)
            InkWell(
              key: ValueKey('mention-${names[i]}'),
              onTap: () => onPick(names[i]),
              borderRadius: BorderRadius.circular(Rd.sm),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: i == picked ? Dk.p3 : null,
                  borderRadius: BorderRadius.circular(Rd.sm),
                ),
                child: Row(
                  children: [
                    Text('@', style: Ty.meta.copyWith(color: Dk.signal)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(names[i], style: Ty.body)),
                    if (i == picked) const Text('Tab', style: Ty.meta),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Split [text] into spans; spans whose recognizer is non-null are mentions
/// of a room member ("@名字" exactly, longest name first).
List<({String text, bool isMention})> mentionSpans(
  String text,
  List<String> names,
) {
  if (names.isEmpty || text.isEmpty) {
    return [(text: text, isMention: false)];
  }
  final sorted = [...names]..sort((a, b) => b.length.compareTo(a.length));
  final spans = <({String text, bool isMention})>[];
  var i = 0;
  var plain = StringBuffer();
  while (i < text.length) {
    if (text[i] == '@') {
      String? hit;
      for (final n in sorted) {
        if (text.startsWith(n, i + 1)) {
          // The name must end the text or be followed by a non-name char.
          final end = i + 1 + n.length;
          if (end >= text.length ||
              RegExp(r'[\s，。,.!!?？:：、]').hasMatch(text[end])) {
            hit = n;
            break;
          }
        }
      }
      if (hit != null) {
        if (plain.isNotEmpty) {
          spans.add((text: plain.toString(), isMention: false));
          plain = StringBuffer();
        }
        spans.add((text: '@$hit', isMention: true));
        i += 1 + hit.length;
        continue;
      }
    }
    plain.write(text[i]);
    i++;
  }
  if (plain.isNotEmpty) spans.add((text: plain.toString(), isMention: false));
  return spans;
}
