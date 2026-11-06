/// Room panel — group room controls (design doc §10.4/§10.6).
///
/// One sheet with four sections:
///   成员     member list with roles (owner badge)
///   邀请     mint / copy / revoke invite codes (owner only)
///   连接配置  Base URL `/rooms/<id>/v1`, model name, caller key minting
///             with a display name — all copyable (owner only)
///   已连接的 AI  each caller session with its declared tools; the owner
///             runs a tool on exactly the session they pick (owner only)
///   设置     idle-release seconds + segmentation toggle (owner only)
///
/// Non-owners see the member list and the read-only connection info of
/// their own; the owner-only sections are hidden (the server enforces the
/// rule either way).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sdk_provider.dart';
import '../../widgets/avatar.dart';
import '../../widgets/sheet.dart';

class RoomPanel {
  static Future<void> show(BuildContext context, String roomId) {
    return showDkSheet<void>(
      context,
      maxWidth: 680,
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
    final roomAsync = ref.watch(roomInfoProvider(widget.roomId));
    final isOwner = ref.watch(roomOwnershipProvider(widget.roomId));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: roomAsync.when(
          loading: () => Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: Dk.t2),
            ),
          ),
          error: (e, _) => Center(child: Text('无法加载：$e')),
          data: (room) {
            if (room == null) {
              return const Center(child: Text('不是群聊'));
            }
            final members = (room['members'] as List?)
                    ?.whereType<Map<String, dynamic>>()
                    .toList() ??
                const <Map<String, dynamic>>[];
            final metadata =
                (room['metadata'] as Map?)?.cast<String, dynamic>() ??
                    const <String, dynamic>{};
            final title = room['title'] as String? ?? '群聊';

            return ListView(
              padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x2, Sp.x6, Sp.x6),
              children: [
                Row(
                  children: [
                    Text(title, style: Ty.title.copyWith(fontSize: 16)),
                    const Spacer(),
                    if (_busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: Dk.t2,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── 成员 ──
                Text('成员（${members.length}）', style: Ty.label),
                const SizedBox(height: 8),
                for (final m in members)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: PersonAvatar(
                      name: m['display_name'] as String? ?? memberId(m) ?? '?',
                      size: 26,
                    ),
                    title: Text(
                        m['display_name'] as String? ?? memberId(m) ?? '?'),
                    trailing: m['role'] == 'owner'
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Dk.p3,
                              borderRadius: BorderRadius.circular(Rd.pill),
                            ),
                            child: Text(
                              '群主',
                              style: Ty.small.copyWith(fontSize: 11.5),
                            ),
                          )
                        : null,
                  ),
                const Divider(height: 32),

                if (isOwner) ...[
                  // ── 邀请 ──
                  Text('邀请', style: Ty.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _run(() async {
                          final client = ref.read(openHumanClientProvider);
                          final res = await client.mintInvite(widget.roomId);
                          setState(
                              () => _lastInviteCode = res['code'] as String?);
                        }),
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('创建邀请码'),
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
                  Text('接入', style: Ty.label),
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
                    label: const Text('创建密钥'),
                  ),
                  if (_lastCallerKey != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Dk.p3,
                        borderRadius: BorderRadius.circular(Rd.sm),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lastCallerKey!,
                              style: Ty.small,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () =>
                                _copy('caller key', _lastCallerKey!),
                            tooltip: '复制',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 32),

                  // ── 已连接的 AI（工具调用目标，§6.6）──
                  _CallersSection(roomId: widget.roomId),
                  const Divider(height: 32),

                  // ── 设置 ──
                  Text('群聊设置', style: Ty.label),
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
                    '仅群主可见。',
                    style: Ty.small.copyWith(
                      color: Dk.t2,
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
        title: const Text('创建密钥'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Ty.small),
          ),
          Expanded(
            child: Text(
              value,
              style: Ty.small.copyWith(
                  fontFamily: 'GeistMono',
                  fontFamilyFallback: const ['NotoSansSC']),
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
            const SizedBox(width: 120, child: Text('空闲超时（秒）')),
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
          value: _segmented,
          onChanged: (v) => setState(() => _segmented = v),
        ),
        FilledButton(
          onPressed: () =>
              widget.onSave(int.tryParse(_idle.text) ?? 60, _segmented),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// The AI callers reachable in the room. A tool call runs on the one
/// session the owner picks here — with several callers declaring the same
/// tool, the server refuses an untargeted call rather than guess whose
/// machine runs it.
class _CallersSection extends ConsumerStatefulWidget {
  const _CallersSection({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_CallersSection> createState() => _CallersSectionState();
}

class _CallersSectionState extends ConsumerState<_CallersSection> {
  late Future<List<Map<String, dynamic>>> _callers = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(openHumanClientProvider).listRoomCallers(widget.roomId);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('已连接的工具', style: Ty.label),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: '刷新',
              onPressed: () => setState(() => _callers = _load()),
            ),
          ],
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _callers,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              );
            }
            if (snap.hasError) return const Text('无法加载');
            final callers = snap.data ?? const [];
            if (callers.isEmpty) {
              return Text(
                '无已连接的工具',
                style: Ty.small,
              );
            }
            return Column(
              children: [
                for (final c in callers)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.smart_toy_outlined,
                      size: 20,
                      color: c['live'] == true ? Dk.t1 : Dk.t2,
                    ),
                    title: Text(c['display_name'] as String? ?? '?'),
                    subtitle: Text(
                      '${c['live'] == true ? '在线' : '空闲'} · '
                      '${(c['tools'] as List?)?.length ?? 0} 个工具',
                    ),
                    trailing: ((c['tools'] as List?)?.isNotEmpty ?? false)
                        ? TextButton(
                            onPressed: () => _invoke(context, c),
                            child: const Text('调用工具'),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _invoke(
      BuildContext context, Map<String, dynamic> caller) async {
    final tools = (caller['tools'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    var tool = tools.first;
    final input = TextEditingController(text: '{}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('在 ${caller['display_name']} 上调用'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: tool,
                isExpanded: true,
                items: [
                  for (final t in tools)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setLocal(() => tool = v ?? tool),
              ),
              TextField(
                controller: input,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '参数 (JSON)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('执行'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final args = jsonDecode(input.text.trim().isEmpty ? '{}' : input.text);
      await ref.read(openHumanClientProvider).invokeTool(
            widget.roomId,
            tool,
            args,
            target: caller['target'] as String?,
          );
      messenger.showSnackBar(const SnackBar(content: Text('已发送')));
    } on FormatException {
      messenger.showSnackBar(const SnackBar(content: Text('JSON 无效')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('无法执行：$e')));
    }
  }
}
