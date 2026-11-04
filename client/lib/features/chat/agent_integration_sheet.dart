import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_service.dart';
import '../../core/sdk_provider.dart';
import '../../app/adaptive.dart';
import '../../widgets/sheet.dart';

/// Modal bottom sheet displaying OpenAI-compatible configuration and
/// self-configuring prompts for AI agents (WorkBuddy, Trae, Cursor, Windsurf, Claude Code).
class AgentIntegrationSheet extends ConsumerStatefulWidget {
  const AgentIntegrationSheet({super.key});

  static void show(BuildContext context) {
    showDkSheet<void>(
      context,
      maxWidth: 640,
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
    final serverConfig = ref.watch(serverConfigProvider);
    final baseUrl = _deriveBaseUrl(serverConfig.serverUrl);
    final apiKey = serverConfig.apiKey;
    const modelName = 'openhuman-human';
    final fcmToken = NotificationService.fcmToken;
    final ready = baseUrl.isNotEmpty && apiKey.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x2, Sp.x3, Sp.x4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('接入 AI', style: Ty.title.copyWith(fontSize: 18)),
                    const SizedBox(height: 4),
                    const Text(
                      '把你自己当成一个兼容 OpenAI 的模型，交给任何 AI 工具调用。'
                      'AI 需要你时，请求会出现在这个控制台。',
                      style: Ty.small,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close_rounded, size: 18, color: Dk.t2),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Sp.x6, 0, Sp.x6, Sp.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Spec sheet ──
                Container(
                  decoration: BoxDecoration(
                    color: Dk.bg,
                    borderRadius: BorderRadius.circular(Rd.lg),
                    border: Border.all(color: Dk.line),
                  ),
                  child: Column(
                    children: [
                      _SpecRow(
                        label: '接口地址',
                        hint: '由服务器地址推导',
                        value: baseUrl.isNotEmpty ? baseUrl : '未连接',
                        empty: baseUrl.isEmpty,
                        onCopy: baseUrl.isNotEmpty
                            ? () => _copyToClipboard(context, baseUrl, '接口地址')
                            : null,
                      ),
                      _SpecRow(
                        label: '密钥',
                        hint: '当前连接使用的令牌',
                        value: apiKey.isEmpty
                            ? '未配置'
                            : _showApiKey
                                ? apiKey
                                : '${apiKey.substring(0, apiKey.length.clamp(0, 4))}'
                                    '••••••••••••••••',
                        empty: apiKey.isEmpty,
                        extra: apiKey.isEmpty
                            ? null
                            : _MiniIcon(
                                icon: _showApiKey
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                tooltip: _showApiKey ? '隐藏' : '显示',
                                onTap: () =>
                                    setState(() => _showApiKey = !_showApiKey),
                              ),
                        onCopy: apiKey.isNotEmpty
                            ? () => _copyToClipboard(context, apiKey, '密钥')
                            : null,
                      ),
                      _SpecRow(
                        label: '模型名',
                        hint: '调用时填写的 model',
                        value: modelName,
                        onCopy: () =>
                            _copyToClipboard(context, modelName, '模型名'),
                      ),
                      _SpecRow(
                        label: '手机推送',
                        hint:
                            fcmToken != null ? '已注册，锁屏也能收到请求' : '桌面与网页通过长连接接收',
                        value: fcmToken != null
                            ? '${fcmToken.substring(0, 10)}…'
                                '${fcmToken.substring(fcmToken.length - 6)}'
                            : '未注册',
                        empty: fcmToken == null,
                        good: fcmToken != null,
                        last: true,
                        onCopy: fcmToken != null
                            ? () => _copyToClipboard(context, fcmToken, '推送令牌')
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Sp.x5),
                const Text('一键复制', style: Ty.label),
                const SizedBox(height: Sp.x2),
                _CopyAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '给 AI 的配置说明',
                  detail: '粘贴给任意 AI 工具，它会把你配置成可联系的端点',
                  primary: true,
                  onTap: ready
                      ? () => _copyToClipboard(
                            context,
                            _buildAgentPrompt(
                              baseUrl: baseUrl,
                              apiKey: apiKey,
                              modelName: modelName,
                            ),
                            '配置说明',
                          )
                      : null,
                ),
                const SizedBox(height: Sp.x2),
                _CopyAction(
                  icon: Icons.terminal_rounded,
                  title: '终端环境变量',
                  detail: 'OPENAI_BASE_URL 与 OPENAI_API_KEY',
                  onTap: ready
                      ? () => _copyToClipboard(
                            context,
                            _buildShellEnv(baseUrl: baseUrl, apiKey: apiKey),
                            '环境变量',
                          )
                      : null,
                ),
                if (!ready) ...[
                  const SizedBox(height: Sp.x3),
                  Text(
                    '连接服务器后才能复制。',
                    style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of the spec sheet: label on the left, the value in mono, and
/// a copy control that confirms in place.
class _SpecRow extends StatelessWidget {
  const _SpecRow({
    required this.label,
    required this.hint,
    required this.value,
    this.onCopy,
    this.extra,
    this.empty = false,
    this.good = false,
    this.last = false,
  });

  final String label;
  final String hint;
  final String value;
  final VoidCallback? onCopy;
  final Widget? extra;
  final bool empty;
  final bool good;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Ty.name),
        const SizedBox(height: 2),
        Text(hint, style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3)),
      ],
    );
    final val = SelectableText(
      value,
      maxLines: 1,
      style: Ty.code.copyWith(
        height: 1.4,
        fontSize: 12.5,
        color: empty
            ? Dk.t3
            : good
                ? Dk.ok
                : Dk.t1,
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (extra != null) extra!,
        if (onCopy != null)
          _MiniIcon(icon: Icons.copy_rounded, tooltip: '复制', onTap: onCopy!),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x2, Sp.x3),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Expanded(child: head), actions]),
                const SizedBox(height: Sp.x2),
                val,
              ],
            )
          : Row(
              children: [
                SizedBox(width: 150, child: head),
                const SizedBox(width: Sp.x3),
                Expanded(child: val),
                actions,
              ],
            ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final edge = Touch.target;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.sm),
        hoverColor: Dk.p3,
        child: SizedBox(
          width: edge,
          height: edge,
          child: Icon(icon, size: 15, color: Dk.t2),
        ),
      ),
    );
  }
}

/// A large copy target: what you get, and where it goes.
class _CopyAction extends StatelessWidget {
  const _CopyAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final fg = primary && on ? Dk.ink : (on ? Dk.t1 : Dk.t3);
    return Material(
      color: primary && on ? Dk.t1 : Dk.p2,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        hoverColor: primary ? Dk.mineCode : Dk.p3,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: primary && on ? Colors.transparent : Dk.line2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Ty.name.copyWith(color: fg)),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: Ty.small.copyWith(
                        fontSize: 12,
                        color: primary && on ? Dk.mineMuted : Dk.t3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.content_copy_rounded, size: 15, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
