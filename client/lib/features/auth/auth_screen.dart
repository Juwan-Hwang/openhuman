/// Auth screen — connect to the OpenHuman server.
///
/// This screen collects the WebSocket server URL and API key,
/// then calls `client.connect()` and navigates to the chat screen
/// on success.
library;

import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notification_service.dart';
import '../../core/sdk_provider.dart';

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
    final hasBoth = (savedUrl?.isNotEmpty ?? false) &&
        (savedKey?.isNotEmpty ?? false);
    if (hasBoth && mounted) {
      await _connect();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (url.isEmpty || apiKey.isEmpty) {
      setState(() => _error = 'Please enter both URL and API key.');
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
            _error =
                'Connection failed (status: ${client.currentState.name}). Check URL & Key.';
          });
        }
      }
    } on Object catch (e, st) {
      debugPrint('[AuthScreen] Exception during connect: $e\n$st');
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Connection error: $e';
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
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo / Title ──
                Icon(
                  Icons.hub_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'OpenHuman',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Human-as-an-API Runtime',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Server URL ──
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: '例如: wss://your-server.com/ws',
                    helperText: '支持公网 wss:// 或本地 ws:// 协议地址',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  enabled: !_connecting,
                ),
                const SizedBox(height: 16),

                // ── API Key ──
                TextField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: '例如: ohk_xxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  obscureText: _obscureApiKey,
                  enabled: !_connecting,
                ),
                const SizedBox(height: 24),

                // ── Error message ──
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Connect button ──
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: _connecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
