/// Keeps the console running in the tray when the window is closed.
///
/// This is a console for a service that talks to you — closing the
/// window should not mean the agent cannot reach you. The close button
/// hides the window and leaves an icon in the tray; quitting is a
/// deliberate choice from that icon's menu.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app/tokens.dart';
import '../widgets/window_chrome.dart';

/// Owns the tray icon and intercepts the window's close event.
class TrayService with WindowListener, TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  bool _initialised = false;

  /// True on a desktop where this service owns the window (Windows, Linux).
  bool get active => _initialised;

  /// True once the user has asked to really quit from the tray menu.
  bool _quitting = false;

  /// Wires the window listener, the tray and its menu.
  Future<void> initialize() async {
    if (_initialised || kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux) return;
    _initialised = true;
    final windows = Platform.isWindows;
    // Windows gets the console's own title bar; Linux keeps the
    // desktop's, which users there expect to match their theme.
    WindowChrome.enabled = windows;

    await windowManager.ensureInitialized();

    // The console draws its own title bar (widgets/window_chrome.dart):
    // the system caption is hidden, and the floor colour is set before
    // the first frame so the window never flashes white.
    final options = WindowOptions(
      size: const Size(1320, 840),
      minimumSize: windows ? const Size(880, 560) : const Size(380, 560),
      center: true,
      title: 'OpenHuman',
      backgroundColor: Dk.bg,
      titleBarStyle: windows ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: !windows,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // The interception itself: the close event is refused unless the
    // quit item in the tray menu was what asked for it.
    windowManager.setPreventClose(true);
    windowManager.addListener(this);

    trayManager.addListener(this);
    await _setTrayIcon();
    await trayManager.setToolTip('OpenHuman');
    await _setMenu();
  }

  /// How many people are waiting on a reply, for the tray's hover text.
  int _waiting = -1;

  /// Keep the tray's hover text on whether anyone is waiting on me, so
  /// a glance at the taskbar answers it without opening the window.
  Future<void> setWaiting(int count) async {
    if (!_initialised || count == _waiting) return;
    _waiting = count;
    await trayManager.setToolTip(trayTooltip(count));
  }

  /// Windows wants an .ico, and the runner's own icon is not copied into
  /// the build output — so it ships as an asset and is read from beside
  /// the executable. Without a resolved icon the tray stays empty and
  /// the window would then have no way back.
  Future<void> _setTrayIcon() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = Platform.isWindows
        ? <String>[
            p.join(exeDir, 'data', 'flutter_assets', 'assets', 'tray_icon.ico'),
            p.join(exeDir, 'app_icon.ico'),
            'assets/tray_icon.ico',
            'windows/runner/resources/app_icon.ico',
          ]
        // Linux bundles assets under data/flutter_assets beside the binary.
        : <String>[
            p.join(exeDir, 'data', 'flutter_assets', 'assets', 'tray_icon.png'),
            'assets/tray_icon.png',
          ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        await trayManager.setIcon(candidate);
        return;
      }
    }
    debugPrint('[Tray] no icon found at: ${candidates.join(", ")}');
  }

  Future<void> _setMenu() => trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: '打开 OpenHuman',
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit',
              label: '退出',
            ),
          ],
        ),
      );

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // ── WindowListener ──────────────────────────────────────────

  @override
  void onWindowClose() async {
    if (_quitting) {
      await windowManager.destroy();
      return;
    }
    // Hide rather than exit. The connection stays up, so a message
    // arriving while the window is closed is not lost.
    await windowManager.hide();
  }

  // ── TrayListener ────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() async {
    // A single click is enough on Windows, where the tray icon is
    // always visible. On Linux the indicator opens its menu instead,
    // which carries 打开 OpenHuman.
    await _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
      case 'quit':
        _quitting = true;
        await trayManager.destroy();
        // Now that the flag is set, closing actually closes.
        await windowManager.close();
    }
  }
}

/// The tray's hover text.
String trayTooltip(int waiting) =>
    waiting <= 0 ? 'OpenHuman' : 'OpenHuman · $waiting 条待回复';
