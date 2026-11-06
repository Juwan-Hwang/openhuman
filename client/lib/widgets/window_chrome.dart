/// The console's own window chrome: a slim title bar drawn in the
/// Darkroom palette, with drag-to-move, double-click to maximise and
/// Windows-style caption buttons.
///
/// Only drawn when [WindowChrome.enabled] is set (the desktop window
/// hid its system caption); in tests and on platforms that keep the
/// native caption, the child is returned untouched.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/tokens.dart';
import 'brand.dart';

class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key, required this.child});

  final Widget child;

  /// Set by the desktop bootstrap once the system caption is hidden.
  static bool enabled = false;

  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ColoredBox(
      color: Dk.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the Navigator, so it brings its own Material.
          const Material(type: MaterialType.transparency, child: TitleBar()),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    if (WindowChrome.enabled) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _maximized = v);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    if (WindowChrome.enabled) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMax() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = _focused ? Dk.t2 : Dk.t4;
    return Container(
      height: WindowChrome.height,
      decoration: const BoxDecoration(
        color: Dk.bg,
        border: Border(bottom: BorderSide(color: Dk.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMax,
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Row(
                  children: [
                    AnimatedOpacity(
                      duration: Mo.base,
                      opacity: _focused ? 1 : 0.45,
                      child: const BrandMark(size: 16),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'OpenHuman',
                      style: Ty.small.copyWith(
                        fontSize: 12,
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CaptionButton(
            tooltip: '最小化',
            icon: Icons.remove_rounded,
            ink: ink,
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            tooltip: _maximized ? '还原' : '最大化',
            icon: _maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _maximized ? 12 : 14,
            ink: ink,
            onTap: _toggleMax,
          ),
          _CaptionButton(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            ink: ink,
            danger: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.ink,
    required this.onTap,
    this.iconSize = 15,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final Color ink;
  final VoidCallback onTap;
  final double iconSize;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? Dk.closeRed
            : Dk.p3;
    final fg = _hover ? Dk.t1 : widget.ink;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Mo.fast,
            width: 46,
            height: WindowChrome.height,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
