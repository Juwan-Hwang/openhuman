/// Room composer & mention rendering (design doc §10.4).
///
/// `RoomComposer` replaces the default chat input in group rooms: typing
/// "@" opens member-name completion above the field; picking a name
/// inserts "@名字 ". `buildMentionTextMessage` is the matching
/// `textMessageBuilder`: "@名字" spans that match a room member render
/// highlighted; messages without mentions fall back to the library's
/// default bubble.
library;

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sdk_provider.dart';

/// Member display names of a room, for completion + highlight.
List<String> roomMemberNames(Map<String, dynamic>? room) {
  final members = (room?['members'] as List?) ?? const [];
  return members
      .whereType<Map<String, dynamic>>()
      .map((m) => m['display_name'] as String? ?? '')
      .where((n) => n.isNotEmpty)
      .toList();
}

class RoomComposer extends ConsumerStatefulWidget {
  const RoomComposer({
    super.key,
    required this.roomId,
    required this.enabled,
    required this.onSend,
  });

  final String roomId;
  final bool enabled;
  final void Function(String text) onSend;

  @override
  ConsumerState<RoomComposer> createState() => _RoomComposerState();
}

class _RoomComposerState extends ConsumerState<RoomComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// The "@..." token under the caret, if any: (start index, query).
  (int, String)? _activeToken() {
    final text = _controller.text;
    var caret = _controller.selection.baseOffset;
    if (caret < 0 || caret > text.length) caret = text.length;
    final before = text.substring(0, caret);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    // "@" must start the text or follow whitespace.
    if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
    final query = before.substring(at + 1);
    if (query.contains(' ') || query.contains('\n')) return null;
    return (at, query);
  }

  void _pick(String name) {
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
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = ref.watch(roomInfoProvider(widget.roomId)).valueOrNull;
    final names = roomMemberNames(room);
    final token = _activeToken();
    final suggestions = token == null
        ? const <String>[]
        : names
            .where(
              (n) =>
                  token.$2.isEmpty ||
                  n.toLowerCase().contains(token.$2.toLowerCase()),
            )
            .take(5)
            .toList();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final n in suggestions)
                    InkWell(
                      key: ValueKey('mention-$n'),
                      onTap: () => _pick(n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.alternate_email, size: 14),
                            const SizedBox(width: 8),
                            Text(n, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: widget.enabled ? '发消息，@ 可唤起成员' : '回合已结束',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.enabled
                      ? () {
                          final text = _controller.text.trim();
                          if (text.isEmpty) return;
                          widget.onSend(text);
                          _controller.clear();
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  tooltip: '发送',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A textMessageBuilder that highlights "@member" spans (§10.4).
/// Non-mention messages render with the library default bubble.
Widget buildMentionTextMessage(
  BuildContext context,
  types.TextMessage message, {
  required int messageWidth,
  required bool showName,
  required List<String> memberNames,
}) {
  final spans = mentionSpans(message.text, memberNames);
  final hasMention = spans.any((s) => s.isMention);
  if (!hasMention) {
    return ui.TextMessage(
      emojiEnlargementBehavior: ui.EmojiEnlargementBehavior.multi,
      hideBackgroundOnEmojiMessages: true,
      message: message,
      showName: showName,
      usePreviewData: false,
    );
  }

  final theme = Theme.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final highlight = theme.colorScheme.primary;
  final body = theme.textTheme.bodyMedium?.copyWith(
    color: isDark ? Colors.white : Colors.black87,
  );

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              message.author.firstName ?? '',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Container(
          constraints: BoxConstraints(maxWidth: messageWidth.toDouble()),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text.rich(
            TextSpan(
              style: body,
              children: [
                for (final s in spans)
                  TextSpan(
                    text: s.text,
                    style: s.isMention
                        ? body?.copyWith(
                            color: highlight,
                            fontWeight: FontWeight.w700,
                          )
                        : body,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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
