/// Chat screen — the main communication UI.
///
/// Layout:
/// ```
/// ┌──────────────┬──────────────────────┬───────────────┐
/// │ Conversation │  Message Timeline   │  Agent Runtime │
/// │   Sidebar     │  (newest at bottom) │    Panel       │
/// │ (friend list)│                     │               │
/// │              ├──────────────────────┤               │
/// │              │  [End Turn] [Input]  │               │
/// └──────────────┴──────────────────────┴───────────────┘
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
import '../../widgets/pane_divider.dart';

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
      _showSidebar = MediaQuery.sizeOf(context).width >= 1100;
    }
  }

  void _focusSearch() {
    setState(() => _showSidebar = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => sidebarSearchFocus.requestFocus(),
    );
  }

  bool _turnEnded = false;
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

    // A new inbound message from the agent means a new turn has begun —
    // automatically re-open the input so the human can reply again.
    ref.listen(chatControllerProvider, (prev, next) {
      if (next.length > (prev?.length ?? 0) && _turnEnded) {
        setState(() => _turnEnded = false);
      }
    });

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
              () => setState(() => _showRuntimePanel = !_showRuntimePanel),
      },
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: _scaffold(
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
    );
  }

  Widget _scaffold(
    BuildContext context, {
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
    return Scaffold(
      backgroundColor: Dk.bg,
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Conversation Sidebar ──
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
            // ── Stream ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    title: activeInfo?.displayName ??
                        human?.displayName ??
                        'OpenHuman',
                    subtitle: _connectionStateLabel(connState, human),
                    conn: connState,
                    state: _turnEnded
                        ? _TurnState.ended
                        : waitingOnMe
                            ? _TurnState.yours
                            : messages.isEmpty
                                ? _TurnState.idle
                                : _TurnState.theirs,
                    sidebarOpen: _showSidebar,
                    onSidebar: () =>
                        setState(() => _showSidebar = !_showSidebar),
                    actions: [
                      if (connState != oh.ConnectionState.connected)
                        _BarIcon(
                          icon: Icons.refresh_rounded,
                          tooltip: '重新连接',
                          busy: _reconnecting,
                          onTap: _reconnecting ? null : _reconnect,
                        ),
                      if (isGroup && activeConvId != null)
                        _BarIcon(
                          icon: Icons.groups_outlined,
                          tooltip: '群聊管理',
                          onTap: () => RoomPanel.show(context, activeConvId),
                        ),
                      if (showOwnerControls)
                        _BarIcon(
                          icon: _showRuntimePanel
                              ? Icons.view_sidebar_rounded
                              : Icons.view_sidebar_outlined,
                          tooltip: 'AI 运行信息  Ctrl I',
                          active: _showRuntimePanel,
                          onTap: () => setState(
                            () => _showRuntimePanel = !_showRuntimePanel,
                          ),
                        ),
                      _BarIcon(
                        icon: Icons.integration_instructions_outlined,
                        tooltip: 'AI 接入配置与指南',
                        onTap: () => AgentIntegrationSheet.show(context),
                      ),
                    ],
                  ),
                  Expanded(
                    // A reading column: on a wide window the stream keeps
                    // its measure instead of flinging replies to the edge.
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: Sp.column),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                onResume: () =>
                                    setState(() => _turnEnded = false),
                              ),
                            Composer(
                              enabled: !_turnEnded,
                              onSend: sendText,
                              onEndTurn: showOwnerControls && !_turnEnded
                                  ? _endTurn
                                  : null,
                              mentionNames: mentionNames,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Agent Runtime Panel ──
            AnimatedSize(
              duration: Mo.base,
              curve: Mo.expo,
              alignment: Alignment.centerRight,
              child: _showRuntimePanel && showOwnerControls
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
    setState(() => _turnEnded = true);

    // Send the end.turn signal to the server, which closes the waiting
    // SSE stream with `finish_reason: stop` + [DONE]. WorkBuddy then
    // treats the reply as complete.
    final client = ref.read(openHumanClientProvider);
    final conversationId = ref.read(activeConversationIdProvider) ??
        (client.activeConversations.isNotEmpty
            ? client.activeConversations.first
            : null);
    if (conversationId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前没有可结束的会话。'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    client.endTurn(conversationId);
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

/// The stream's header: title, the turn state pill, window actions.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.conn,
    required this.state,
    required this.sidebarOpen,
    required this.onSidebar,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final oh.ConnectionState conn;
  final _TurnState state;
  final bool sidebarOpen;
  final VoidCallback onSidebar;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final connColor = switch (conn) {
      oh.ConnectionState.connected => Dk.ok,
      oh.ConnectionState.connecting ||
      oh.ConnectionState.reconnecting =>
        const Color(0xFFE0B252),
      oh.ConnectionState.error => Dk.danger,
      _ => Dk.t3,
    };
    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: Sp.x4, right: Sp.x6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: Row(
        children: [
          _BarIcon(
            icon: sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
            tooltip: '会话列表',
            active: sidebarOpen,
            onTap: onSidebar,
          ),
          const SizedBox(width: Sp.x4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Ty.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: connColor),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        subtitle,
                        style: Ty.meta.copyWith(color: Dk.t3),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.x5),
          AnimatedSwitcher(
            duration: Mo.base,
            child: _StatePill(key: ValueKey(state), state: state),
          ),
          const SizedBox(width: Sp.x4),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({super.key, required this.state});
  final _TurnState state;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (state) {
      _TurnState.yours => ('等你回复', Dk.signal, Dk.signalSoft),
      _TurnState.theirs => ('AI 处理中', Dk.ok, Dk.okSoft),
      _TurnState.ended => ('本轮已结束', Dk.t2, Dk.p3),
      _TurnState.idle => ('空闲', Dk.t3, Dk.p2),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 6, 13, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Rd.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg,
              boxShadow: state == _TurnState.yours
                  ? const [BoxShadow(color: Dk.signalRing, spreadRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: Ty.name.copyWith(fontSize: 12.5, color: fg),
          ),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
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
            child: SizedBox(
              width: 36,
              height: 36,
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

class _EndedStrip extends StatelessWidget {
  const _EndedStrip({required this.onResume});
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.x9, Sp.x2),
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
