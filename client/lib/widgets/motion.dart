/// The console's motion system: four moves, used everywhere.
///
/// | Move        | Widget      | Used for                                   |
/// |-------------|-------------|--------------------------------------------|
/// | enter       | [Enter]     | a new message, a pane's content arriving   |
/// | expand      | [Reveal]    | folded text, technical details, sections   |
/// | state swap  | [Swap]      | "your move" pill, send state, icons        |
/// | slide       | [SlideSwap] | phone list ⇄ conversation                   |
///
/// All four read their timing from [Mo] and fall back to a cut when the
/// platform asks for reduced motion. Interruption is free: they are
/// implicit animations, so a change mid-flight retargets from wherever
/// the value is instead of jumping to the start.
library;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

/// Fades and rises into place once, when first built.
class Enter extends StatelessWidget {
  const Enter({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = Mo.slow,
    this.rise = Mo.rise,
  });

  final Widget child;

  /// Off for rows that are merely scrolled back into view.
  final bool enabled;
  final Duration duration;
  final double rise;

  @override
  Widget build(BuildContext context) {
    if (!enabled || Mo.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Mo.expo,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * rise),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Opens and closes [child] vertically, fading as it goes.
class Reveal extends StatelessWidget {
  const Reveal({
    super.key,
    required this.open,
    required this.child,
    this.alignment = Alignment.topLeft,
  });

  final bool open;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final d = Mo.of(context, Mo.base);
    return AnimatedSize(
      duration: d,
      curve: Mo.expo,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: Mo.expo,
        switchOutCurve: Mo.exit,
        child: open
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox(key: ValueKey(false), width: double.infinity),
      ),
    );
  }
}

/// Cross-fades between states with a small scale, keyed by [value].
class Swap<T> extends StatelessWidget {
  const Swap({
    super.key,
    required this.value,
    required this.child,
    this.alignment = Alignment.center,
  });

  final T value;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Mo.of(context, Mo.base),
      switchInCurve: Mo.expo,
      switchOutCurve: Mo.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(a),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey<T>(value), child: child),
    );
  }
}

/// Slides between two screens on a phone: forward goes left, back goes
/// right, the way a navigation stack does.
class SlideSwap extends StatelessWidget {
  const SlideSwap({
    super.key,
    required this.forward,
    required this.child,
  });

  /// True when [child] is the deeper screen (the conversation).
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Mo.of(context, Mo.base),
      switchInCurve: Mo.expo,
      switchOutCurve: Mo.exit,
      transitionBuilder: (child, a) {
        final deeper = child.key == const ValueKey('deep');
        return SlideTransition(
          position: Tween(
            begin: Offset(deeper ? 0.22 : -0.22, 0),
            end: Offset.zero,
          ).animate(a),
          child: FadeTransition(opacity: a, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(forward ? 'deep' : 'top'),
        child: child,
      ),
    );
  }
}

/// A dot that breathes while [on] — the "your move" signal. Holds still
/// when ambient motion is off or reduced.
class BreathingDot extends StatefulWidget {
  const BreathingDot({
    super.key,
    required this.color,
    this.on = true,
    this.size = Sz.dot,
  });

  final Color color;
  final bool on;
  final double size;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Mo.breath);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BreathingDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.on && Mo.loops && !Mo.reduced(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.on)
                Container(
                  width: s + s * 1.4 * v,
                  height: s + s * 1.4 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.34 * (1 - v)),
                  ),
                ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
