/// The phone's two screens, the list and a conversation, as one stack:
/// the conversation slides over the list, and a drag from the left edge
/// pulls it back the way a native navigation stack does, following the
/// finger and settling on release.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

class PhoneStack extends StatefulWidget {
  const PhoneStack({
    super.key,
    required this.deep,
    required this.list,
    required this.conversation,
    required this.onBack,
  });

  /// True when the conversation is the screen in front.
  final bool deep;
  final Widget list;
  final Widget conversation;

  /// Called once a swipe from the edge has carried the conversation away.
  final VoidCallback onBack;

  /// How wide the strip along the left edge that starts a swipe is.
  static const double edge = 24;

  @override
  State<PhoneStack> createState() => _PhoneStackState();
}

class _PhoneStackState extends State<PhoneStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    value: widget.deep ? 1 : 0,
  );
  bool _dragging = false;

  static const Duration _push = Duration(milliseconds: 360);
  static const Duration _settle = Duration(milliseconds: 260);

  @override
  void didUpdateWidget(PhoneStack old) {
    super.didUpdateWidget(old);
    if (old.deep != widget.deep && !_dragging) {
      _animateTo(widget.deep ? 1 : 0, _push);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _animateTo(double v, Duration d) {
    final dur = Mo.of(context, d);
    if (dur == Duration.zero) {
      _t.value = v;
    } else {
      _t.animateTo(v, duration: dur, curve: Mo.expo);
    }
  }

  double get _width => math.max(1, MediaQuery.sizeOf(context).width);

  void _start(DragStartDetails d) => setState(() => _dragging = true);

  void _update(DragUpdateDetails d) {
    _t.value = (_t.value - d.primaryDelta! / _width).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final away = v > 520 || (v > -200 && _t.value < 0.6);
    setState(() => _dragging = false);
    if (away) {
      _animateTo(0, _settle);
      widget.onBack();
    } else {
      _animateTo(1, _settle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        final w = _width;
        final listShown = t < 1;
        final convShown = t > 0 || widget.deep;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The list waits behind, a little to the left and dimmed.
            // Offstage once covered: it keeps its state (the scroll
            // position) without painting or being read out.
            Offstage(
              offstage: !listShown,
              child: IgnorePointer(
                ignoring: t > 0.01,
                child: Transform.translate(
                  offset: Offset(-0.28 * w * t, 0),
                  child: widget.list,
                ),
              ),
            ),
            if (t > 0)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.38 * t),
                ),
              ),
            if (convShown)
              Transform.translate(
                offset: Offset((1 - t) * w, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Dk.bg,
                    boxShadow: [
                      if (t < 1)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(-6, 0),
                        ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        ignoring: !widget.deep && !_dragging,
                        child: widget.conversation,
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: PhoneStack.edge,
                        child: GestureDetector(
                          key: const ValueKey('phone-edge-swipe'),
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: widget.deep ? _start : null,
                          onHorizontalDragUpdate: widget.deep ? _update : null,
                          onHorizontalDragEnd: widget.deep ? _end : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
