/// Chat screen: the conversation with one person (or one room).
///
/// The header leads with the person: their avatar, their name, the
/// small "经由 Claude Code" tag for the tool they type in, and whose
/// move it is. Below it the stream, then the composer.
///
/// Layout, by window class (see `app/adaptive.dart`):
/// ```
/// expanded  ┌ list ┬──── stream ────┬ details ┐   all side by side
/// medium    ┌ list ┬──── stream ─────[details]┐   details overlay
/// compact   [ list ] ⇄ [ stream ]  details = bottom sheet
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sdk_provider.dart';
import '../../core/tasks.dart';
import '../../core/tray_service.dart';
import '../../widgets/avatar.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/motion.dart';
import 'message_adapter.dart';
import 'share_sheet.dart';
import 'details_panel.dart';
import 'chat_controller.dart';
import 'conversation_sidebar.dart';
import 'room_composer.dart';
import 'stream/message_stream.dart';
import '../../app/adaptive.dart';
import '../../widgets/pane_divider.dart';
import '../../widgets/sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _showRuntimePanel = false;
  bool _showSidebar = false;
  bool _sidebarDecided = false;
  double _sidebarWidth = kSidebarDefault;
  double _runtimeWidth = kDetailsDefault;

  /// Whose turn it is, kept for panes opened outside build (the sheet).
  bool _waitingOnMe = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A desktop window wide enough for both panes opens with the list
    // showing; a narrow one keeps the stream to itself.
    if (!_sidebarDecided) {
      _sidebarDecided = true;
      final w = MediaQuery.sizeOf(context).width;
      _showSidebar = w >= 840;
    }
  }

  /// Phones show one pane at a time: the list, or the open conversation.
  bool _phoneList = true;

  void _focusSearch() {
    setState(() {
      _showSidebar = true;
      _phoneList = true;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => sidebarSearchFocus.requestFocus(),
    );
  }

  /// Whether I ended the turn in the open conversation. The controller
  /// keeps the mark and clears it when the other side writes again.
  /// Only read during build.
  bool get _turnEnded {
    final id = ref.watch(activeConversationIdProvider);
    return id != null && ref.watch(turnEndedProvider).contains(id);
  }

  bool _reconnecting = false;

  /// Reconnect using the credentials saved on the last successful connect.
  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('openhuman_server_url');
      final apiKey = prefs.getString('openhuman_api_key');

      if (url == null || url.isEmpty || apiKey == null || apiKey.isEmpty) {
        if (mounted) context.go('/auth');
        return;
      }

      final client = ref.read(openHumanClientProvider);
      await client.disconnect();
      await client.connect(url, apiKey);
    } catch (e) {
      debugPrint('[ChatScreen] Reconnect failed: $e');
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A step the server turned down (left the room, owner only, a tool
    // the other side no longer has) is said once, plainly.
    ref.listen(serverNoticeProvider, (_, next) {
      final t = next.valueOrNull;
      if (t != null) toast(context, t);
    });
    final messages = ref.watch(chatControllerProvider);
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        oh.ConnectionState.idle;
    final human = ref.watch(currentHumanProvider);
    // Watched here so the list starts fetching as soon as the console
    // opens. The provider is lazy, and the sidebar is often closed —
    // waiting for it to be opened would start the fetch far too late.
    final list = ref.watch(conversationListProvider);
    TrayService.instance
        .setWaiting(list.entries.where((c) => c.waiting).length);

    final controller = ref.read(chatControllerProvider.notifier);
    final humanUser = controller.humanUser;

    void sendText(String text) {
      final sent = controller.sendReply(text);
      if (!sent && mounted) toast(context, '未选择对话');
    }

    // Group-room context (§10.6): end.turn and the tool-invoke panel are
    // owner-only. The server enforces it; the buttons simply don't show.
    final activeConvId = ref.watch(activeConversationIdProvider);
    ConversationInfo? activeInfo;
    for (final c in ref.watch(conversationListProvider).entries) {
      if (c.id == activeConvId) {
        activeInfo = c;
        break;
      }
    }
    final isGroup = activeInfo?.isGroup ?? false;
    final isRoomOwner = isGroup &&
        activeConvId != null &&
        ref.watch(roomOwnershipProvider(activeConvId));
    final showOwnerControls = !isGroup || isRoomOwner;

    final waitingOnMe = !_turnEnded &&
        messages.isNotEmpty &&
        messages.first.author.id != humanUser.id;
    _waitingOnMe = waitingOnMe;
    final openTask = _openFileTask(messages, humanUser.id);
    final mentionNames = isGroup && activeConvId != null
        ? roomMemberNames(
            ref.watch(roomInfoProvider(activeConvId)).valueOrNull,
          )
        : const <String>[];

    final shortcuts = <ShortcutActivator, VoidCallback>{
      for (final mod in const [true, false]) ...{
        SingleActivator(LogicalKeyboardKey.keyK, control: mod, meta: !mod):
            _focusSearch,
        SingleActivator(LogicalKeyboardKey.keyB, control: mod, meta: !mod):
            () => setState(() => _showSidebar = !_showSidebar),
        SingleActivator(LogicalKeyboardKey.keyI, control: mod, meta: !mod):
            _toggleRuntime,
      },
    };

    final fit = Fit.of(context);
    final phoneList = fit.isCompact && (_phoneList || activeConvId == null);
    return PopScope(
      // Android back on a phone: from a conversation, back to the list.
      canPop: !fit.isCompact || phoneList,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _phoneList = true);
      },
      child: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: true,
          child: _scaffold(
            fit: fit,
            phoneList: phoneList,
            context,
            messages: messages,
            connState: connState,
            human: human,
            humanUser: humanUser,
            activeConvId: activeConvId,
            activeInfo: activeInfo,
            isGroup: isGroup,
            showOwnerControls: showOwnerControls,
            sendText: sendText,
            waitingOnMe: waitingOnMe,
            mentionNames: mentionNames,
            openTask: openTask,
          ),
        ),
      ),
    );
  }

  /// The newest task in this conversation that is still open and wants
  /// files, so the composer can attach them: (message id, task).
  (String, ApiTask)? _openFileTask(List<types.Message> newestFirst, String me) {
    final outcomes = ref.watch(taskOutcomesProvider);
    for (final m in newestFirst) {
      if (m.author.id == me) return null;
      final t = taskOf(m);
      if (t == null) continue;
      final o = outcomes[m.id]?.state;
      if (o != null && o != TaskState.open) return null;
      if (t.expiredAt(DateTime.now())) return null;
      if (t.media == AnswerMedia.text || t.media == AnswerMedia.json) {
        return null;
      }
      return (m.id, t);
    }
    return null;
  }

  void _toggleRuntime() {
    final fit = Fit.of(context);
    if (fit.isCompact) {
      _runtimeSheet();
      return;
    }
    setState(() => _showRuntimePanel = !_showRuntimePanel);
  }

  /// On a phone the runtime pane is a sheet over the stream.
  void _runtimeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Dk.p1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (c, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrip(),
            Expanded(
              child: DetailsPanel(
                width: double.infinity,
                waitingOnMe: _waitingOnMe,
                onClose: () => Navigator.of(c).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scaffold(
    BuildContext context, {
    required Fit fit,
    required bool phoneList,
    required List<types.Message> messages,
    required oh.ConnectionState connState,
    required oh.HumanSession? human,
    required types.User humanUser,
    required String? activeConvId,
    required ConversationInfo? activeInfo,
    required bool isGroup,
    required bool showOwnerControls,
    required void Function(String) sendText,
    required bool waitingOnMe,
    required List<String> mentionNames,
    required (String, ApiTask)? openTask,
  }) {
    final caller = activeInfo?.caller;
    final connected = connState == oh.ConnectionState.connected;
    final topBar = _TopBar(
      compact: fit.isCompact,
      title: activeInfo?.displayName ?? human?.displayName ?? 'OpenHuman',
      avatar: activeInfo == null
          ? null
          : isGroup
              ? RoomAvatar(
                  title: activeInfo.displayName,
                  members: mentionNames,
                  size: fit.isCompact ? Sz.avatarSm : Sz.avatar,
                )
              : PersonAvatar(
                  name: caller!.name,
                  anonymous: caller.anonymous,
                  size: fit.isCompact ? Sz.avatarSm : Sz.avatar,
                ),
      via: isGroup
          ? (activeInfo?.memberCount == null
              ? '群聊'
              : '群聊 · ${activeInfo!.memberCount} 人')
          : caller?.via,
      // My own connection only speaks up when it is not fine.
      connection: activeInfo != null && connected
          ? null
          : _connectionStateLabel(connState, human),
      conn: connState,
      state: _turnEnded
          ? _TurnState.ended
          : waitingOnMe
              ? _TurnState.yours
              : messages.isEmpty
                  ? _TurnState.idle
                  // My newest reply never left: they are not waiting on
                  // anything from me, they have not heard it at all.
                  : messages.first.status == types.Status.error
                      ? _TurnState.failed
                      : _TurnState.theirs,
      sidebarOpen: !fit.isCompact && _showSidebar,
      onSidebar: () => setState(() {
        if (fit.isCompact) {
          _phoneList = true;
        } else {
          _showSidebar = !_showSidebar;
        }
      }),
      actions: [
        if (!connected)
          _Action(
            glyph: Glyph.retry,
            label: '重新连接',
            busy: _reconnecting,
            onTap: _reconnecting ? null : _reconnect,
          ),
        _Action(
          glyph: isGroup ? Glyph.people : Glyph.details,
          label: isGroup ? '群聊详情' : '对话详情',
          shortcut: 'I',
          active: _showRuntimePanel && !fit.isCompact,
          onTap: _toggleRuntime,
        ),
        _Action(
          glyph: Glyph.link,
          label: '分享联系方式',
          onTap: () => ShareSheet.show(context),
        ),
      ],
    );

    final stream = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar,
        Expanded(
          // A reading column: on a wide window the stream keeps its
          // measure instead of flinging replies to the edge.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sp.column),
              child: StreamColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (connState != oh.ConnectionState.connected &&
                        connState != oh.ConnectionState.idle)
                      _ConnBanner(
                        state: connState,
                        busy: _reconnecting,
                        onRetry: _reconnecting ? null : _reconnect,
                      ),
                    Expanded(
                      child: MessageStream(
                        messages: messages,
                        meId: humanUser.id,
                        mentions: mentionNames,
                        waitingOnMe: waitingOnMe,
                        onRetry:
                            ref.read(chatControllerProvider.notifier).retry,
                      ),
                    ),
                    Composer(
                      // A fresh composer per conversation: a draft never
                      // leaks into someone else's chat.
                      key: ValueKey('composer-$activeConvId'),
                      enabled: !_turnEnded,
                      onSend: sendText,
                      // Nothing to end before anyone has written.
                      onEndTurn: showOwnerControls && messages.isNotEmpty
                          ? _endTurn
                          : null,
                      onReopen:
                          ref.read(chatControllerProvider.notifier).reopenTurn,
                      mentionNames: mentionNames,
                      to: isGroup ? null : caller?.name,
                      waitingOnMe: waitingOnMe,
                      offline: !connected,
                      fileTypes: openTask?.$2.acceptExtensions,
                      onSendFiles: openTask == null
                          ? null
                          : (text, files) => _sendFiles(
                                openTask.$1,
                                openTask.$2,
                                text,
                                files,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (fit.isCompact) {
      final w = MediaQuery.sizeOf(context).width;
      return Scaffold(
        backgroundColor: Dk.bg,
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: Mo.base,
            switchInCurve: Mo.expo,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, a) {
              final list = child.key == const ValueKey('phone-list');
              return SlideTransition(
                position: Tween(
                  begin: Offset(list ? -0.25 : 0.25, 0),
                  end: Offset.zero,
                ).animate(a),
                child: FadeTransition(opacity: a, child: child),
              );
            },
            child: phoneList
                ? KeyedSubtree(
                    key: const ValueKey('phone-list'),
                    child: ConversationSidebar(
                      width: w,
                      onPicked: () => setState(() => _phoneList = false),
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('phone-stream'),
                    child: stream,
                  ),
          ),
        ),
      );
    }

    final runtimeOpen = _showRuntimePanel && activeConvId != null;
    final runtimeInline = fit.isExpanded;

    return Scaffold(
      backgroundColor: Dk.bg,
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Conversation list ──
            AnimatedSize(
              duration: Mo.base,
              curve: Mo.expo,
              alignment: Alignment.centerLeft,
              child: _showSidebar
                  ? ConversationSidebar(width: _sidebarWidth)
                  : const SizedBox.shrink(),
            ),
            if (_showSidebar)
              PaneDivider(
                onDrag: (dx) => setState(
                  () => _sidebarWidth =
                      (_sidebarWidth + dx).clamp(kSidebarMin, kSidebarMax),
                ),
                onReset: () => setState(() => _sidebarWidth = kSidebarDefault),
              ),
            // ── Stream (+ the runtime pane floating over it on medium) ──
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: stream),
                  if (!runtimeInline)
                    _OverlayPane(
                      open: runtimeOpen,
                      onDismiss: () =>
                          setState(() => _showRuntimePanel = false),
                      child: DetailsPanel(
                        width: kDetailsDefault,
                        waitingOnMe: waitingOnMe,
                        onClose: () =>
                            setState(() => _showRuntimePanel = false),
                      ),
                    ),
                ],
              ),
            ),
            // ── Agent runtime ──
            if (runtimeInline)
              AnimatedSize(
                duration: Mo.base,
                curve: Mo.expo,
                alignment: Alignment.centerRight,
                child: runtimeOpen
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PaneDivider(
                            invert: true,
                            onDrag: (dx) => setState(
                              () => _runtimeWidth = (_runtimeWidth + dx)
                                  .clamp(kDetailsMin, kDetailsMax),
                            ),
                            onReset: () => setState(
                              () => _runtimeWidth = kDetailsDefault,
                            ),
                          ),
                          DetailsPanel(
                            width: _runtimeWidth,
                            waitingOnMe: waitingOnMe,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  void _endTurn() {
    // end.turn closes the other person's waiting stream
    // (`finish_reason: stop` + [DONE]), so their tool shows my reply as
    // complete.
    final ended = ref.read(chatControllerProvider.notifier).endTurn();
    if (!ended && mounted) toast(context, '没有进行中的对话');
  }

  /// Words and files from the composer, as the answer to an open task.
  Future<void> _sendFiles(
    String taskMessageId,
    ApiTask task,
    String text,
    List<OutgoingFile> files,
  ) async {
    final out = await ref.read(chatControllerProvider.notifier).answerTask(
          taskMessageId: taskMessageId,
          task: task,
          text: text,
          files: files,
        );
    if (!mounted) return;
    if (out.state == TaskState.open && out.note != null) {
      toast(context, out.note!);
    }
  }

  String _connectionStateLabel(
    oh.ConnectionState state,
    oh.HumanSession? human,
  ) {
    switch (state) {
      case oh.ConnectionState.idle:
        return '未连接';
      case oh.ConnectionState.connecting:
        return '连接中…';
      case oh.ConnectionState.connected:
        return '已连接';
      case oh.ConnectionState.reconnecting:
        return '重连中…';
      case oh.ConnectionState.disconnected:
        return '已断开';
      case oh.ConnectionState.error:
        return '连接出错';
    }
  }
}

/// Whose move it is, as the top bar shows it.
enum _TurnState { yours, theirs, failed, ended, idle }

/// A header action: a glyph button on a desktop, a menu row on a phone.
class _Action {
  const _Action({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.active = false,
    this.busy = false,
  });
  final Glyph glyph;
  final String label;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool active;
  final bool busy;

  Widget button() => DkIconButton(
        glyph: glyph,
        label: label,
        shortcut: shortcut,
        active: active,
        busy: busy,
        bar: true,
        onTap: onTap,
      );
}

/// The stream's header: who I am talking to, whose move it is, and the
/// conversation's actions.
///
/// [Sz.bar] on a desktop (it lines up with the list's search bar and the
/// details pane's head); [Sz.barCompact] on a phone, where the list
/// button becomes a back arrow and the actions fold into a menu.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.title,
    required this.avatar,
    required this.via,
    required this.connection,
    required this.conn,
    required this.state,
    required this.sidebarOpen,
    required this.onSidebar,
    required this.actions,
  });

  final bool compact;
  final String title;

  /// The person's (or room's) face; null with no conversation open.
  final Widget? avatar;

  /// "经由 Claude Code", "群聊 · 4 人".
  final String? via;

  /// My own connection, when it needs saying.
  final String? connection;
  final oh.ConnectionState conn;
  final _TurnState state;
  final bool sidebarOpen;
  final VoidCallback onSidebar;
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final connColor = switch (conn) {
      oh.ConnectionState.connected => Dk.ok,
      oh.ConnectionState.connecting ||
      oh.ConnectionState.reconnecting =>
        Dk.warn,
      oh.ConnectionState.error => Dk.danger,
      _ => Dk.t3,
    };
    final turn = _turnLabel(state, compact);
    final second = <Widget>[
      if (via != null)
        Flexible(
          child: Text(
            via!,
            style: Ty.small.copyWith(fontSize: 12, color: Dk.t3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (connection != null) ...[
        if (via != null) const _Sep(),
        Container(
          width: Sz.dotSm,
          height: Sz.dotSm,
          decoration: BoxDecoration(shape: BoxShape.circle, color: connColor),
        ),
        const SizedBox(width: Sp.x15),
        Flexible(
          child: Text(
            connection!,
            style: Ty.small.copyWith(fontSize: 12, color: Dk.t3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      // On a phone the turn sits here; a desktop has room for a pill.
      if (compact && turn != null) ...[
        if (via != null || connection != null) const _Sep(),
        Text(
          turn.$1,
          style: Ty.small.copyWith(
            fontSize: 12,
            color: turn.$2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ];
    final heading = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: compact
              ? Ty.title.copyWith(fontSize: 16)
              : Ty.title.copyWith(fontSize: 17),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (second.isNotEmpty) ...[
          const SizedBox(height: Sp.x05),
          Row(mainAxisSize: MainAxisSize.min, children: second),
        ],
      ],
    );
    final who = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avatar != null) ...[
          avatar!,
          SizedBox(width: compact ? Sp.x25 : Sp.x3),
        ],
        Flexible(child: heading),
      ],
    );

    if (compact) {
      // Keep the one action a phone reaches for most (reconnect when it
      // is needed, else the details) and fold the rest.
      final keep = actions.isEmpty ? null : actions.first;
      final rest = actions.length > 1 ? actions.sublist(1) : <_Action>[];
      return Container(
        height: Sz.barCompact,
        padding: const EdgeInsets.symmetric(horizontal: Sp.x1),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Dk.line)),
        ),
        child: Row(
          children: [
            DkIconButton(
              glyph: Glyph.back,
              label: '对话列表',
              bar: true,
              onTap: onSidebar,
            ),
            const SizedBox(width: Sp.x1),
            Expanded(child: who),
            const SizedBox(width: Sp.x1),
            if (keep != null) keep.button(),
            if (rest.isNotEmpty) _Overflow(items: rest),
          ],
        ),
      );
    }

    return Container(
      height: Sz.bar,
      padding: const EdgeInsets.only(left: Sp.x3, right: Sp.x4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: Row(
        children: [
          DkIconButton(
            glyph: Glyph.sidebar,
            label: '对话列表',
            shortcut: 'B',
            bar: true,
            active: sidebarOpen,
            onTap: onSidebar,
          ),
          const SizedBox(width: Sp.x3),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: who,
                  ),
                ),
                const SizedBox(width: Sp.x4),
                if (turn != null)
                  Swap(
                    value: state,
                    child: _StatePill(state: state),
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[
            const SizedBox(width: Sp.x05),
            a.button(),
          ],
        ],
      ),
    );
  }
}

/// What the header says about whose move it is, and in what colour.
(String, Color)? _turnLabel(_TurnState s, bool short) => switch (s) {
      _TurnState.yours => (short ? '待回复' : '待回复', Dk.signal),
      _TurnState.theirs => ('等待回复', Dk.t2),
      _TurnState.failed => (short ? '未发送' : '回复未发送', Dk.danger),
      _TurnState.ended => (short ? '已结束' : '已结束本轮', Dk.t3),
      _TurnState.idle => null,
    };

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x15),
        child: Text('·', style: Ty.small.copyWith(color: Dk.t4)),
      );
}

/// The folded actions of a phone top bar.
class _Overflow extends StatelessWidget {
  const _Overflow({required this.items});
  final List<_Action> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '更多',
      icon: const GlyphIcon(Glyph.more, size: Sz.glyph, color: Dk.t2),
      position: PopupMenuPosition.under,
      onSelected: (i) => items[i].onTap?.call(),
      itemBuilder: (c) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: items[i].onTap != null,
            child: Row(
              children: [
                GlyphIcon(items[i].glyph, size: Sz.glyph, color: Dk.t2),
                const SizedBox(width: Sp.x3),
                Text(items[i].label, style: Ty.body),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});
  final _TurnState state;

  @override
  Widget build(BuildContext context) {
    final (label, fg) = _turnLabel(state, false)!;
    final yours = state == _TurnState.yours;
    final failed = state == _TurnState.failed;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.x25, Sp.x1, Sp.x3, Sp.x1),
        decoration: BoxDecoration(
          color: yours
              ? Dk.signalSoft
              : failed
                  ? Dk.dangerSoft
                  : Dk.p2,
          borderRadius: BorderRadius.circular(Rd.pill),
          border: Border.all(
            color: yours
                ? Dk.signalRing
                : failed
                    ? Dk.dangerEdge
                    : Dk.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BreathingDot(color: fg, on: yours, size: Sz.dotSm),
            const SizedBox(width: Sp.x2),
            Text(
              label,
              style: Ty.name.copyWith(fontSize: 12, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin strip under the top bar while the socket is down: says what is
/// happening and offers the one fix.
class _ConnBanner extends StatelessWidget {
  const _ConnBanner({
    required this.state,
    required this.busy,
    required this.onRetry,
  });
  final oh.ConnectionState state;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final g = StreamScope.of(context);
    final retrying = state == oh.ConnectionState.connecting ||
        state == oh.ConnectionState.reconnecting;
    final (fg, bg, edge, text) = retrying
        ? (Dk.warn, Dk.warnSoft, Dk.warnSoft, '正在重新连接…')
        : (Dk.danger, Dk.dangerSoft, Dk.dangerEdge, '已断开连接。');
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: EdgeInsets.fromLTRB(g.side, Sp.x3, g.side, 0),
        padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x15, Sp.x15, Sp.x15),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Rd.md),
          border: Border.all(color: edge),
        ),
        child: Row(
          children: [
            if (retrying)
              SizedBox.square(
                dimension: Sz.glyphXs,
                child: CircularProgressIndicator(
                  strokeWidth: Sz.stroke,
                  color: fg,
                ),
              )
            else
              GlyphIcon(Glyph.offline, size: Sz.glyphSm, color: fg),
            const SizedBox(width: Sp.x2),
            Expanded(
              child: Text(
                text,
                style: Ty.small.copyWith(color: Dk.t1, fontSize: 12.5),
              ),
            ),
            if (!retrying)
              DkButton(
                label: busy ? '连接中…' : '重新连接',
                kind: DkButtonKind.quiet,
                dense: true,
                busy: busy,
                onTap: onRetry,
              ),
          ],
        ),
      ),
    );
  }
}

/// The details pane over the stream on a medium window: slides in from
/// the right over a scrim; a tap on the scrim or Esc closes it.
class _OverlayPane extends StatefulWidget {
  const _OverlayPane({
    required this.open,
    required this.onDismiss,
    required this.child,
  });
  final bool open;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_OverlayPane> createState() => _OverlayPaneState();
}

class _OverlayPaneState extends State<_OverlayPane> {
  /// Built while open and while sliding away; a closed pane is not built
  /// at all, so it never holds focus or answers a search for its text.
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    final onDismiss = widget.onDismiss;
    if (open) _built = true;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: onDismiss,
                  child: AnimatedOpacity(
                    duration: Mo.base,
                    opacity: open ? 1 : 0,
                    child: const ColoredBox(color: Dk.scrim),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: Mo.slow,
                curve: Mo.expo,
                top: 0,
                bottom: 0,
                right: open ? 0 : -kDetailsDefault - 24,
                onEnd: () {
                  if (!widget.open && _built) setState(() => _built = false);
                },
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Dk.line2)),
                    boxShadow: [
                      BoxShadow(color: Dk.shadow, blurRadius: 40),
                    ],
                  ),
                  child: _built
                      ? Focus(autofocus: open, child: widget.child)
                      : const SizedBox(width: kDetailsDefault),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
