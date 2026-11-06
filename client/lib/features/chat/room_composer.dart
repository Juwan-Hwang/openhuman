/// The composer, and room mention helpers (design doc §10.4).
///
/// One composer for 1:1 chats and group rooms.
///
/// * Enter sends, Shift+Enter breaks the line.
/// * Ctrl/⌘+Enter is 发送完毕: sends what is typed, then tells the other
///   person's tool I am done for now, so their window stops waiting.
///   After that the composer says so and offers 继续说 to reopen.
/// * In a room, "@" opens member completion above the field; picking a
///   name inserts "@名字 ".
/// * When the other person asked for files (a picture, a recording),
///   the attach control adds them as chips and they go with the words.
/// * Offline, the words stay in the field and send is held back.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/adaptive.dart';
import '../../app/tokens.dart';
import '../../core/files_io.dart';
import '../../core/tasks.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import 'stream/attachments.dart';
import '../../widgets/haptics.dart';

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
    this.onReopen,
    this.mentionNames = const [],
    this.to,
    this.waitingOnMe = false,
    this.offline = false,
    this.fileTypes,
    this.onSendFiles,
  });

  /// False after I ended the turn ([onReopen] opens it again).
  final bool enabled;
  final void Function(String text) onSend;

  /// 发送完毕. Null hides it (nothing to end yet, or not mine to end in a
  /// room, §10.6).
  final VoidCallback? onEndTurn;

  /// 继续说: undo [onEndTurn] and keep writing in the same turn.
  final VoidCallback? onReopen;

  /// Room member names for "@" completion; empty in 1:1 chats.
  final List<String> mentionNames;

  /// Who I am writing to, for the placeholder.
  final String? to;

  /// The other person is waiting on me.
  final bool waitingOnMe;

  /// No connection: typing is fine, sending waits.
  final bool offline;

  /// File types the other person asked for; null when they can only
  /// take words (plain chat), which disables attaching.
  final List<String>? fileTypes;

  /// Send words with files.
  final void Function(String text, List<OutgoingFile> files)? onSendFiles;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _files = <OutgoingFile>[];
  int _pick = 0;

  bool get _canAttach => widget.fileTypes != null && widget.onSendFiles != null;

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

  bool get _hasDraft => _controller.text.trim().isNotEmpty || _files.isNotEmpty;

  bool get _canSend => widget.enabled && !widget.offline && _hasDraft;

  /// Sends the draft. Returns whether anything went.
  bool _send() {
    if (!_canSend) return false;
    final text = _controller.text.trim();
    if (_files.isNotEmpty && _canAttach) {
      widget.onSendFiles!(text, List.of(_files));
    } else if (text.isNotEmpty) {
      widget.onSend(text);
    } else {
      return false;
    }
    Haptic.sent();
    _controller.clear();
    setState(_files.clear);
    return true;
  }

  /// 发送完毕: whatever is typed goes first.
  void _finish() {
    if (widget.onEndTurn == null || !widget.enabled) return;
    if (_hasDraft && !_send()) return;
    widget.onEndTurn!();
  }

  Future<void> _attach() async {
    try {
      final picked = await FilesIo.pick(widget.fileTypes ?? const []);
      if (!mounted || picked.isEmpty) return;
      setState(() => _files.addAll(picked));
      _focus.requestFocus();
    } catch (_) {
      if (mounted) toast(context, '无法打开文件');
    }
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
        _finish();
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

  String get _hint {
    if (widget.offline) return '未连接';
    final to = widget.to;
    if (widget.mentionNames.isNotEmpty) return '消息';
    return to == null ? '消息' : '消息';
  }

  @override
  Widget build(BuildContext context) {
    final g = StreamScope.of(context);
    final touch = Touch.primary;
    final phone = g.phone;
    final pad = EdgeInsets.fromLTRB(
      g.side,
      0,
      g.side,
      // Clear a phone's home indicator.
      (phone ? Sp.x3 : Sp.x5) + MediaQuery.viewPaddingOf(context).bottom,
    );

    if (!widget.enabled) {
      return Padding(
        padding: pad,
        child: _Ended(onReopen: widget.onReopen),
      );
    }

    final sugg = _suggestions();
    final focused = _focus.hasFocus;
    final hot = widget.waitingOnMe && !widget.offline;

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      minLines: 1,
      maxLines: phone ? 5 : 8,
      textInputAction: touch ? TextInputAction.newline : TextInputAction.none,
      style: Ty.prose.copyWith(color: Dk.t1, fontSize: 14.5, height: 1.6),
      cursorColor: Dk.signal,
      cursorWidth: 2,
      onChanged: (_) => setState(() => _pick = 0),
      decoration: InputDecoration(
        hintText: _hint,
        hintStyle: Ty.prose.copyWith(
          color: Dk.t3,
          fontSize: 14.5,
          height: 1.6,
        ),
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: Sp.x1),
      ),
    );

    final bar = Row(
      children: [
        DkIconButton(
          key: const ValueKey('composer-attach'),
          glyph: Glyph.attach,
          label: _canAttach ? '添加文件' : '对方仅支持文字',
          onTap: _canAttach ? _attach : null,
        ),
        const SizedBox(width: Sp.x2),
        const Spacer(),
        if (widget.onEndTurn != null) ...[
          Tooltip(
            message: touch ? '结束本轮' : '结束本轮  ${shortcutLabel('↵')}',
            child: DkButton(
              key: const ValueKey('composer-end-turn'),
              label: '结束本轮',
              glyph: Glyph.done,
              kind: DkButtonKind.quiet,
              dense: !touch,
              onTap: widget.offline ? null : _finish,
            ),
          ),
          const SizedBox(width: Sp.x15),
        ],
        DkButton(
          key: const ValueKey('composer-send'),
          label: '发送',
          trailing: Glyph.send,
          kind: hot ? DkButtonKind.signal : DkButtonKind.primary,
          dense: !touch,
          onTap: _canSend ? _send : null,
        ),
      ],
    );

    return Padding(
      padding: pad,
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
              duration: Mo.of(context, Mo.fast),
              decoration: BoxDecoration(
                color: Dk.p2,
                borderRadius: BorderRadius.circular(Rd.lg),
                border: Border.all(
                  color: focused
                      ? Dk.focus
                      : hot
                          ? Dk.signalRing
                          : Dk.line2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Dk.bgFade,
                    blurRadius: 40,
                    offset: Offset(0, -16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_files.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.x3,
                        Sp.x3,
                        Sp.x3,
                        0,
                      ),
                      child: Wrap(
                        spacing: Sp.x15,
                        runSpacing: Sp.x15,
                        children: [
                          for (final f in _files)
                            DraftChip(
                              file: f,
                              onRemove: () => setState(() => _files.remove(f)),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      phone ? Sp.x35 : Sp.x4,
                      Sp.x3,
                      phone ? Sp.x35 : Sp.x4,
                      0,
                    ),
                    child: field,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Sp.x15,
                      Sp.x15,
                      Sp.x2,
                      Sp.x2,
                    ),
                    child: bar,
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

/// The composer after 发送完毕.
class _Ended extends StatelessWidget {
  const _Ended({required this.onReopen});
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('composer-ended'),
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
      decoration: BoxDecoration(
        color: Dk.p1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line),
      ),
      child: Row(
        children: [
          const GlyphIcon(Glyph.done, size: Sz.glyphSm, color: Dk.t3),
          const SizedBox(width: Sp.x25),
          Expanded(
            child: Text(
              '已结束本轮',
              style: Ty.small.copyWith(fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onReopen != null)
            DkButton(
              key: const ValueKey('composer-reopen'),
              label: '继续',
              kind: DkButtonKind.secondary,
              dense: !Touch.primary,
              onTap: onReopen,
            ),
        ],
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.x2),
        padding: const EdgeInsets.all(Sp.x1),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: Dk.p2,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: Dk.line2),
          boxShadow: const [BoxShadow(color: Dk.shadow, blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < names.length; i++)
              Pressable(
                key: ValueKey('mention-${names[i]}'),
                semanticLabel: '提及 ${names[i]}',
                onTap: () => onPick(names[i]),
                radius: Rd.sm,
                ring: false,
                builder: (context, s) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.x25,
                    vertical: Sp.x15,
                  ),
                  decoration: BoxDecoration(
                    color: i == picked || s.lit ? Dk.p3 : null,
                    borderRadius: BorderRadius.circular(Rd.sm),
                  ),
                  child: Row(
                    children: [
                      Text('@', style: Ty.meta.copyWith(color: Dk.signal)),
                      const SizedBox(width: Sp.x2),
                      Expanded(child: Text(names[i], style: Ty.body)),
                      if (i == picked && !Touch.primary) const Kbd('Tab'),
                    ],
                  ),
                ),
              ),
          ],
        ),
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
