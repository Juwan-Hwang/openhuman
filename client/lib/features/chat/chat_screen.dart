/// Chat screen — the main communication UI.
///
/// Layout, by window class (see `app/adaptive.dart`):
/// ```
/// expanded  ┌ list ┬──── stream ────┬ runtime ┐   all side by side
/// medium    ┌ list ┬──── stream ─────[runtime]┐   runtime overlays
/// compact   [ list ] ⇄ [ stream ]  runtime = bottom sheet
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
import 'agent_integration_sheet.dart';
import 'agent_runtime_panel.dart';
import 'chat_controller.dart';
import 'conversation_sidebar.dart';
import 'room_composer.dart';
import 'room_panel.dart';
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
  double _runtimeWidth = kRuntimeDefault;

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
    final messages = ref.watch(chatControllerProvider);
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        oh.ConnectionState.idle;
    final human = ref.watch(currentHumanProvider);
    // Watched here so the list starts fetching as soon as the console
    // opens. The provider is lazy, and the sidebar is often closed —
    // waiting for it to be opened would start the fetch far too late.
    ref.watch(conversationListProvider);

    final controller = ref.read(chatControllerProvider.notifier);
    final humanUser = controller.humanUser;

    void sendText(String text) {
      final sent = controller.sendReply(text);
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未连接 — 请先重连后再发送。'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
        if (showOwnerControls)
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
          ),
        ),
      ),
    );
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
              child: AgentRuntimePanel(
                width: double.infinity,
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
  }) {
    final topBar = _TopBar(
      compact: fit.isCompact,
      title: activeInfo?.displayName ?? human?.displayName ?? 'OpenHuman',
      subtitle: _connectionStateLabel(connState, human),
      conn: connState,
      state: _turnEnded
          ? _TurnState.ended
          : waitingOnMe
              ? _TurnState.yours
              : messages.isEmpty
                  ? _TurnState.idle
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
        if (connState != oh.ConnectionState.connected)
          BarIcon(
            icon: Icons.refresh_rounded,
            tooltip: '重新连接',
            busy: _reconnecting,
            onTap: _reconnecting ? null : _reconnect,
          ),
        if (isGroup && activeConvId != null)
          BarIcon(
            icon: Icons.groups_outlined,
            tooltip: '群聊管理',
            onTap: () => RoomPanel.show(context, activeConvId),
          ),
        if (showOwnerControls)
          BarIcon(
            icon: _showRuntimePanel && !fit.isCompact
                ? Icons.view_sidebar_rounded
                : Icons.view_sidebar_outlined,
            tooltip:
                fit.isCompact || Touch.primary ? 'AI 运行信息' : 'AI 运行信息  Ctrl I',
            active: _showRuntimePanel && !fit.isCompact,
            onTap: _toggleRuntime,
          ),
        BarIcon(
          icon: Icons.integration_instructions_outlined,
          tooltip: 'AI 接入配置与指南',
          onTap: () => AgentIntegrationSheet.show(context),
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
                      ),
                    ),
                    if (_turnEnded)
                      _EndedStrip(
                        onResume: () => ref
                            .read(chatControllerProvider.notifier)
                            .reopenTurn(),
                      ),
                    Composer(
                      enabled: !_turnEnded,
                      onSend: sendText,
                      // Nothing to end before the first request.
                      onEndTurn: showOwnerControls &&
                              !_turnEnded &&
                              messages.isNotEmpty
                          ? _endTurn
                          : null,
                      mentionNames: mentionNames,
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

    final runtimeOpen = _showRuntimePanel && showOwnerControls;
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
                      child: AgentRuntimePanel(
                        width: kRuntimeDefault,
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
                                  .clamp(kRuntimeMin, kRuntimeMax),
                            ),
                            onReset: () => setState(
                              () => _runtimeWidth = kRuntimeDefault,
                            ),
                          ),
                          AgentRuntimePanel(width: _runtimeWidth),
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
    // end.turn closes the caller's waiting stream (`finish_reason: stop`
    // + [DONE]), so their tool treats the reply as complete.
    final ended = ref.read(chatControllerProvider.notifier).endTurn();
    if (!ended && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有可结束的会话。'),
          duration: Duration(seconds: 2),
        ),
      );
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
        return human != null ? '已连接 · ${human.id}' : '已连接';
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
enum _TurnState { yours, theirs, ended, idle }

/// The stream's header: title, the turn state, window actions.
///
/// 72 px on a desktop (it lines up with the list's search bar and the
/// runtime pane's head); 56 px on a phone, where the list button becomes
/// a back arrow and the actions fold into an overflow menu.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.title,
    required this.subtitle,
    required this.conn,
    required this.state,
    required this.sidebarOpen,
    required this.onSidebar,
    required this.actions,
  });

  final bool compact;
  final String title;
  final String subtitle;
  final oh.ConnectionState conn;
  final _TurnState state;
  final bool sidebarOpen;
  final VoidCallback onSidebar;
  final List<BarIcon> actions;

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
    final heading = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: compact ? Ty.title.copyWith(fontSize: 16.5) : Ty.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: compact ? 2 : 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: connColor),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                subtitle,
                style: Ty.meta.copyWith(color: Dk.t3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      // Keep the one action a phone reaches for most (reconnect when it
      // is needed, else the runtime pane) and fold the rest.
      final keep = actions.isEmpty ? null : actions.first;
      final rest = actions.length > 1 ? actions.sublist(1) : <BarIcon>[];
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: Sp.x1),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Dk.line)),
        ),
        child: Row(
          children: [
            BarIcon(
              icon: Icons.arrow_back_rounded,
              tooltip: '会话列表',
              onTap: onSidebar,
            ),
            const SizedBox(width: Sp.x1),
            Expanded(child: heading),
            const SizedBox(width: Sp.x2),
            AnimatedSwitcher(
              duration: Mo.base,
              child: _StatePill(
                key: ValueKey(state),
                state: state,
                dense: true,
              ),
            ),
            if (keep != null) keep,
            if (rest.isNotEmpty) _Overflow(items: rest),
          ],
        ),
      );
    }

    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: Sp.x4, right: Sp.x6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: Row(
        children: [
          BarIcon(
            icon: sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
            tooltip: Touch.primary ? '会话列表' : '会话列表  Ctrl B',
            active: sidebarOpen,
            onTap: onSidebar,
          ),
          const SizedBox(width: Sp.x4),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: heading,
            ),
          ),
          const SizedBox(width: Sp.x5),
          AnimatedSwitcher(
            duration: Mo.base,
            child: _StatePill(key: ValueKey(state), state: state),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// The folded actions of a phone top bar.
class _Overflow extends StatelessWidget {
  const _Overflow({required this.items});
  final List<BarIcon> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: Dk.t2),
      position: PopupMenuPosition.under,
      onSelected: (i) => items[i].onTap?.call(),
      itemBuilder: (c) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: items[i].onTap != null,
            child: Row(
              children: [
                Icon(items[i].icon, size: 18, color: Dk.t2),
                const SizedBox(width: Sp.x3),
                Text(items[i].tooltip, style: Ty.body),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({super.key, required this.state, this.dense = false});
  final _TurnState state;

  /// Phone top bar: shorter label, tighter box.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (label, short, fg, bg) = switch (state) {
      _TurnState.yours => ('等你回复', '等你', Dk.signal, Dk.signalSoft),
      _TurnState.theirs => ('AI 处理中', '处理中', Dk.ok, Dk.okSoft),
      _TurnState.ended => ('本轮已结束', '已结束', Dk.t2, Dk.p3),
      _TurnState.idle => ('空闲', '空闲', Dk.t3, Dk.p2),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: dense
            ? const EdgeInsets.fromLTRB(8, 4, 10, 4)
            : const EdgeInsets.fromLTRB(11, 6, 13, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Rd.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pulse(
              color: fg,
              on: state == _TurnState.yours || state == _TurnState.theirs,
              halo: state == _TurnState.yours,
            ),
            SizedBox(width: dense ? 7 : 9),
            Text(
              dense ? short : label,
              style: Ty.name.copyWith(fontSize: dense ? 12 : 12.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// The state dot. "Your move" breathes slowly in Apricot; "working"
/// breathes in green; idle and ended sit still.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.on, required this.halo});
  final Color color;
  final bool on;
  final bool halo;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.on && Mo.loops) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 7,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.on)
                Container(
                  width: 7 + 10 * v,
                  height: 7 + 10 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(
                        alpha: (widget.halo ? 0.34 : 0.22) * (1 - v)),
                  ),
                ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A square icon button for bars. 36 px on desktop, 44 px on touch; the
/// hover floor is the only acknowledgement a mouse gets, so it is never
/// skipped.
class BarIcon extends StatelessWidget {
  const BarIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final edge = Touch.primary ? 44.0 : 36.0;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Material(
          color: active ? Dk.p3 : Colors.transparent,
          borderRadius: BorderRadius.circular(Rd.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Rd.md),
            hoverColor: Dk.p2,
            focusColor: Dk.p3,
            child: SizedBox(
              width: edge,
              height: edge,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: Dk.t2,
                        ),
                      )
                    : Icon(icon, size: 18, color: active ? Dk.t1 : Dk.t2),
              ),
            ),
          ),
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
    final (fg, bg, text) = retrying
        ? (Dk.warn, Dk.warnSoft, '正在重新连接，期间的回复会在连上后发出。')
        : (Dk.danger, Dk.dangerSoft, '连接已断开，新请求暂时收不到。');
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: EdgeInsets.fromLTRB(g.gutter, Sp.x3, g.right, 0),
        padding: const EdgeInsets.fromLTRB(Sp.x3, 6, 6, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Rd.md),
          border: Border.all(color: fg.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            if (retrying)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
              )
            else
              Icon(Icons.wifi_off_rounded, size: 14, color: fg),
            const SizedBox(width: Sp.x2),
            Expanded(
              child: Text(
                text,
                style: Ty.small.copyWith(color: Dk.t1, fontSize: 12.5),
              ),
            ),
            if (!retrying)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  busy ? '连接中…' : '重新连接',
                  style: Ty.name.copyWith(fontSize: 12.5, color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The runtime pane over the stream on a medium window: slides in from
/// the right over a scrim; a tap on the scrim or Esc closes it.
class _OverlayPane extends StatelessWidget {
  const _OverlayPane({
    required this.open,
    required this.onDismiss,
    required this.child,
  });
  final bool open;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
                right: open ? 0 : -kRuntimeDefault - 24,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Dk.line2)),
                    boxShadow: [
                      BoxShadow(color: Dk.shadow, blurRadius: 40),
                    ],
                  ),
                  child: Focus(autofocus: open, child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndedStrip extends StatelessWidget {
  const _EndedStrip({required this.onResume});
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StreamScope.of(context).gutter,
        0,
        StreamScope.of(context).right,
        Sp.x2,
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 14, color: Dk.t3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本轮已结束。之后的回复会攒到下一轮一起发出。',
              style: Ty.small.copyWith(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onResume,
            child: Text('继续本轮', style: Ty.small.copyWith(color: Dk.t1)),
          ),
        ],
      ),
    );
  }
}
