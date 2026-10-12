import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_service.dart';
import '../../core/sdk_provider.dart';

/// Modal bottom sheet displaying OpenAI-compatible configuration and
/// self-configuring prompts for AI agents (WorkBuddy, Trae, Cursor, Windsurf, Claude Code).
class AgentIntegrationSheet extends ConsumerStatefulWidget {
  const AgentIntegrationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AgentIntegrationSheet(),
    );
  }

  @override
  ConsumerState<AgentIntegrationSheet> createState() =>
      _AgentIntegrationSheetState();
}

class _AgentIntegrationSheetState extends ConsumerState<AgentIntegrationSheet> {
  bool _showApiKey = false;

  /// Automatically derives the OpenAI-compatible HTTP Base URL
  /// from the user's WebSocket URL.
  ///
  /// Examples:
  /// - `wss://api.example.com/ws` -> `https://api.example.com/v1`
  /// - `ws://localhost:8080/ws`   -> `http://localhost:8080/v1`
  String _deriveBaseUrl(String serverUrl) {
    if (serverUrl.trim().isEmpty) return '';
    var url = serverUrl.trim();

    if (url.startsWith('wss://')) {
      url = 'https://${url.substring(6)}';
    } else if (url.startsWith('ws://')) {
      url = 'http://${url.substring(5)}';
    }

    final queryIdx = url.indexOf('?');
    if (queryIdx != -1) url = url.substring(0, queryIdx);
    final hashIdx = url.indexOf('#');
    if (hashIdx != -1) url = url.substring(0, hashIdx);

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/ws')) {
      url = url.substring(0, url.length - 3);
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (!url.endsWith('/v1')) {
      url = '$url/v1';
    }
    return url;
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $label 到剪贴板'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Builds a prompt for configuring OpenHuman as a human contact endpoint
  /// in any AI Agent environment (WorkBuddy, Trae, Cursor, Windsurf, Claude Code, etc.).
  String _buildAgentPrompt({
    required String baseUrl,
    required String apiKey,
    required String modelName,
  }) {
    return '''请将以下 OpenHuman 真人联系端点配置到你当前所在的 Agent 环境中：

【端点参数 (OpenAI Compatible)】：
- API Base URL: $baseUrl
- API Key: $apiKey
- Model Name: $modelName

【端点说明与使用约定】：
该端点对应的是真实人类（开发者/联系人）。当你或你的用户想要联系我、向我留言、咨询事宜、或需要与我沟通时，可直接通过调用该模型（或通过该 Provider）向我发送消息。消息会实时推送至我的移动端/客户端，并在我回复后流式返回给你。''';
  }

  /// Builds shell environment variable export commands.
  String _buildShellEnv({required String baseUrl, required String apiKey}) {
    return '''export OPENAI_BASE_URL="$baseUrl"
export OPENAI_API_KEY="$apiKey"''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverConfig = ref.watch(serverConfigProvider);
    final baseUrl = _deriveBaseUrl(serverConfig.serverUrl);
    final apiKey = serverConfig.apiKey;
    const modelName = 'openhuman-human';
    final fcmToken = NotificationService.fcmToken;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agent 联系端点配置与指南',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '将自身作为 API 端点，供其他人及其 Agent 随时与你取得联系',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. OpenAI Compatible Base URL
                  _buildConfigTile(
                    theme: theme,
                    icon: Icons.link_rounded,
                    title: 'OpenAI Base URL (API 端点)',
                    subtitle: '由输入的 WebSocket 地址自动推导',
                    value: baseUrl.isNotEmpty ? baseUrl : '未连接或未配置',
                    onCopy: baseUrl.isNotEmpty
                        ? () => _copyToClipboard(context, baseUrl, 'API 端点')
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // 2. API Key
                  _buildConfigTile(
                    theme: theme,
                    icon: Icons.vpn_key_outlined,
                    title: 'API Key (凭证密钥)',
                    subtitle: '当前会话所用的 Bearer Token',
                    value: apiKey.isNotEmpty
                        ? (_showApiKey
                            ? apiKey
                            : '••••••••••••••••••••••••••••••••')
                        : '未配置',
                    trailingAction: apiKey.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              _showApiKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            tooltip: _showApiKey ? '隐藏密钥' : '显示密钥',
                            onPressed: () =>
                                setState(() => _showApiKey = !_showApiKey),
                          )
                        : null,
                    onCopy: apiKey.isNotEmpty
                        ? () => _copyToClipboard(context, apiKey, 'API Key')
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // 3. Model Name
                  _buildConfigTile(
                    theme: theme,
                    icon: Icons.psychology_outlined,
                    title: 'Model Name (模型标识)',
                    subtitle: '标准人类专家路由模型',
                    value: modelName,
                    onCopy: () =>
                        _copyToClipboard(context, modelName, '模型标识'),
                  ),
                  const SizedBox(height: 12),

                  // 4. FCM Device Token Status
                  _buildConfigTile(
                    theme: theme,
                    icon: Icons.notifications_active_outlined,
                    title: 'FCM 移动端推送通道',
                    subtitle: fcmToken != null
                        ? 'Google FCM Token 已注册，可接收锁屏离线唤醒'
                        : '移动设备推送就绪 (桌面/Web 环境将走站内长连接)',
                    value: fcmToken != null
                        ? '${fcmToken.substring(0, 16)}...${fcmToken.substring(fcmToken.length - 12)}'
                        : '未生成 Device Token',
                    valueColor: fcmToken != null
                        ? const Color(0xFF639922)
                        : theme.colorScheme.onSurfaceVariant,
                    onCopy: fcmToken != null
                        ? () => _copyToClipboard(
                            context, fcmToken, 'FCM Device Token')
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text(
                      '一键复制 Agent 联系端点配置提示词',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: baseUrl.isNotEmpty && apiKey.isNotEmpty
                        ? () {
                            final prompt = _buildAgentPrompt(
                              baseUrl: baseUrl,
                              apiKey: apiKey,
                              modelName: modelName,
                            );
                            _copyToClipboard(
                              context,
                              prompt,
                              'Agent 联系端点配置提示词',
                            );
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    icon: const Icon(Icons.terminal_rounded),
                    label: const Text('一键复制 Shell 环境变量'),
                    onPressed: baseUrl.isNotEmpty && apiKey.isNotEmpty
                        ? () {
                            final envCmd = _buildShellEnv(
                              baseUrl: baseUrl,
                              apiKey: apiKey,
                            );
                            _copyToClipboard(context, envCmd, 'Shell 环境变量');
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    Color? valueColor,
    Widget? trailingAction,
    VoidCallback? onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (trailingAction != null) trailingAction,
              if (onCopy != null)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: '复制',
                  onPressed: onCopy,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
