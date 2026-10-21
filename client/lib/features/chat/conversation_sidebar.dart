/// Conversation Sidebar — shows all active conversations (like a friend list).
///
/// Clicking a conversation switches the active view to that conversation's
/// messages and agent runtime data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../app/theme.dart';
import '../../core/sdk_provider.dart';

class ConversationSidebar extends ConsumerWidget {
  const ConversationSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(conversationListProvider);
    final conversations = listState.entries;
    final activeId = ref.watch(activeConversationIdProvider);
    // The socket gates the history fetch, so "not loaded yet" usually
    // means "not connected yet" — worth saying rather than spinning.
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ?? oh.ConnectionState.idle;
    final theme = Theme.of(context);

    // A card resting on the surface rather than a panel bolted to the
    // edge: inset from the window, rounded, and outlined instead of
    // separated by a divider that runs the full height.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: SizedBox(
        width: 268,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Icon(Icons.forum_outlined,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('会话', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Text('${conversations.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
          // ── Trash ──
          _TrashButton(theme: theme, onOpen: () => _openTrash(context)),
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
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      final isActive = conv.id == activeId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _ConversationTile(
                          conversation: conv,
                          isActive: isActive,
                          theme: theme,
                          onTap: () {
                            ref.read(conversationListProvider.notifier)
                                .selectConversation(conv.id);
                          },
                          onRename: () => _askForName(context, ref, conv),
                          onDelete: () => _confirmDelete(context, ref, conv),
                          onSave: () async {
                            final ok = await ref
                                .read(conversationListProvider.notifier)
                                .saveConversation(conv.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? '会话记录已保存' : '保存失败'),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Open the trash as a sheet over the console.
Future<void> _openTrash(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _TrashSheet(),
  );
}

class _TrashButton extends StatelessWidget {
  const _TrashButton({required this.theme, required this.onOpen});

  final ThemeData theme;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onOpen,
      icon: const Icon(Icons.restore_from_trash, size: 16),
      label: const Text('回收站'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: theme.textTheme.bodySmall,
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

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('回收站', style: theme.textTheme.titleSmall),
            ),
            // An unreachable trash must not read as an empty one: "空的"
            // invites the reader to think their conversations are gone
            // for good, and invites a pointless retry loop.
            if (trash.entries.isEmpty)
              Expanded(
                child: _TrashPlaceholder(
                  theme: theme,
                  status: trash.status,
                  error: trash.error,
                  onRetry: () =>
                      ref.read(trashListProvider.notifier).refresh(),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: trash.entries.length,
                  itemBuilder: (context, index) {
                    final item = trash.entries[index];
                    return ListTile(
                      leading: const Icon(Icons.restore_from_trash, size: 20),
                      title: Text(item.agentName),
                      subtitle: Text(
                        item.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore, size: 20),
                            tooltip: '恢复',
                            onPressed: () async {
                              final ok = await ref
                                  .read(trashListProvider.notifier)
                                  .restore(item.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '已恢复' : '恢复失败'),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever, size: 20),
                            tooltip: '彻底删除',
                            onPressed: () async {
                              final confirmed =
                                  await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('彻底删除'),
                                  content: const Text(
                                    '这条对话会被永久删除，无法恢复。',
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
                              await ref
                                  .read(trashListProvider.notifier)
                                  .destroy(item.id);
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
      ),
    );
  }
}

/// Ask for a new agent name and apply it.
///
/// The name belongs to the agent, not the conversation, so every
/// conversation with that agent changes — which is what the prompt says.
Future<void> _askForName(
  BuildContext context,
  WidgetRef ref,
  ConversationInfo conversation,
) async {
  final controller = TextEditingController(text: conversation.agentName);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 64,
        decoration: const InputDecoration(
          labelText: '名称',
          helperText: '该 agent 的所有对话都会用这个名字',
        ),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
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

  final ok = await ref
      .read(conversationListProvider.notifier)
      .renameAgent(conversation.agentId, trimmed);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(ok ? '已重命名为「$trimmed」' : '重命名失败'),
    ),
  );
}

/// Confirm before moving a conversation to the trash.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  ConversationInfo conversation,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('移到回收站'),
      content: Text('「${conversation.agentName}」的这段对话会被移到回收站，可以恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('移到回收站'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final ok = await ref
      .read(conversationListProvider.notifier)
      .trash(conversation.id);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? '已移到回收站' : '删除失败')),
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
          title: '正在加载会话…',
          loading: true,
        );

      case ConversationListStatus.error:
        return _CenteredNote(
          theme: theme,
          icon: Icons.cloud_off_outlined,
          title: listState.error ?? '加载失败',
          subtitle: '网络可能不太稳定，可以重试',
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
          title: '还没有会话',
          subtitle: '当 agent 发来消息时，会话会出现在这里',
        );

      case ConversationListStatus.idle:
        // History is fetched only once the socket connects. Until then the
        // fetch has not started, and spinning here would imply otherwise.
        return _CenteredNote(
          theme: theme,
          icon: _connIcon,
          title: _connTitle,
          subtitle: connState == oh.ConnectionState.connecting ||
                  connState == oh.ConnectionState.reconnecting
              ? '连上之后会自动加载'
              : '检查网络或点右上角重连',
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
        return '等待连接';
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
          title: '正在加载回收站…',
          loading: true,
        );

      case ConversationListStatus.error:
        return _CenteredNote(
          theme: theme,
          icon: Icons.cloud_off_outlined,
          title: error ?? '加载失败',
          subtitle: '没能读取回收站，内容没有丢',
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
          title: '回收站是空的',
          subtitle: '移到回收站的对话会保留在这里',
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
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

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
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (icon != null)
              Icon(
                icon,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: style),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: style?.copyWith(fontSize: 12),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.theme,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onSave,
  });

  final ConversationInfo conversation;
  final bool isActive;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          // The active row reads as a raised card inside the card, not as
          // a stripe down the edge.
          color: isActive ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.outlineVariant
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Avatar circle with first letter of agent name
            CircleAvatar(
              radius: 16,
              backgroundColor: isActive
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                conversation.agentName.isNotEmpty
                    ? conversation.agentName[0].toUpperCase()
                    : '?',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.agentName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conversation.lastMessage != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      conversation.lastMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Only offered on the open conversation: a menu on every row
            // turns the list into a wall of dots and makes the target
            // easy to miss.
            if (isActive)
              PopupMenuButton<String>(
                iconSize: 18,
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'rename') {
                    onRename();
                  } else if (value == 'save') {
                    onSave();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  // Messages are not kept on the server unless saved.
                  PopupMenuItem(value: 'save', child: Text('保存会话记录')),
                  PopupMenuItem(value: 'delete', child: Text('移到回收站')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
