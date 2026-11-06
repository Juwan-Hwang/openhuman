/// Auth screen — connect to the OpenHuman server.
///
/// This screen collects the WebSocket server URL and API key,
/// then calls `client.connect()` and navigates to the chat screen
/// on success.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notification_service.dart';
import '../../core/sdk_provider.dart';
import '../../app/adaptive.dart';
import '../../widgets/brand.dart';

/// Screen for entering server URL and API key.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static const _prefServerUrlKey = 'openhuman_server_url';
  static const _prefApiKeyKey = 'openhuman_api_key';

  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  bool _connecting = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    String? savedUrl;
    String? savedKey;

    try {
      final prefs = await SharedPreferences.getInstance();
      savedUrl = prefs.getString(_prefServerUrlKey);
      savedKey = prefs.getString(_prefApiKeyKey);

      if (mounted) {
        if (savedUrl != null && savedUrl.isNotEmpty) {
          _urlController.text = savedUrl;
        }
        if (savedKey != null && savedKey.isNotEmpty) {
          _apiKeyController.text = savedKey;
        }
      }
    } catch (e) {
      debugPrint('[AuthScreen] Failed to load config: $e');
      return;
    }

    // Credentials are remembered, so make the remembered state real.
    // Otherwise every launch drops the console back to "Not connected"
    // with an empty conversation list until someone clicks Connect.
    final hasBoth =
        (savedUrl?.isNotEmpty ?? false) && (savedKey?.isNotEmpty ?? false);
    if (hasBoth && mounted) {
      await _connect();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (url.isEmpty || apiKey.isEmpty) {
      setState(() => _error = '请输入服务器地址和 API 密钥。');
      return;
    }

    // Clean up any stray non-ascii characters or accidental copy-paste symbols
    var cleanUrl = url.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    final cleanApiKey = apiKey.trim();

    debugPrint('[AuthScreen] Connecting to: "$cleanUrl"');

    setState(() {
      _connecting = true;
      _error = null;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_connecting) {
        _ticker?.cancel();
        return;
      }
      setState(() {});
    });

    final client = ref.read(openHumanClientProvider);

    try {
      // If already connected, proceed immediately
      if (client.currentState == oh.ConnectionState.connected) {
        _onConnectSuccess(cleanUrl, cleanApiKey);
        return;
      }

      await client.connect(
        cleanUrl,
        cleanApiKey,
        deviceToken: NotificationService.fcmToken,
      );

      // Poll rather than racing a single short timeout. A handshake on a
      // slow link can take well past a few seconds, and failing fast here
      // meant the console just sat on "Not connected" with no clue why.
      var isConnected = client.currentState == oh.ConnectionState.connected;
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!isConnected && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        isConnected = client.currentState == oh.ConnectionState.connected;
      }

      if (isConnected && mounted) {
        await _onConnectSuccess(cleanUrl, cleanApiKey);
      } else {
        if (mounted) {
          setState(() {
            _connecting = false;
            _error = '无法连接。请检查地址和密钥。';
          });
        }
      }
    } on Object catch (e, st) {
      debugPrint('[AuthScreen] Exception during connect: $e\n$st');
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '无法连接：$e';
        });
      }
    }
  }

  Future<void> _onConnectSuccess(String url, String apiKey) async {
    // Persist successful connection credentials
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerUrlKey, url);
      await prefs.setString(_prefApiKeyKey, apiKey);
    } catch (e) {
      debugPrint('[AuthScreen] Failed to save config: $e');
    }

    // Cache into runtime state for quick access across features
    ref.read(serverConfigProvider.notifier).state =
        ServerConfig(serverUrl: url, apiKey: apiKey);

    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Dk.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (!_connecting) _connect();
          },
        },
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal:
                  MediaQuery.sizeOf(context).width < 480 ? Sp.x4 : Sp.x8,
              vertical: Sp.x8,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Hero: the mark winks while it waits for the server.
                  SizedBox(
                    height: 132,
                    child: BrandHalo(
                      radius: 120,
                      child: Center(
                        child: BrandMark(
                          size: 76,
                          wink: _connecting ? BrandWink.busy : BrandWink.once,
                        ),
                      ),
                    ),
                  ),
                  const Center(child: BrandWordmark(height: 26)),
                  const SizedBox(height: Sp.x3),
                  Text(
                    '连接到你的服务器',
                    textAlign: TextAlign.center,
                    style: Ty.small.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: Sp.x8),
                  Container(
                    decoration: BoxDecoration(
                      color: Dk.p1,
                      borderRadius: BorderRadius.circular(Rd.xl),
                      border: Border.all(color: Dk.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Dk.shadow,
                          blurRadius: 80,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 22, 28, 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _FieldLabel('服务器地址'),
                              _Field(
                                controller: _urlController,
                                hint: 'wss://your-server.com/ws',
                                icon: Icons.dns_outlined,
                                enabled: !_connecting,
                                autofocus: true,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '例如 wss://example.com/ws',
                                style: Ty.small.copyWith(
                                  fontSize: 11.5,
                                  color: Dk.t3,
                                ),
                              ),
                              const SizedBox(height: Sp.x5),
                              const _FieldLabel('API 密钥'),
                              _Field(
                                controller: _apiKeyController,
                                hint: 'ohk_xxxxxxxxxxxx',
                                icon: Icons.key_outlined,
                                enabled: !_connecting,
                                obscure: _obscureApiKey,
                                trailing: IconButton(
                                  tooltip: _obscureApiKey ? '显示' : '隐藏',
                                  iconSize: 17,
                                  icon: Icon(
                                    _obscureApiKey
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Dk.t3,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureApiKey = !_obscureApiKey,
                                  ),
                                ),
                              ),
                              const SizedBox(height: Sp.x6),

                              // ── Error ──
                              AnimatedSize(
                                duration: Mo.base,
                                curve: Mo.expo,
                                child: _error == null
                                    ? const SizedBox(width: double.infinity)
                                    : Container(
                                        margin: const EdgeInsets.only(
                                            bottom: Sp.x4),
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          10,
                                          12,
                                          10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Dk.dangerSoft,
                                          borderRadius:
                                              BorderRadius.circular(Rd.md),
                                          border: Border.all(
                                            color: Dk.dangerEdge,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(top: 1),
                                              child: Icon(
                                                Icons.error_outline_rounded,
                                                color: Dk.danger,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: SelectableText(
                                                _error!,
                                                style: Ty.small.copyWith(
                                                  color: Dk.dangerInk,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),

                              // ── Connect ──
                              SizedBox(
                                height: 42,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Dk.t1,
                                    foregroundColor: Dk.ink,
                                    disabledBackgroundColor: Dk.p3,
                                    disabledForegroundColor: Dk.t2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(Rd.md),
                                    ),
                                    textStyle: Ty.name.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onPressed: _connecting ? null : _connect,
                                  child: _connecting
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              height: 14,
                                              width: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.6,
                                                color: Dk.t2,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text('正在连接…'),
                                          ],
                                        )
                                      : const Text('连接'),
                                ),
                              ),
                              const SizedBox(height: Sp.x3),
                              Center(
                                child: Text(
                                  Touch.primary ? '将自动登录' : '按 Return 键连接',
                                  style: Ty.small.copyWith(
                                    fontSize: 11.5,
                                    color: Dk.t3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Ty.name.copyWith(fontSize: 12.5, color: Dk.t2),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.enabled,
    this.obscure = false,
    this.autofocus = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscure;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: c),
        );
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      autofocus: autofocus,
      style: Ty.code.copyWith(fontSize: 13, color: Dk.t1, height: 1.4),
      cursorColor: Dk.signal,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Dk.bg,
        hintText: hint,
        hintStyle: Ty.code.copyWith(fontSize: 13, color: Dk.t4, height: 1.4),
        prefixIcon: Icon(icon, size: 16, color: Dk.t3),
        suffixIcon: trailing,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 20, maxHeight: 40),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: edge(Dk.line2),
        enabledBorder: edge(Dk.line2),
        disabledBorder: edge(Dk.line),
        focusedBorder: edge(Dk.t3),
      ),
    );
  }
}
