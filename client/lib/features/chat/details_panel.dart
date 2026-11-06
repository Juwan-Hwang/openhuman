/// Details pane (Ctrl/⌘+I): who is on the other end, and what you can do
/// about this conversation.
///
/// It leads with the person — face, name, the tool they write from — and
/// a remark name you can change. The technical side (ids, declared tools,
/// their system prompt) is folded away under 技术详情: it is there when
/// needed and never the first thing a person reads.
///
/// In a group the same pane manages the room: members (the owner can
/// remove one), invite codes, leaving.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/sdk_provider.dart';
import '../../widgets/avatar.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import 'agent_runtime_panel.dart';
import 'conversation_sidebar.dart';
import 'room_composer.dart';
import 'room_panel.dart';

/// Pane width limits; resizable from its left edge.
const double kDetailsMin = 300;
const double kDetailsMax = 520;
const double kDetailsDefault = 340;

class DetailsPanel extends ConsumerWidget {
  const DetailsPanel({
    super.key,
    this.width = kDetailsDefault,
    this.onClose,
    this.waitingOnMe = false,
  });

  final double width;

  /// Shown as a close button when the pane floats (tablet overlay, phone
  /// sheet) instead of sitting in the window.
  final VoidCallback? onClose;

  /// Whose turn it is, as the header has it.
  final bool waitingOnMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(activeConversationIdProvider);
    final info = ref
        .watch(conversationListProvider)
        .entries
        .where((c) => c.id == id)
        .firstOrNull;

    return SizedBox(
      width: width,
      child: ColoredBox(
        color: Dk.p1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onClose: onClose),
            Expanded(
              child: info == null
                  ? const _Nothing()
                  : info.isGroup
                      ? _RoomDetails(info: info)
                      : _PersonDetails(info: info, waitingOnMe: waitingOnMe),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: Sp.x5, right: Sp.x3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: Row(
        children: [
          Text('详情', style: Ty.name.copyWith(fontSize: 14)),
          const Spacer(),
          if (onClose != null)
            DkIconButton(glyph: Glyph.close, label: '关闭', onTap: onClose)
          else
            const Kbd('Ctrl I'),
        ],
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '未选择对话',
        style: Ty.small.copyWith(color: Dk.t3),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  One person
// ═══════════════════════════════════════════════════════════════

class _PersonDetails extends ConsumerWidget {
  const _PersonDetails({required this.info, required this.waitingOnMe});
  final ConversationInfo info;
  final bool waitingOnMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caller = info.caller;
    final caps = ref.watch(capabilityCacheProvider);
    // The cache holds the latest report from anyone; only show it here
    // when it is this person's.
    final mine =
        caps != null && (caps.agentId == info.agentId || caps.agentId.isEmpty)
            ? caps
            : null;

    return ListView(
      key: const ValueKey('details-person'),
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x6, Sp.x4, Sp.x8),
      children: [
        // ── Who ──
        Center(
          child: PersonAvatar(
            name: caller.name,
            anonymous: caller.anonymous,
            size: Sz.avatarLg,
            waiting: waitingOnMe,
          ),
        ),
        const SizedBox(height: Sp.x3),
        Text(
          info.displayName,
          textAlign: TextAlign.center,
          style: Ty.title.copyWith(fontSize: 18),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Sp.x15),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Sp.x15,
          runSpacing: Sp.x1,
          children: [
            if (caller.tool != null) Tag('通过 ${caller.tool}'),
            if (caller.tag != null) Tag(caller.tag!, mono: true),
          ],
        ),
        const SizedBox(height: Sp.x3),
        Center(child: _TurnChip(waitingOnMe: waitingOnMe)),
        const SizedBox(height: Sp.x6),

        // ── Remark name ──
        _Group(
          children: [
            _Row(
              key: const ValueKey('details-remark'),
              label: '名称',
              value: caller.anonymous ? '添加名称' : caller.name,
              valueMuted: caller.anonymous,
              trailing: const GlyphIcon(Glyph.edit, size: 14, color: Dk.t3),
              onTap: () => askForName(context, ref, info),
            ),
            // Only when the raw name says more than the person and tool
            // already shown (a session tag, a name the parser dropped).
            if (caller.raw != caller.name &&
                caller.raw != remarkToStoredName(caller.name, caller.tool))
              _Row(
                label: '原始名称',
                value: caller.raw,
                mono: true,
              ),
          ],
        ),
        const SizedBox(height: Sp.x4),

        // ── This conversation ──
        _Group(
          children: [
            _Row(
              label: '保存记录',
              trailing: const GlyphIcon(Glyph.save, size: 14, color: Dk.t3),
              onTap: () async {
                final ok = await ref
                    .read(conversationListProvider.notifier)
                    .saveConversation(info.id);
                if (context.mounted) toast(context, ok ? '已保存' : '无法保存');
              },
            ),
            _Row(
              label: '移到废纸篓',
              danger: true,
              trailing:
                  const GlyphIcon(Glyph.trash, size: 14, color: Dk.danger),
              onTap: () => confirmTrash(context, ref, info),
            ),
          ],
        ),
        const SizedBox(height: Sp.x4),

        // ── Technical details, folded ──
        _Fold(
          key: const ValueKey('details-tech'),
          title: '高级',
          summary: mine == null ? '' : '${mine.capabilities.length} 个工具',
          children: [
            _Group(
              children: [
                _Row(label: 'ID', value: info.agentId, mono: true, copy: true),
                _Row(label: '对话 ID', value: info.id, mono: true, copy: true),
                if (info.origin != null)
                  _Row(label: '来自', value: info.origin!, mono: true),
              ],
            ),
            const SizedBox(height: Sp.x4),
            Padding(
              padding: const EdgeInsets.only(left: Sp.x1, bottom: Sp.x2),
              child: Text(
                mine == null ? '工具' : '工具 · ${mine.capabilities.length}',
                style: Ty.label,
              ),
            ),
            if (mine == null)
              Padding(
                padding: const EdgeInsets.only(left: Sp.x1),
                child: Text(
                  '无工具',
                  style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
                ),
              )
            else
              RuntimeTools(data: mine),
          ],
        ),
      ],
    );
  }
}

class _TurnChip extends StatelessWidget {
  const _TurnChip({required this.waitingOnMe});
  final bool waitingOnMe;

  @override
  Widget build(BuildContext context) {
    final (text, color, floor) = waitingOnMe
        ? ('待回复', Dk.signal, Dk.signalSoft)
        : ('无待回复', Dk.t3, Dk.p3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x25, vertical: 3),
      decoration: BoxDecoration(
        color: floor,
        borderRadius: BorderRadius.circular(Rd.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: Sz.dotSm,
            height: Sz.dotSm,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Sp.x15),
          Text(
            text,
            style: Ty.small.copyWith(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  A group
// ═══════════════════════════════════════════════════════════════

class _RoomDetails extends ConsumerStatefulWidget {
  const _RoomDetails({required this.info});
  final ConversationInfo info;

  @override
  ConsumerState<_RoomDetails> createState() => _RoomDetailsState();
}

class _RoomDetailsState extends ConsumerState<_RoomDetails> {
  String? _invite;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(roomInfoProvider(widget.info.id));
    } catch (e) {
      if (mounted) toast(context, '出现错误：${_plain(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final roomAsync = ref.watch(roomInfoProvider(info.id));
    final isOwner = ref.watch(roomOwnershipProvider(info.id));
    final me = ref.watch(currentHumanProvider)?.id;
    final room = roomAsync.valueOrNull;
    final members = ((room?['members'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList()
      // The owner first, then me, then everyone else as the server lists.
      ..sort((a, b) {
        int rank(Map<String, dynamic> m) =>
            m['role'] == 'owner' ? 0 : (memberId(m) == me ? 1 : 2);
        return rank(a).compareTo(rank(b));
      });
    final names = roomMemberNames(room);
    final client = ref.read(openHumanClientProvider);

    return ListView(
      key: const ValueKey('details-room'),
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x6, Sp.x4, Sp.x8),
      children: [
        Center(
          child: RoomAvatar(
            title: info.displayName,
            members: names,
            size: Sz.avatarLg,
          ),
        ),
        const SizedBox(height: Sp.x3),
        Text(
          info.displayName,
          textAlign: TextAlign.center,
          style: Ty.title.copyWith(fontSize: 18),
        ),
        const SizedBox(height: Sp.x1),
        Text(
          [
            '${members.isEmpty ? (info.memberCount ?? 0) : members.length} 人',
            if (isOwner) '群主',
          ].join(' · '),
          textAlign: TextAlign.center,
          style: Ty.small.copyWith(color: Dk.t3),
        ),
        const SizedBox(height: Sp.x6),

        // ── Members ──
        _SectionTitle('成员', trailing: _busy ? const _Spinner() : null),
        if (roomAsync.isLoading && room == null)
          const Padding(
            padding: EdgeInsets.all(Sp.x4),
            child: Center(child: _Spinner()),
          )
        else if (room == null)
          Padding(
            padding: const EdgeInsets.all(Sp.x2),
            child: Text(
              '无法加载成员',
              style: Ty.small.copyWith(color: Dk.t3),
            ),
          )
        else
          _Group(
            children: [
              for (final m in members)
                _MemberRow(
                  key: ValueKey('member-${memberId(m) ?? m['display_name']}'),
                  name: m['display_name'] as String? ?? memberId(m) ?? '?',
                  owner: m['role'] == 'owner',
                  me: memberId(m) != null && memberId(m) == me,
                  onRemove: isOwner &&
                          memberId(m) != null &&
                          memberId(m) != me &&
                          m['role'] != 'owner'
                      ? () => _confirmRemove(
                            m['display_name'] as String? ?? '此成员',
                            memberId(m)!,
                          )
                      : null,
                ),
            ],
          ),
        const SizedBox(height: Sp.x5),

        // ── Invite (owner) ──
        if (isOwner) ...[
          const _SectionTitle('邀请'),
          _Group(
            children: [
              if (_invite == null)
                _Row(
                  key: const ValueKey('details-invite'),
                  label: '创建邀请码',
                  trailing:
                      const GlyphIcon(Glyph.invite, size: 14, color: Dk.t3),
                  onTap: () => _run(() async {
                    final res = await client.mintInvite(info.id);
                    setState(() => _invite = res['code'] as String?);
                  }),
                )
              else ...[
                _Row(
                  label: '邀请码',
                  value: _invite,
                  mono: true,
                  copy: true,
                  emphasis: true,
                ),
                _Row(
                  label: '停用邀请码',
                  danger: true,
                  onTap: () => _run(() async {
                    await client.revokeInvite(info.id, _invite!);
                    setState(() => _invite = null);
                  }),
                ),
              ],
            ],
          ),
          const SizedBox(height: Sp.x5),
        ],

        // ── This room ──
        _Group(
          children: [
            if (isOwner)
              _Row(
                label: '群聊设置',
                trailing: const GlyphIcon(Glyph.more, size: 14, color: Dk.t3),
                onTap: () => RoomPanel.show(context, info.id),
              ),
            _Row(
              label: '保存记录',
              trailing: const GlyphIcon(Glyph.save, size: 14, color: Dk.t3),
              onTap: () async {
                final ok = await ref
                    .read(conversationListProvider.notifier)
                    .saveConversation(info.id);
                if (context.mounted) toast(context, ok ? '已保存' : '无法保存');
              },
            ),
            if (!isOwner && room != null)
              _Row(
                label: '退出群聊',
                danger: true,
                onTap: _confirmLeave,
              ),
          ],
        ),
        const SizedBox(height: Sp.x4),
        _Fold(
          title: '高级',
          summary: '群聊 ID',
          children: [
            _Group(
              children: [
                _Row(label: '群聊 ID', value: info.id, mono: true, copy: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRemove(String name, String participantId) async {
    final ok = await _confirm(
      context,
      title: '移除',
      body: '要移除“$name”吗？',
      action: '移除',
    );
    if (!ok) return;
    await _run(() async {
      final done = await ref
          .read(openHumanClientProvider)
          .removeRoomMember(widget.info.id, participantId);
      if (!done) throw StateError('操作未完成');
      if (mounted) toast(context, '已移除');
    });
  }

  Future<void> _confirmLeave() async {
    final ok = await _confirm(
      context,
      title: '退出群聊',
      body: '退出后将不再收到此群聊的消息。',
      action: '退出',
    );
    if (!ok) return;
    await _run(() async {
      final done =
          await ref.read(openHumanClientProvider).leaveRoom(widget.info.id);
      if (!done) throw StateError('操作未完成');
      ref.read(activeConversationIdProvider.notifier).state = null;
      await ref.read(conversationListProvider.notifier).retry();
    });
  }
}

String _plain(Object e) =>
    e.toString().replaceFirst(RegExp(r'^[A-Za-z]*(Error|Exception):\s*'), '');

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.name,
    required this.owner,
    required this.me,
    this.onRemove,
  });

  final String name;
  final bool owner;
  final bool me;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 7),
      child: Row(
        children: [
          PersonAvatar(name: name, size: Sz.avatarSm, me: me),
          const SizedBox(width: Sp.x25),
          Flexible(
            child: Text(
              name,
              style: Ty.name.copyWith(color: Dk.t1Soft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (me) ...[
            const SizedBox(width: Sp.x15),
            const Tag('我'),
          ],
          if (owner) ...[
            const SizedBox(width: Sp.x15),
            const Tag('群主', color: Dk.signal, floor: Dk.signalSoft),
          ],
          const Spacer(),
          if (onRemove != null)
            DkIconButton(
              glyph: Glyph.close,
              label: '移除',
              glyphSize: Sz.glyphXs,
              onTap: onRemove,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Building blocks
// ═══════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x1, 0, Sp.x1, Sp.x2),
      child: Row(
        children: [
          Text(text, style: Ty.label),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: Sz.stroke, color: Dk.t2),
      );
}

/// Rows on one card, divided by hairlines — the settings-list idiom.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, thickness: 1, color: Dk.line));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Dk.p2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.mono = false,
    this.copy = false,
    this.danger = false,
    this.valueMuted = false,
    this.emphasis = false,
  }) : hint = null;

  final String label;
  final String? value;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool mono;
  final bool copy;
  final bool danger;
  final bool valueMuted;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tap = onTap ??
        (copy && value != null
            ? () {
                Clipboard.setData(ClipboardData(text: value!));
                toast(context, '已复制$label');
              }
            : null);
    final valueStyle = (mono ? Ty.meta : Ty.small).copyWith(
      color: valueMuted ? Dk.t3 : (emphasis ? Dk.t1 : Dk.t2),
      fontSize: mono ? (emphasis ? 14 : 11.5) : 12.5,
      letterSpacing: emphasis ? 1.5 : null,
      fontWeight: emphasis ? FontWeight.w600 : null,
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Ty.name.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: danger ? Dk.danger : Dk.t1Soft,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    value!,
                    style: valueStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (hint != null && hint!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: Ty.small.copyWith(color: Dk.t3, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          if (copy) ...[
            const SizedBox(width: Sp.x2),
            const GlyphIcon(Glyph.copy, size: 14, color: Dk.t3),
          ] else if (trailing != null) ...[
            const SizedBox(width: Sp.x2),
            trailing!,
          ],
        ],
      ),
    );
    if (tap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        hoverColor: Dk.hover,
        splashFactory: NoSplash.splashFactory,
        child: body,
      ),
    );
  }
}

/// A disclosure: a title with a one-line summary, children below when open.
class _Fold extends StatefulWidget {
  const _Fold({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
  });

  final String title;
  final String summary;
  final List<Widget> children;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(Rd.md),
            hoverColor: Dk.hover,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.x1,
                vertical: Sp.x2,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: Mo.fast,
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Dk.t3,
                    ),
                  ),
                  const SizedBox(width: Sp.x1),
                  Text(widget.title, style: Ty.label),
                  const SizedBox(width: Sp.x2),
                  Expanded(
                    child: Text(
                      _open ? '' : widget.summary,
                      style: Ty.small.copyWith(color: Dk.t4, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Mo.base,
          curve: Mo.expo,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: Sp.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
