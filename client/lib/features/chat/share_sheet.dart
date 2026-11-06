import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../core/notification_service.dart';
import '../../core/sdk_provider.dart';
import '../../app/adaptive.dart';
import '../../widgets/avatar.dart';
import '../../widgets/controls.dart';
import '../../widgets/sheet.dart';

/// The model name callers pick, as the server has it (it can be renamed
/// and pinned there). Falls back to the protocol default.
final modelNameProvider = FutureProvider.autoDispose<oh.ModelName>((ref) async {
  ref.watch(serverConfigProvider);
  try {
    return await ref.read(openHumanClientProvider).modelName();
  } catch (_) {
    return const oh.ModelName(name: 'openhuman-human');
  }
});

/// The people who hold a key of their own from this seat. `null` when
/// the server predates per-person keys: the sheet then hands out the
/// seat's own key, as before.
final callerKeysProvider =
    FutureProvider.autoDispose<List<oh.CallerKey>?>((ref) async {
  ref.watch(serverConfigProvider);
  try {
    return await ref.read(openHumanClientProvider).callerKeys();
  } catch (_) {
    return null;
  }
});

/// 让别人联系你: what a friend fills into the tool they already use —
/// address, key, model — so that what they type there reaches you here.
///
/// The person is the point: the sheet speaks about a friend reaching you,
/// and keeps the protocol words (Base URL, API Key) as the hints that map
/// onto the fields of their tool.
class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet({super.key});

  static void show(BuildContext context) {
    showDkSheet<void>(
      context,
      maxWidth: 640,
      builder: (ctx) => const ShareSheet(),
    );
  }

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  bool _showApiKey = false;

  /// The key just made, the one time its value is known.
  oh.CallerKey? _fresh;
  bool _making = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final name = _name.text.trim();
    if (name.isEmpty || _making) return;
    setState(() => _making = true);
    try {
      final k = await ref.read(openHumanClientProvider).createCallerKey(name);
      if (!mounted) return;
      setState(() {
        _fresh = k;
        _name.clear();
      });
      ref.invalidate(callerKeysProvider);
    } catch (_) {
      if (mounted) toast(context, '没生成出来，名字最长 48 个字');
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _revoke(oh.CallerKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('收回${k.name}的钥匙？'),
        content: const Text('收回后对方就发不进来了。以前的对话还在。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('收回'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await ref.read(openHumanClientProvider).revokeCallerKey(k.id);
    if (!mounted) return;
    if (_fresh?.id == k.id) setState(() => _fresh = null);
    ref.invalidate(callerKeysProvider);
    toast(context, done ? '已收回${k.name}的钥匙' : '没收回成功，再试一次');
  }

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

  Future<void> _renameModel(String current) async {
    final controller = TextEditingController(text: current)
      ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('改模型名'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: Ty.code.copyWith(fontSize: 14),
            decoration: const InputDecoration(
              hintText: '例如：huang-zhiwen',
              helperText: '朋友在模型列表里看到的就是这个名字。改了之后，旧名字就不能用了',
              helperMaxLines: 2,
            ),
            onSubmitted: (v) => Navigator.of(c).pop(v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current || !mounted) return;
    try {
      final now = await ref.read(openHumanClientProvider).setModelName(name);
      ref.invalidate(modelNameProvider);
      if (mounted) toast(context, '模型名已改为 $now');
    } catch (e) {
      if (!mounted) return;
      final t = e.toString();
      toast(
        context,
        t.contains('locked') || t.contains('pinned')
            ? '服务器管理员固定了模型名，不能改'
            : '这个名字用不了：只能用字母、数字和 - _ .',
      );
    }
  }

  /// Builds shell environment variable export commands.
  String _buildShellEnv({required String baseUrl, required String apiKey}) {
    return '''export OPENAI_BASE_URL="$baseUrl"
export OPENAI_API_KEY="$apiKey"''';
  }

  Widget _specSheet(
    BuildContext context, {
    required String baseUrl,
    required String apiKey,
    required oh.ModelName? model,
    required String modelName,
    required bool ready,
    required String keyLabel,
    required String keyHint,
    required bool showKey,
    required bool canHide,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Dk.bg,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line),
      ),
      child: Column(
        children: [
          _SpecRow(
            label: '接口地址',
            hint: '对方工具里的 Base URL',
            value: baseUrl.isNotEmpty ? baseUrl : '未连接',
            empty: baseUrl.isEmpty,
            onCopy: baseUrl.isNotEmpty
                ? () => _copyToClipboard(context, baseUrl, '接口地址')
                : null,
          ),
          _SpecRow(
            label: keyLabel,
            hint: keyHint,
            value: apiKey.isEmpty
                ? '未配置'
                : showKey
                    ? apiKey
                    : '${apiKey.substring(0, apiKey.length.clamp(0, 4))}'
                        '••••••••••••••••',
            empty: apiKey.isEmpty,
            extra: apiKey.isEmpty || !canHide
                ? null
                : _MiniIcon(
                    icon: _showApiKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    tooltip: _showApiKey ? '隐藏' : '显示',
                    onTap: () => setState(() => _showApiKey = !_showApiKey),
                  ),
            onCopy: apiKey.isNotEmpty
                ? () => _copyToClipboard(context, apiKey, '密钥')
                : null,
          ),
          _SpecRow(
            label: '模型',
            hint: '对方要选的模型名',
            last: true,
            value: modelName,
            // A name of your own reads better in a friend's
            // model list than the protocol default — unless
            // the server owner pinned it.
            extra: model == null || model.locked || !ready
                ? null
                : _MiniIcon(
                    key: const ValueKey('share-rename-model'),
                    icon: Icons.edit_outlined,
                    tooltip: '改模型名',
                    onTap: () => _renameModel(modelName),
                  ),
            onCopy: () => _copyToClipboard(context, modelName, '模型名'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverConfig = ref.watch(serverConfigProvider);
    final baseUrl = _deriveBaseUrl(serverConfig.serverUrl);
    final keys = ref.watch(callerKeysProvider);
    // Per-person keys when the server has them; the seat's own key only
    // on a server that predates them.
    final perPerson = keys.valueOrNull != null;
    final fresh = _fresh;
    final apiKey = perPerson ? (fresh?.apiKey ?? '') : serverConfig.apiKey;
    final model = ref.watch(modelNameProvider).valueOrNull;
    final modelName = model?.name ?? 'openhuman-human';
    final me = ref.watch(currentHumanProvider)?.displayName;
    final fcmToken = NotificationService.fcmToken;
    final ready = baseUrl.isNotEmpty && apiKey.isNotEmpty;
    final connected = baseUrl.isNotEmpty;

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
                    Text('让别人联系你', style: Ty.title.copyWith(fontSize: 18)),
                    const SizedBox(height: 4),
                    const Text(
                      '对方在自己常用的工具里填三项，打的字就会到你这里，'
                      '你在这里回复。每人一把钥匙，随时能单独收回。',
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
                // ── Who gets a key (per-person keys) ──
                if (perPerson) ...[
                  _NewKey(
                    controller: _name,
                    busy: _making,
                    enabled: connected,
                    onMake: _make,
                  ),
                  const SizedBox(height: Sp.x4),
                ],
                if (perPerson && fresh != null) ...[
                  _FreshBanner(name: fresh.name),
                  const SizedBox(height: Sp.x3),
                ],
                // ── Spec sheet ──
                if (!perPerson || fresh != null) ...[
                  _specSheet(
                    context,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    model: model,
                    modelName: modelName,
                    ready: ready,
                    keyLabel: fresh != null ? '${fresh.name}的密钥' : '密钥',
                    keyHint: fresh != null ? '只显示这一次，现在复制' : '对方工具里的 API Key',
                    showKey: fresh != null || _showApiKey,
                    canHide: fresh == null,
                  ),
                  const SizedBox(height: Sp.x5),
                  const Text('复制', style: Ty.label),
                  const SizedBox(height: Sp.x2),
                  _CopyAction(
                    key: const ValueKey('share-friend'),
                    icon: Icons.forward_to_inbox_outlined,
                    title: fresh != null ? '复制发给${fresh.name}的话' : '复制发给朋友的话',
                    detail: '一段说明，直接发到聊天或邮件里',
                    primary: true,
                    onTap: ready
                        ? () => _copyToClipboard(
                              context,
                              friendNote(
                                baseUrl: baseUrl,
                                apiKey: apiKey,
                                modelName: modelName,
                                me: me,
                                to: fresh?.name,
                              ),
                              '给朋友的说明',
                            )
                        : null,
                  ),
                  const SizedBox(height: Sp.x2),
                  _CopyAction(
                    icon: Icons.integration_instructions_outlined,
                    title: '复制给对方工具的配置说明',
                    detail: '对方贴进自己的工具，工具会自己配好',
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
                ],
                // ── Who holds one ──
                if (perPerson && keys.value!.isNotEmpty) ...[
                  const SizedBox(height: Sp.x5),
                  const Text('拿着钥匙的人', style: Ty.label),
                  const SizedBox(height: Sp.x2),
                  _Holders(keys: keys.value!, onRevoke: _revoke),
                ],
                const SizedBox(height: Sp.x4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.shield_outlined, size: 14, color: Dk.t3),
                    ),
                    const SizedBox(width: Sp.x2),
                    Expanded(
                      child: Text(
                        '${perPerson ? '钥匙只能用来给你发消息，不能替你回复；谁的钥匙出了问题，单独收回就行。' : '拿到密钥的人都能给你发消息，只发给信任的人。'}'
                        '${fcmToken != null ? '手机推送已开启，锁屏也能收到。' : ''}',
                        style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (!connected) ...[
                  const SizedBox(height: Sp.x3),
                  Text(
                    '连接服务器后才能用。',
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
    this.last = false,
  });

  final String label;
  final String hint;
  final String value;
  final VoidCallback? onCopy;
  final Widget? extra;
  final bool empty;
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
        color: empty ? Dk.t3 : Dk.t1,
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
    super.key,
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
    super.key,
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

/// Words to send a friend as they are, by chat or mail.
String friendNote({
  required String baseUrl,
  required String apiKey,
  required String modelName,
  String? me,
  String? to,
}) {
  return '''${to == null ? '' : '$to，'}${me == null ? '我' : '我（$me）'}在用 OpenHuman，你可以在自己常用的工具里直接给我发消息。

在 Claude Code、Cursor、WorkBuddy 这类支持「OpenAI 兼容」的工具里，新加一个模型服务，填这三项：

接口地址（Base URL）：$baseUrl
密钥（API Key）：$apiKey
模型：$modelName

然后选这个模型发消息就行。消息会直接到我这里，我回的话会出现在你那边。

这把密钥是专门给你的，请别转发。''';
}

/// Name someone and make them a key.
class _NewKey extends StatelessWidget {
  const _NewKey({
    required this.controller,
    required this.busy,
    required this.enabled,
    required this.onMake,
  });
  final TextEditingController controller;
  final bool busy;
  final bool enabled;
  final VoidCallback onMake;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x3, Sp.x3),
      decoration: BoxDecoration(
        color: Dk.bg,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('给谁一把钥匙', style: Ty.name),
          const SizedBox(height: 2),
          Text(
            '写上对方的名字，对方发来的消息就会以这个名字出现在你这里。',
            style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3),
          ),
          const SizedBox(height: Sp.x3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('share-new-name'),
                  controller: controller,
                  enabled: enabled && !busy,
                  maxLength: 48,
                  decoration: const InputDecoration(
                    hintText: '例如：林晓',
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => onMake(),
                ),
              ),
              const SizedBox(width: Sp.x2),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, v, _) => FilledButton(
                  key: const ValueKey('share-make-key'),
                  onPressed: enabled && !busy && v.text.trim().isNotEmpty
                      ? onMake
                      : null,
                  child: Text(busy ? '生成中…' : '生成钥匙'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The key just made: say plainly it shows once.
class _FreshBanner extends StatelessWidget {
  const _FreshBanner({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
      decoration: BoxDecoration(
        color: Dk.signalSoft,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.signalEdge),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_rounded, size: 16, color: Dk.signal),
          const SizedBox(width: Sp.x3),
          Expanded(
            child: Text(
              '$name的钥匙做好了。密钥只显示这一次，关掉前把说明发给$name。',
              style: Ty.small.copyWith(color: Dk.t1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everyone holding a key, with the one control that matters: take it back.
class _Holders extends StatelessWidget {
  const _Holders({required this.keys, required this.onRevoke});
  final List<oh.CallerKey> keys;
  final void Function(oh.CallerKey) onRevoke;

  @override
  Widget build(BuildContext context) {
    // Live keys first (newest on top), then the ones already taken back.
    final rows = [
      ...keys.where((k) => !k.revoked).toList().reversed,
      ...keys.where((k) => k.revoked).toList().reversed,
    ];
    return Container(
      decoration: BoxDecoration(
        color: Dk.bg,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: Dk.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Dk.line)),
              ),
              child: Row(
                children: [
                  Opacity(
                    opacity: rows[i].revoked ? 0.4 : 1,
                    child: PersonAvatar(name: rows[i].name, size: 26),
                  ),
                  const SizedBox(width: Sp.x3),
                  Expanded(
                    child: Text(
                      rows[i].name,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.name.copyWith(
                        color: rows[i].revoked ? Dk.t3 : Dk.t1,
                      ),
                    ),
                  ),
                  if (rows[i].revoked)
                    Padding(
                      padding: const EdgeInsets.only(right: Sp.x3),
                      child: Text(
                        '已收回',
                        style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
                      ),
                    )
                  else
                    TextButton(
                      key: ValueKey('share-revoke-${rows[i].id}'),
                      onPressed: () => onRevoke(rows[i]),
                      child: const Text('收回'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
