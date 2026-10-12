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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:openhuman_client/features/chat/chat_theme.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sdk_provider.dart';
import 'agent_integration_sheet.dart';
import 'agent_runtime_panel.dart';
import 'chat_controller.dart';
import 'conversation_sidebar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _showRuntimePanel = false;
  bool _showSidebar = false;
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

    final theme = Theme.of(context);
    final controller = ref.read(chatControllerProvider.notifier);
    final humanUser = controller.humanUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_showSidebar ? Icons.menu_open_rounded : Icons.menu_rounded),
          onPressed: () => setState(() => _showSidebar = !_showSidebar),
          tooltip: 'Conversations',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(human?.displayName ?? 'OpenHuman'),
            const SizedBox(height: 2),
            Text(
              _connectionStateLabel(connState, human),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _connectionStateColor(connState, theme),
              ),
            ),
          ],
        ),
        actions: [
          // ── Reconnect ──
          // The socket is reclaimed upstream when it idles, so being
          // dropped is routine. Without this the only way back is a
          // restart, which also throws away the loaded history.
          if (connState != oh.ConnectionState.connected)
            IconButton(
              onPressed: _reconnecting ? null : _reconnect,
              icon: _reconnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'Reconnect',
            ),
          // ── End Turn button ──
          if (_turnEnded)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: const Text('Turn ended'),
                avatar: const Icon(Icons.check_circle, size: 16),
                onPressed: () => setState(() => _turnEnded = false),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _endTurn(),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('End Turn'),
              ),
            ),
          // ── Toggle Runtime Panel ──
          IconButton(
            onPressed: () => setState(() => _showRuntimePanel = !_showRuntimePanel),
            icon: Icon(
              _showRuntimePanel
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
            ),
            tooltip: 'Agent Runtime',
          ),
          // ── Agent Integration Guide ──
          IconButton(
            onPressed: () => AgentIntegrationSheet.show(context),
            icon: const Icon(Icons.integration_instructions_outlined),
            tooltip: 'Agent 接入配置与指南',
          ),
          // ── Connection dot ──
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _connectionStateDotColor(connState, theme),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // ── Conversation Sidebar ──
            if (_showSidebar) const ConversationSidebar(),
            // ── Chat area ──
            Expanded(
              child: Column(
                children: [
                  // Turn-ended banner
                  if (_turnEnded)
                    Material(
                      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined,
                                size: 18, color: theme.colorScheme.tertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Turn ended — your replies will be batched '
                                'and sent when you start a new turn.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Chat messages
                  Expanded(
                    child: Chat(
                      messages: messages,
                      onSendPressed: _turnEnded
                          ? (_) {} // disabled
                          : (partialText) {
                              final sent =
                                  controller.sendReply(partialText.text);
                              if (!sent && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('未连接 — 请先重连后再发送。'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                      user: humanUser,
                      // Without this the chat kept the library's own
                      // theme and the console looked half restyled.
                      theme: buildChatTheme(
                        isDark: theme.brightness == Brightness.dark,
                      ),
                      showUserNames: true,
                      // Agents commonly send inline images as
                      // `data:image/...;base64,` URLs, which the default
                      // network image provider cannot load.
                      imageMessageBuilder: _buildImageMessage,
                    ),
                  ),
                ],
              ),
            ),
            // ── Agent Runtime Panel ──
            if (_showRuntimePanel) const AgentRuntimePanel(),
          ],
        ),
      ),
    );
  }

  /// Renders an image message, including inline `data:` URLs.
  ///
  /// The default builder hands the URI to a network image provider, which
  /// fails on the base64 payloads agents actually send.
  Widget _buildImageMessage(
    types.ImageMessage message, {
    required int messageWidth,
  }) {
    const maxHeight = 320.0;
    final uri = message.uri;

    ImageProvider? provider;
    if (uri.startsWith('data:')) {
      final comma = uri.indexOf(',');
      if (comma != -1 && comma < uri.length - 1) {
        final bytes = base64Decode(uri.substring(comma + 1));
        provider = MemoryImage(bytes);
      }
    } else if (uri.startsWith('http://') || uri.startsWith('https://')) {
      provider = NetworkImage(uri);
    }

    if (provider == null) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Padding(
            padding: EdgeInsets.all(12),
            child: Text('图片无法显示'),
          ),
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
    final conversationId =
        ref.read(activeConversationIdProvider) ??
            (client.activeConversations.isNotEmpty
                ? client.activeConversations.first
                : null);
    if (conversationId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active conversation to end.'),
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
        return 'Not connected';
      case oh.ConnectionState.connecting:
        return 'Connecting…';
      case oh.ConnectionState.connected:
        return human != null ? 'Connected as ${human.id}' : 'Connected';
      case oh.ConnectionState.reconnecting:
        return 'Reconnecting…';
      case oh.ConnectionState.disconnected:
        return 'Disconnected';
      case oh.ConnectionState.error:
        return 'Connection error';
    }
  }

  Color _connectionStateDotColor(oh.ConnectionState state, ThemeData theme) {
    switch (state) {
      case oh.ConnectionState.connected:
        return const Color(0xFF639922);
      case oh.ConnectionState.connecting:
      case oh.ConnectionState.reconnecting:
        return const Color(0xFF8A7355);
      case oh.ConnectionState.disconnected:
      case oh.ConnectionState.idle:
        return theme.colorScheme.outline;
      case oh.ConnectionState.error:
        return theme.colorScheme.error;
    }
  }

  Color _connectionStateColor(oh.ConnectionState state, ThemeData theme) {
    switch (state) {
      case oh.ConnectionState.connected:
        return const Color(0xFF639922);
      case oh.ConnectionState.connecting:
      case oh.ConnectionState.reconnecting:
        return const Color(0xFF8A7355);
      case oh.ConnectionState.disconnected:
      case oh.ConnectionState.idle:
        return theme.colorScheme.onSurfaceVariant;
      case oh.ConnectionState.error:
        return theme.colorScheme.error;
    }
  }
}
