/// The console's interactive parts: one pressable core with hover,
/// keyboard focus, press and semantics, and the buttons built on it.
///
/// Every control in the chrome goes through [Pressable], so hover and
/// focus look the same everywhere: a floor one step up on hover, an
/// Apricot ring on keyboard focus (focus is an emphasis, and Apricot is
/// the console's one emphasis), and a slight dip while pressed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/adaptive.dart';
import '../app/tokens.dart';
import 'glyphs.dart';

/// "Ctrl K" on Windows and Linux, "⌘K" on a Mac.
String shortcutLabel(String key, {bool shift = false}) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mac) return '${shift ? '⇧' : ''}⌘$key';
  return 'Ctrl ${shift ? 'Shift ' : ''}$key';
}

/// A tooltip that names a shortcut where there is a keyboard to use it.
String withShortcut(String label, String? key) =>
    key == null || Touch.primary ? label : '$label  ${shortcutLabel(key)}';

typedef PressableBuilder = Widget Function(
  BuildContext context,
  PressState state,
);

/// What a control looks like right now.
class PressState {
  const PressState({
    required this.hovered,
    required this.focused,
    required this.pressed,
    required this.enabled,
  });
  final bool hovered;
  final bool focused;
  final bool pressed;
  final bool enabled;

  bool get lit => enabled && (hovered || focused);
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    required this.onTap,
    required this.semanticLabel,
    this.onSecondaryTapDown,
    this.onLongPressStart,
    this.radius = Rd.md,
    this.ring = true,
    this.selected,
    this.focusNode,
    this.autofocus = false,
    this.cursor = SystemMouseCursors.click,
  });

  final PressableBuilder builder;
  final VoidCallback? onTap;
  final String semanticLabel;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureLongPressStartCallback? onLongPressStart;
  final double radius;

  /// Draw the keyboard focus ring around the control.
  final bool ring;

  /// For toggles and list rows: announced as selected.
  final bool? selected;
  final FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor cursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final state = PressState(
      hovered: _hover,
      focused: _focus,
      pressed: _down,
      enabled: _enabled,
    );
    final body = widget.builder(context, state);
    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: _enabled ? () => setState(() => _down = false) : null,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onLongPressStart: widget.onLongPressStart,
          child: AnimatedScale(
            duration: Mo.of(context, Mo.instant),
            scale: _down ? 0.97 : 1,
            child: widget.ring
                ? FocusRing(
                    on: _focus && _enabled,
                    radius: widget.radius,
                    child: body,
                  )
                : body,
          ),
        ),
      ),
    );
  }
}

/// An Apricot ring drawn just outside [child] while [on].
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.on,
    required this.child,
    this.radius = Rd.md,
  });
  final bool on;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: on ? _RingPainter(radius) : null,
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(Sz.ring),
      Radius.circular(radius + Sz.ring),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Sz.ring
        ..color = Dk.focus,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius;
}

/// A square glyph button. 32 px on a desktop (34 in bars), 44 on touch.
class DkIconButton extends StatelessWidget {
  const DkIconButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.active = false,
    this.busy = false,
    this.bar = false,
    this.color,
    this.glyphSize = Sz.glyph,
  });

  final Glyph glyph;

  /// Tooltip and screen-reader label.
  final String label;

  /// Shown after the label in the tooltip: "K" → "Ctrl K".
  final String? shortcut;
  final VoidCallback? onTap;
  final bool active;
  final bool busy;

  /// Sized for a pane header.
  final bool bar;
  final Color? color;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final edge = Touch.primary
        ? Sz.hitTouch
        : bar
            ? Sz.hitBar
            : Sz.hit;
    return Tooltip(
      message: withShortcut(label, shortcut),
      child: Pressable(
        semanticLabel: label,
        selected: active ? true : null,
        onTap: busy ? null : onTap,
        builder: (context, s) {
          final fg = !s.enabled && !busy
              ? Dk.t4
              : active || s.lit
                  ? Dk.t1
                  : (color ?? Dk.t2);
          return AnimatedContainer(
            duration: Mo.of(context, Mo.instant),
            width: edge,
            height: edge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? Dk.p3
                  : s.lit
                      ? Dk.p2
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(Rd.md),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: Sz.glyphSm,
                    child: CircularProgressIndicator(
                      strokeWidth: Sz.stroke,
                      color: Dk.t2,
                    ),
                  )
                : GlyphIcon(glyph, size: glyphSize, color: fg),
          );
        },
      ),
    );
  }
}

enum DkButtonKind {
  /// Paper on ink: the one main action of a surface.
  primary,

  /// Apricot: only for "your move" (send).
  signal,

  /// Hairline outline.
  secondary,

  /// Text only, floor on hover.
  quiet,

  /// Destructive, in the outline style.
  danger,
}

/// A text button with an optional leading glyph and trailing hint.
class DkButton extends StatelessWidget {
  const DkButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = DkButtonKind.secondary,
    this.glyph,
    this.trailing,
    this.semanticLabel,
    this.dense = false,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final DkButtonKind kind;
  final Glyph? glyph;

  /// A trailing glyph (e.g. the send arrow).
  final Glyph? trailing;
  final String? semanticLabel;
  final bool dense;

  /// Fill the available width.
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final touch = Touch.primary;
    final height = touch ? Sz.hitTouch : (dense ? Sz.hit - 2 : Sz.hitBar + 2);
    return Pressable(
      semanticLabel: semanticLabel ?? label,
      onTap: busy ? null : onTap,
      builder: (context, s) {
        final on = s.enabled || busy;
        final (bg, bgLit, fg, edge) = switch (kind) {
          DkButtonKind.primary => (Dk.paper, Dk.mineCode, Dk.ink, null),
          DkButtonKind.signal => (Dk.signal, Dk.signalCode, Dk.signalInk, null),
          DkButtonKind.secondary => (Dk.p2, Dk.p3, Dk.t1, Dk.line2),
          DkButtonKind.quiet => (Colors.transparent, Dk.p2, Dk.t2, null),
          DkButtonKind.danger => (
              Dk.p2,
              Dk.dangerSoft,
              Dk.danger,
              Dk.dangerEdge
            ),
        };
        final floor = !on ? Dk.p2 : (s.lit ? bgLit : bg);
        final ink =
            !on ? Dk.t4 : (kind == DkButtonKind.quiet && s.lit ? Dk.t1 : fg);
        final row = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox.square(
                dimension: Sz.glyphXs,
                child: CircularProgressIndicator(
                  strokeWidth: Sz.stroke,
                  color: ink,
                ),
              )
            else if (glyph != null)
              GlyphIcon(glyph!, size: Sz.glyphSm, color: ink),
            if (busy || glyph != null) const SizedBox(width: Sp.x2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.name.copyWith(
                  color: ink,
                  fontWeight: kind == DkButtonKind.quiet
                      ? FontWeight.w600
                      : FontWeight.w700,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Sp.x15),
              GlyphIcon(trailing!, size: Sz.glyphXs, color: ink),
            ],
          ],
        );
        return AnimatedContainer(
          duration: Mo.of(context, Mo.instant),
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Sp.x25 : Sp.x35,
          ),
          decoration: BoxDecoration(
            color: floor,
            borderRadius: BorderRadius.circular(Rd.md),
            border: edge == null || !on
                ? (on ? null : Border.all(color: Dk.line))
                : Border.all(color: edge),
          ),
          child: row,
        );
      },
    );
  }
}

/// A key cap: "↵", "Shift ↵".
class Kbd extends StatelessWidget {
  const Kbd(this.keys, {super.key, this.label});
  final String keys;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cap = Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x15 - 1, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: Dk.line2),
        borderRadius: BorderRadius.circular(Rd.xs - 1),
      ),
      child: Text(keys, style: Ty.meta.copyWith(fontSize: 10.5)),
    );
    if (label == null) return cap;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cap,
        const SizedBox(width: Sp.x15),
        Text(label!, style: Ty.small.copyWith(fontSize: 11.5, color: Dk.t3)),
      ],
    );
  }
}

/// A small rounded label: "经由 Claude Code", a session tag, "群主".
class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.mono = false,
    this.color = Dk.t3,
    this.floor = Dk.p3,
    this.glyph,
  });
  final String text;
  final bool mono;
  final Color color;
  final Color floor;
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? Ty.meta.copyWith(color: color, fontSize: 10.5, height: 1.3)
        : Ty.small.copyWith(color: color, fontSize: 11, height: 1.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x15, vertical: 1),
      decoration: BoxDecoration(
        color: floor,
        borderRadius: BorderRadius.circular(Rd.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            GlyphIcon(glyph!, size: Sz.glyphXs - 2, color: color),
            const SizedBox(width: Sp.x1),
          ],
          Flexible(
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-line confirmation at the foot of the window.
void toast(BuildContext context, String text,
    {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      action: action == null
          ? null
          : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ),
  );
}
