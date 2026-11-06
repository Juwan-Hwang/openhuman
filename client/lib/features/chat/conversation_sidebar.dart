/// Conversation Sidebar — shows all active conversations (like a friend list).
///
/// Clicking a conversation switches the active view to that conversation's
/// messages and agent runtime data.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../app/theme.dart';
import '../../core/sdk_provider.dart';
import '../../app/adaptive.dart';
import '../../widgets/brand.dart';
import '../../widgets/avatar.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/sheet.dart';
import '../../core/identity.dart';
import '../files/file_library.dart';
import '../../widgets/haptics.dart';
import 'stream/message_stream.dart' show beijing;

/// Sidebar width limits; the pane is resizable from its right edge.
const double kSidebarMin = 232;
const double kSidebarMax = 400;
const double kSidebarDefault = 284;

/// Keyboard focus target for the sidebar's filter, so Ctrl/⌘+K anywhere
/// in the console can jump to it.
final sidebarSearchFocus = FocusNode(debugLabel: 'sidebar-search');

class ConversationSidebar extends ConsumerStatefulWidget {
  const ConversationSidebar({
    super.key,
    this.width = kSidebarDefault,
    this.onPicked,
  });

  final double width;

  /// Called after a conversation is opened from the list, so a phone
  /// layout can move from the list to the stream.
  final VoidCallback? onPicked;

  @override
  ConsumerState<ConversationSidebar> createState() =>
      _ConversationSidebarState();
}

class _ConversationSidebarState extends ConsumerState<ConversationSidebar> {
  final _query = TextEditingController();
  int _cursor = -1;

  List<ConversationInfo> _filter(List<ConversationInfo> all) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (c) =>
              c.displayName.toLowerCase().contains(q) ||
              (c.lastMessage ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  KeyEventResult _onSearchKey(
    FocusNode node,
    KeyEvent e,
    List<ConversationInfo> shown,
  ) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && shown.isNotEmpty) {
      setState(() => _cursor = (_cursor + 1) % shown.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && shown.isNotEmpty) {
      setState(
        () => _cursor = (_cursor - 1 + shown.length) % shown.length,
      );
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && shown.isNotEmpty) {
      final pick = shown[_cursor < 0 ? 0 : _cursor];
      ref.read(conversationListProvider.notifier).selectConversation(pick.id);
      widget.onPicked?.call();
      _query.clear();
      setState(() => _cursor = -1);
      node.unfocus();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _query.clear();
      setState(() => _cursor = -1);
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(conversationListProvider);
    final conversations = listState.entries;
    final shown = _filter(conversations);
    final activeId = ref.watch(activeConversationIdProvider);
    // The socket gates the history fetch, so "not loaded yet" usually
    // means "not connected yet" — worth saying rather than spinning.
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        oh.ConnectionState.idle;
    final theme = Theme.of(context);
    final groups = shown.where((c) => c.isGroup).toList();
    final direct = shown.where((c) => !c.isGroup).toList();
    final ordered = [...direct, ...groups];

    Widget tile(ConversationInfo conv) {
      final i = ordered.indexOf(conv);
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _ConversationTile(
          key: ValueKey('conv-${conv.id}'),
          conversation: conv,
          isActive: conv.id == activeId,
          isCursor: i == _cursor,
          onTap: () {
            ref
                .read(conversationListProvider.notifier)
                .selectConversation(conv.id);
            widget.onPicked?.call();
          },
          onRename: () => askForName(context, ref, conv),
          onDelete: () => confirmTrash(context, ref, conv),
          onSave: () async {
            final ok = await ref
                .read(conversationListProvider.notifier)
                .saveConversation(conv.id);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? '已保存' : '无法保存')),
            );
          },
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      child: ColoredBox(
        color: Dk.p1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Phone: the list is the home screen, so it wears the brand.
            if (widget.onPicked != null)
              Container(
                height: 60,
                padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, 0),
                alignment: Alignment.centerLeft,
                child: const BrandLockup(height: 20, wink: BrandWink.once),
              ),
            // ── Filter: sits in a header as tall as the stream's top bar,
            // so the two hairlines meet across the divider.
            Container(
              height: widget.onPicked != null ? 64 : 72,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Dk.line)),
              ),
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (node, e) =>
                    _onSearchKey(sidebarSearchFocus, e, ordered),
                child: _SearchField(
                  controller: _query,
                  onChanged: () => setState(() => _cursor = -1),
                ),
              ),
            ),
            const SizedBox(height: Sp.x2),
            // ── Conversation list ──
            Expanded(
              child: conversations.isEmpty
                  ? _ListPlaceholder(
                      theme: theme,
                      listState: listState,
                      connState: connState,
                      onRetry: () =>
                          ref.read(conversationListProvider.notifier).retry(),
                    )
                  : shown.isEmpty
                      ? _CenteredNote(
                          theme: theme,
                          icon: Icons.search_off_rounded,
                          title: '无结果',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          children: [
                            if (direct.isNotEmpty) ...[
                              _SectionLabel('对话', direct.length),
                              for (final c in direct) tile(c),
                            ],
                            if (groups.isNotEmpty) ...[
                              const SizedBox(height: Sp.x2),
                              _SectionLabel('群聊', groups.length),
                              for (final c in groups) tile(c),
                            ],
                          ],
                        ),
            ),
            // ── Footer ──
            Container(
              padding: EdgeInsets.fromLTRB(
                6,
                6,
                6,
                8 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Dk.line)),
              ),
              child: Row(
                children: [
                  _CreateRoomButton(onPicked: widget.onPicked),
                  _FootButton(
                    key: const ValueKey('join-room'),
                    icon: Icons.login_rounded,
                    label: '加入',
                    tooltip: '加入群聊',
                    onTap: () => joinRoomByCode(
                      context,
                      ref,
                      onPicked: widget.onPicked,
                    ),
                  ),
                  const Spacer(),
                  DkIconButton(
                    key: const ValueKey('open-files'),
                    glyph: Glyph.folder,
                    label: '文件',
                    glyphSize: Sz.glyphSm,
                    onTap: () => FileLibrarySheet.show(context),
                  ),
                  DkIconButton(
                    key: const ValueKey('open-trash'),
                    glyph: Glyph.trash,
                    label: '废纸篓',
                    glyphSize: Sz.glyphSm,
                    onTap: () => _openTrash(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final touch = Touch.primary;
    return SizedBox(
      height: touch ? 42 : 34,
      child: TextField(
        controller: controller,
        focusNode: sidebarSearchFocus,
        onChanged: (_) => onChanged(),
        style: Ty.small.copyWith(color: Dk.t1, fontSize: 13),
        cursorColor: Dk.signal,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Dk.bg,
          hintText: '搜索',
          hintStyle: Ty.small.copyWith(color: Dk.t3, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Dk.t3),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          suffixIcon: touch
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: Dk.line2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          Text('Ctrl K', style: Ty.meta.copyWith(fontSize: 10)),
                    ),
                  ),
                ),
          contentPadding: EdgeInsets.symmetric(vertical: touch ? 12 : 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rd.md),
            borderSide: const BorderSide(color: Dk.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rd.md),
            borderSide: const BorderSide(color: Dk.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rd.md),
            borderSide: const BorderSide(color: Dk.t4),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          Text(label, style: Ty.label),
          const SizedBox(width: 6),
          Text('$count', style: Ty.meta.copyWith(color: Dk.t4)),
        ],
      ),
    );
  }
}

/// Join a room with an invite code someone sent (§10.5), then open it.
Future<void> joinRoomByCode(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onPicked,
}) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('加入群聊'),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('join-code'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: Ty.code.copyWith(fontSize: 15, letterSpacing: 1.2),
          decoration: const InputDecoration(
            hintText: '邀请码',
          ),
          onSubmitted: (v) => Navigator.of(c).pop(v.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(controller.text.trim()),
          child: const Text('加入'),
        ),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;
  try {
    final room = await ref.read(openHumanClientProvider).acceptInvite(code);
    final id = (room['id'] ?? room['room_id']) as String?;
    await ref.read(conversationListProvider.notifier).retry();
    if (id != null) {
      ref.read(conversationListProvider.notifier).selectConversation(id);
      onPicked?.call();
    }
    if (context.mounted) {
      final title = room['title'] as String?;
      toast(context, title == null ? '已加入' : '已加入“$title”');
    }
  } catch (e) {
    if (!context.mounted) return;
    final t = e.toString();
    toast(
      context,
      t.contains('404') || t.contains('not_found') || t.contains('invalid')
          ? '邀请码无效'
          : t.contains('full')
              ? '群聊已满'
              : '无法加入，请稍后再试',
    );
  }
}

/// Open the trash as a sheet over the console.
Future<void> _openTrash(BuildContext context) {
  return showDkSheet<void>(
    context,
    maxWidth: 640,
    builder: (sheetContext) => const _TrashSheet(),
  );
}

/// Create a group room (§10.5): name it, then it appears in the list.
class _CreateRoomButton extends ConsumerWidget {
  const _CreateRoomButton({this.onPicked});
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FootButton(
      icon: Icons.group_add_outlined,
      label: '新建群聊',
      tooltip: '新建群聊',
      onTap: () => _createRoom(context, ref),
    );
  }

  Future<void> _createRoom(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建群聊'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名称'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final client = ref.read(openHumanClientProvider);
      final room = await client.createRoom(name);
      final roomId = room['id'] as String?;
      ref.read(conversationListProvider.notifier).retry();
      if (roomId != null) {
        ref.read(activeConversationIdProvider.notifier).state = roomId;
        onPicked?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法创建：$e')),
        );
      }
    }
  }
}

class _FootButton extends StatelessWidget {
  const _FootButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = _button();
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }

  Widget _button() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.md),
        hoverColor: Dk.p2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Dk.t2),
              const SizedBox(width: 8),
              Text(label, style: Ty.small.copyWith(color: Dk.t2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trash: restore what was discarded, or destroy it for good.
class _TrashSheet extends ConsumerStatefulWidget {
  const _TrashSheet();

  @override
  ConsumerState<_TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends ConsumerState<_TrashSheet> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the notifier can be read safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(trashListProvider.notifier).loadIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final trash = ref.watch(trashListProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(trashListProvider.notifier);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x2, Sp.x3, Sp.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('废纸篓', style: Ty.title.copyWith(fontSize: 18)),
                    ],
                  ),
                ),
                DkIconButton(
                  glyph: Glyph.close,
                  label: '关闭',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // An unreachable trash must not read as an empty one: "空的"
          // invites the reader to think their conversations are gone
          // for good, and invites a pointless retry loop.
          Expanded(
            child: trash.entries.isEmpty
                ? _TrashPlaceholder(
                    theme: theme,
                    status: trash.status,
                    error: trash.error,
                    onRetry: () => notifier.refresh(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x5),
                    itemCount: trash.entries.length,
                    itemBuilder: (context, index) {
                      final item = trash.entries[index];
                      final caller = Caller.parse(item.agentName);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sp.x2,
                          vertical: Sp.x2,
                        ),
                        child: Row(
                          children: [
                            PersonAvatar(
                              name: caller.name,
                              anonymous: caller.anonymous,
                              size: Sz.avatarSm,
                            ),
                            const SizedBox(width: Sp.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    caller.name,
                                    style: Ty.name.copyWith(color: Dk.t1Soft),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // Unnamed callers are told apart by
                                  // what the server calls them.
                                  if ((caller.via ??
                                          (caller.anonymous
                                              ? caller.raw
                                              : null)) !=
                                      null)
                                    Text(
                                      caller.via ?? caller.raw,
                                      style: Ty.small.copyWith(
                                        fontSize: 11.5,
                                        color: Dk.t3,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            DkButton(
                              label: '恢复',
                              glyph: Glyph.restore,
                              dense: true,
                              onTap: () async {
                                final ok = await notifier.restore(item.id);
                                if (!context.mounted) return;
                                toast(context, ok ? '已恢复' : '无法恢复');
                              },
                            ),
                            const SizedBox(width: Sp.x1),
                            DkIconButton(
                              glyph: Glyph.trash,
                              label: '永久删除',
                              color: Dk.danger,
                              glyphSize: Sz.glyphSm,
                              onTap: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('永久删除'),
                                    content: const Text(
                                      '此操作无法撤销。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                        child: const Text('永久删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !context.mounted) {
                                  return;
                                }
                                await notifier.destroy(item.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Ask for a remark name — what this person is called here — and apply it.
///
/// The name belongs to the caller, not the conversation, so every
/// conversation with them follows. The tool they write from is kept, so
/// the header still says "经由 Cursor" after a rename.
Future<void> askForName(
  BuildContext context,
  WidgetRef ref,
  ConversationInfo conversation,
) async {
  final caller = conversation.caller;
  final controller = TextEditingController(
    text: caller.anonymous ? '' : caller.name,
  );
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('编辑名称'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: '名称',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );

  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || !context.mounted) return;
  if (trimmed == caller.name) return;

  final stored = remarkToStoredName(trimmed, caller.tool);
  final ok = await ref
      .read(conversationListProvider.notifier)
      .renameAgent(conversation.agentId, stored);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? '已更新' : '无法更新，请稍后再试')),
  );
}

/// The name the server keeps for a remark: the person, then the tool
/// they write from, in the form [Caller.parse] reads back.
String remarkToStoredName(String remark, String? tool) =>
    tool == null ? remark : '$remark via $tool';

/// Confirm before moving a conversation to the trash.
Future<void> confirmTrash(
  BuildContext context,
  WidgetRef ref,
  ConversationInfo conversation,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('移到废纸篓'),
      content: const Text('可在废纸篓中恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('移到废纸篓'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final ok =
      await ref.read(conversationListProvider.notifier).trash(conversation.id);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? '已移到废纸篓' : '无法删除')),
  );
}

/// What the list area shows when there is nothing to list.
///
/// Four situations render an empty list and must not look alike: never
/// asked, still asking, failed, and genuinely empty. Collapsing them is
/// what made this sidebar spin forever — a request that gave up still
/// read as "loading", and one that never started read the same way.
class _ListPlaceholder extends StatelessWidget {
  const _ListPlaceholder({
    required this.theme,
    required this.listState,
    required this.connState,
    required this.onRetry,
  });

  final ThemeData theme;
  final ConversationListState listState;
  final oh.ConnectionState connState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (listState.status) {
      case ConversationListStatus.loading:
        return _CenteredNote(
          theme: theme,
          title: '正在加载…',
          loading: true,
        );

      case ConversationListStatus.error:
        return _CenteredNote(
          theme: theme,
          icon: Icons.cloud_off_outlined,
          title: listState.error ?? '无法加载',
          action: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
          ),
        );

      case ConversationListStatus.ready:
        return _CenteredNote(
          theme: theme,
          icon: Icons.forum_outlined,
          title: '没有对话',
          subtitle: '分享联系方式，即可收到消息。',
        );

      case ConversationListStatus.idle:
        // History is fetched only once the socket connects. Until then the
        // fetch has not started, and spinning here would imply otherwise.
        return _CenteredNote(
          theme: theme,
          icon: _connIcon,
          title: _connTitle,
          action: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
          ),
        );
    }
  }

  IconData get _connIcon {
    switch (connState) {
      case oh.ConnectionState.connecting:
      case oh.ConnectionState.reconnecting:
        return Icons.sync;
      case oh.ConnectionState.error:
      case oh.ConnectionState.disconnected:
        return Icons.cloud_off_outlined;
      case oh.ConnectionState.idle:
      case oh.ConnectionState.connected:
        return Icons.hourglass_empty;
    }
  }

  String get _connTitle {
    switch (connState) {
      case oh.ConnectionState.connecting:
        return '正在连接…';
      case oh.ConnectionState.reconnecting:
        return '正在重新连接…';
      case oh.ConnectionState.error:
      case oh.ConnectionState.disconnected:
        return '未连接';
      case oh.ConnectionState.idle:
      case oh.ConnectionState.connected:
        return '未连接';
    }
  }
}

/// What the trash shows while it holds nothing.
///
/// Reuses [_CenteredNote] so the wording differs but the layout does not.
class _TrashPlaceholder extends StatelessWidget {
  const _TrashPlaceholder({
    required this.theme,
    required this.status,
    required this.error,
    required this.onRetry,
  });

  final ThemeData theme;
  final ConversationListStatus status;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ConversationListStatus.loading:
      case ConversationListStatus.idle:
        return _CenteredNote(
          theme: theme,
          title: '正在加载…',
          loading: true,
        );

      case ConversationListStatus.error:
        return _CenteredNote(
          theme: theme,
          icon: Icons.cloud_off_outlined,
          title: error ?? '无法加载',
          action: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
          ),
        );

      case ConversationListStatus.ready:
        return _CenteredNote(
          theme: theme,
          icon: Icons.delete_outline,
          title: '废纸篓为空',
        );
    }
  }
}

/// A centred message with an optional icon and an optional button.
///
/// Shared by all four placeholder states so they share spacing and type
/// scale — the wording is what should differ, not the layout.
class _CenteredNote extends StatelessWidget {
  const _CenteredNote({
    required this.theme,
    required this.title,
    this.icon,
    this.subtitle,
    this.action,
    this.loading = false,
  });

  final ThemeData theme;
  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? action;

  /// Show a spinner instead of an icon. Only for a request that is
  /// genuinely still in flight — a spinner that outlives its request is
  /// the bug this whole state split exists to prevent.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final style = Ty.small.copyWith(color: Dk.t2);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Dk.t2,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20, color: Dk.t3),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: style),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: style.copyWith(fontSize: 12, color: Dk.t3),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

/// One line of a message for a list row: Markdown marks dropped,
/// whitespace collapsed.
String previewText(String text) => text
    .replaceAll(RegExp(r'```[^\n]*'), ' ')
    .replaceAll(RegExp(r'[`*#>]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Short, glanceable time for a list row.
String rowTime(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final n = DateTime(now.year, now.month, now.day);
  final diff = n.difference(d).inDays;
  if (diff == 0) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return '昨天';
  if (diff < 7) {
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][t.weekday - 1];
  }
  return '${t.month}/${t.day}';
}

class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.isCursor,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onSave,
  });

  final ConversationInfo conversation;
  final bool isActive;

  /// Highlighted by the keyboard while filtering.
  final bool isCursor;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hover = false;
  bool _menuOpen = false;

  Future<void> _menu(Offset at) async {
    Haptic.menu();
    setState(() => _menuOpen = true);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'rename', height: 36, child: Text('编辑名称')),
        // Messages are not kept on the server unless saved.
        PopupMenuItem(value: 'save', height: 36, child: Text('保存记录')),
        PopupMenuDivider(height: 8),
        PopupMenuItem(value: 'delete', height: 36, child: Text('移到废纸篓')),
      ],
    );
    if (mounted) setState(() => _menuOpen = false);
    switch (value) {
      case 'rename':
        widget.onRename();
      case 'save':
        widget.onSave();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final active = widget.isActive;
    final lit = active || widget.isCursor;
    // A phone has no hover: its row menu opens on a long press, and the
    // row keeps showing its time.
    final touch = Touch.primary;
    final showMenu = touch ? _menuOpen : (_hover || _menuOpen);
    final time = c.lastMessageTime == null
        ? null
        : rowTime(
            beijing(c.lastMessageTime!.millisecondsSinceEpoch),
            beijing(DateTime.now().millisecondsSinceEpoch),
          );
    // Someone is waiting on me here, or wrote while I was elsewhere: the
    // row is "hot", which is the only time it gets brighter than its
    // neighbours.
    final waiting = c.waiting && !active && !c.lastFailed;
    final hot = waiting || c.unread > 0;
    final preview = rowPreview(c);
    final Widget? badge = c.unread > 0
        ? _UnreadPill(count: c.unread, signal: c.waiting)
        : waiting
            ? const _WaitingTag()
            : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(d.globalPosition),
        onLongPressStart: touch ? (d) => _menu(d.globalPosition) : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(Rd.md),
            hoverColor: Dk.p2,
            splashFactory: NoSplash.splashFactory,
            child: AnimatedContainer(
              duration: Mo.fast,
              padding: touch
                  ? const EdgeInsets.fromLTRB(12, 12, 10, 12)
                  : const EdgeInsets.fromLTRB(10, 9, 6, 9),
              decoration: BoxDecoration(
                color: lit ? Dk.p3 : Colors.transparent,
                borderRadius: BorderRadius.circular(Rd.md),
              ),
              child: Row(
                children: [
                  c.isGroup
                      ? RoomAvatar(
                          title: c.displayName,
                          size: touch ? 34 : 30,
                        )
                      : PersonAvatar(
                          name: c.displayName,
                          anonymous: c.caller.anonymous,
                          size: touch ? 34 : 30,
                        ),
                  SizedBox(width: touch ? 14 : 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      c.displayName,
                                      style: Ty.name.copyWith(
                                        color:
                                            active || hot ? Dk.t1 : Dk.t1Soft,
                                        fontWeight: hot
                                            ? FontWeight.w700
                                            : Ty.name.fontWeight,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (c.isGroup && c.memberCount != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '${c.memberCount}人',
                                      style: Ty.small.copyWith(
                                        fontSize: 11.5,
                                        color: Dk.t3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 18,
                              child: showMenu
                                  ? Builder(
                                      builder: (bctx) => _RowMenuButton(
                                        key: ValueKey('conv-menu-${c.id}'),
                                        onPressed: () {
                                          final box = bctx.findRenderObject()
                                              as RenderBox;
                                          _menu(
                                            box.localToGlobal(
                                              Offset(0, box.size.height),
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : time == null
                                      ? null
                                      : Center(
                                          widthFactor: 1,
                                          child: Text(
                                            time,
                                            style: Ty.meta.copyWith(
                                              fontSize: 10.5,
                                              color: hot ? Dk.t2 : Dk.t3,
                                            ),
                                          ),
                                        ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                key: ValueKey('conv-preview-${c.id}'),
                                style: Ty.small.copyWith(
                                  fontSize: 12,
                                  color: c.lastFailed
                                      ? Dk.dangerInk
                                      : (hot || active ? Dk.t2 : Dk.t3),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              badge,
                            ],
                          ],
                        ),
                      ],
                    ),
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

/// What a row shows under the name: my own last word is marked as mine,
/// an open task says so, and nothing at all reads as "no messages yet".
String rowPreview(ConversationInfo c) {
  final raw = c.lastMessage == null ? '' : previewText(c.lastMessage!);
  if (raw.isEmpty) {
    if (c.task != null) return '请求';
    if (c.isGroup) return '群聊';
    final via = c.caller.tool;
    return via == null ? '' : '通过 $via';
  }
  if (c.lastFailed) return '未发送：$raw';
  return c.lastFromMe ? '你：$raw' : raw;
}

/// How many messages came in while I was away. Apricot when someone is
/// also waiting on an answer, quiet otherwise.
class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count, required this.signal});
  final int count;
  final bool signal;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      key: const ValueKey('conv-unread'),
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: signal ? Dk.signal : Dk.p4,
        borderRadius: BorderRadius.circular(Rd.pill),
      ),
      child: Text(
        label,
        style: Ty.meta.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1,
          color: signal ? Dk.signalInk : Dk.t1,
        ),
      ),
    );
  }
}

/// Read, but still unanswered: a small apricot "等你" with a dot.
class _WaitingTag extends StatelessWidget {
  const _WaitingTag();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('conv-waiting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Sz.dotSm,
          height: Sz.dotSm,
          decoration:
              const BoxDecoration(color: Dk.signal, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '待回复',
          style: Ty.meta.copyWith(
            fontSize: 10.5,
            color: Dk.signal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RowMenuButton extends StatelessWidget {
  const _RowMenuButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '更多',
      child: InkResponse(
        onTap: onPressed,
        radius: 14,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.more_horiz_rounded, size: 16, color: Dk.t2),
        ),
      ),
    );
  }
}
