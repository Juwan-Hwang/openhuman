/// Keeps the console running in the tray when the window is closed.
///
/// This is a console for a service that talks to you — closing the
/// window should not mean the agent cannot reach you. The close button
/// hides the window and leaves an icon in the tray; quitting is a
/// deliberate choice from that icon's menu.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the tray icon and intercepts the window's close event.
class TrayService with WindowListener, TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  bool _initialised = false;

  /// True once the user has asked to really quit from the tray menu.
  bool _quitting = false;

  /// Wires the window listener, the tray and its menu.
  Future<void> initialize() async {
    if (_initialised || !Platform.isWindows) return;
    _initialised = true;

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: Size(1180, 780),
      minimumSize: Size(720, 520),
      center: true,
      title: 'OpenHuman',
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

  /// Windows wants an .ico, and the runner's own icon is not copied into
  /// the build output — so it ships as an asset and is read from beside
  /// the executable. Without a resolved icon the tray stays empty and
  /// the window would then have no way back.
  Future<void> _setTrayIcon() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'tray_icon.ico'),
      p.join(exeDir, 'app_icon.ico'),
      'assets/tray_icon.ico',
      'windows/runner/resources/app_icon.ico',
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
              label: '打开主窗口',
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
    // always visible rather than tucked into a menu bar.
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
