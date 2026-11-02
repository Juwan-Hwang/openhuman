/// Room panel — group room controls (design doc §10.4/§10.6).
///
/// One sheet with four sections:
///   成员     member list with roles (owner badge)
///   邀请     mint / copy / revoke invite codes (owner only)
///   连接配置  Base URL `/rooms/<id>/v1`, model name, caller key minting
///             with a display name — all copyable (owner only)
///   设置     idle-release seconds + segmentation toggle (owner only)
///
/// Non-owners see the member list and the read-only connection info of
/// their own; the owner-only sections are hidden (the server enforces the
/// rule either way).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sdk_provider.dart';

class RoomPanel {
  static Future<void> show(BuildContext context, String roomId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RoomPanelSheet(roomId: roomId),
    );
  }
}

class _RoomPanelSheet extends ConsumerStatefulWidget {
  const _RoomPanelSheet({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_RoomPanelSheet> createState() => _RoomPanelSheetState();
}

class _RoomPanelSheetState extends ConsumerState<_RoomPanelSheet> {
  bool _busy = false;
  String? _lastInviteCode;
  String? _lastCallerKey;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // Room detail changed underneath — refetch.
      ref.invalidate(roomInfoProvider(widget.roomId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomAsync = ref.watch(roomInfoProvider(widget.roomId));
    final isOwner = ref.watch(roomOwnershipProvider(widget.roomId));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: roomAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (room) {
            if (room == null) {
              return const Center(child: Text('这不是一个群聊会话'));
            }
            final members =
                (room['members'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
                    const <Map<String, dynamic>>[];
            final metadata =
                (room['metadata'] as Map?)?.cast<String, dynamic>() ??
                    const <String, dynamic>{};
            final title = room['title'] as String? ?? '群聊';

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── 成员 ──
                Text('成员（${members.length}）',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final m in members)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(m['display_name'] as String? ??
                        m['human_id'] as String? ??
                        '?'),
                    trailing: m['role'] == 'owner'
                        ? const Chip(
                            label: Text('房主'),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                const Divider(height: 32),

                if (isOwner) ...[
                  // ── 邀请 ──
                  Text('邀请', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _run(() async {
                          final client = ref.read(openHumanClientProvider);
                          final res = await client.mintInvite(widget.roomId);
                          setState(() =>
                              _lastInviteCode = res['code'] as String?);
                        }),
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('生成邀请码'),
                      ),
                      if (_lastInviteCode != null) ...[
                        ActionChip(
                          label: Text(_lastInviteCode!),
                          onPressed: () => _copy('邀请码', _lastInviteCode!),
                        ),
                        TextButton(
                          onPressed: () => _run(() async {
                            final client = ref.read(openHumanClientProvider);
                            await client.revokeInvite(
                                widget.roomId, _lastInviteCode!);
                            setState(() => _lastInviteCode = null);
                          }),
                          child: const Text('作废'),
                        ),
                      ],
                    ],
                  ),
                  const Divider(height: 32),

                  // ── 连接配置 ──
                  Text('连接配置', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _CopyRow(
                    label: 'Base URL',
                    value: '/rooms/${widget.roomId}/v1',
                    onCopy: _copy,
                  ),
                  _CopyRow(
                    label: 'Model',
                    value: title,
                    onCopy: _copy,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _mintCallerKey(context),
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('生成 caller key'),
                  ),
                  if (_lastCallerKey != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lastCallerKey!,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () =>
                                _copy('caller key', _lastCallerKey!),
                            tooltip: '复制（只显示这一次）',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 32),

                  // ── 设置 ──
                  Text('房间设置', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _SettingsEditor(
                    idleSecs: metadata['room_idle_secs'] as int?,
                    segmented: metadata['room_segmented'] as bool?,
                    onSave: (idle, seg) => _run(() async {
                      final client = ref.read(openHumanClientProvider);
                      await client.updateRoomSettings(
                        widget.roomId,
                        idleSecs: idle,
                        segmented: seg,
                      );
                    }),
                  ),
                ] else ...[
                  Text(
                    '邀请、连接配置与房间设置仅房主可见。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _mintCallerKey(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('生成 caller key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '显示名，如「小明的 Claude Code」'),
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
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _run(() async {
      final client = ref.read(openHumanClientProvider);
      final res = await client.mintCallerKey(widget.roomId, name);
      setState(() => _lastCallerKey = res['api_key'] as String?);
    });
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            onPressed: () => onCopy(label, value),
            tooltip: '复制',
          ),
        ],
      ),
    );
  }
}

class _SettingsEditor extends StatefulWidget {
  const _SettingsEditor({
    required this.idleSecs,
    required this.segmented,
    required this.onSave,
  });

  final int? idleSecs;
  final bool? segmented;
  final void Function(int idleSecs, bool segmented) onSave;

  @override
  State<_SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<_SettingsEditor> {
  late final TextEditingController _idle = TextEditingController(
    text: (widget.idleSecs ?? 60).toString(),
  );
  late bool _segmented = widget.segmented ?? true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 120, child: Text('空闲释放秒数')),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _idle,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('分段模式'),
          subtitle: const Text('关闭后退回普通持续流（降级）'),
          value: _segmented,
          onChanged: (v) => setState(() => _segmented = v),
        ),
        FilledButton(
          onPressed: () =>
              widget.onSave(int.tryParse(_idle.text) ?? 60, _segmented),
          child: const Text('保存设置'),
        ),
      ],
    );
  }
}
