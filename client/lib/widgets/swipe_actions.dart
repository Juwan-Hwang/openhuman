/// A row that slides left to show its actions, the way Mail and Messages
/// do: drag past the buttons and let go, and the row stays open; keep
/// dragging most of the way across, and the last (destructive) action
/// runs on release. Only one row is open at a time.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/tokens.dart';
import 'haptics.dart';

class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.foreground = Dk.t1,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
}

/// Which row is open, shared by every row in one list.
class SwipeGroup extends ValueNotifier<Object?> {
  SwipeGroup() : super(null);
  void closeAll() => value = null;
}

class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.id,
    required this.group,
    required this.actions,
    required this.child,
    this.enabled = true,
  });

  final Object id;
  final SwipeGroup group;

  /// Left to right as drawn. The last one is the full-swipe action.
  final List<SwipeAction> actions;
  final Widget child;
  final bool enabled;

  static const double actionWidth = 76;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this);

  /// Offset in pixels, 0 closed, positive = slid left.
  double get _dx => _c.value;
  bool _armed = false;
  double _width = 1;

  double get _open => SwipeRow.actionWidth * widget.actions.length;
  double get _fullAt => math.max(_open + 40, _width * 0.62);

  @override
  void initState() {
    super.initState();
    _c.value = 0;
    _c.addListener(() => setState(() {}));
    widget.group.addListener(_onGroup);
  }

  @override
  void didUpdateWidget(SwipeRow old) {
    super.didUpdateWidget(old);
    if (old.group != widget.group) {
      old.group.removeListener(_onGroup);
      widget.group.addListener(_onGroup);
    }
    if (!widget.enabled && _dx != 0) _settle(0);
  }

  @override
  void dispose() {
    widget.group.removeListener(_onGroup);
    _c.dispose();
    super.dispose();
  }

  void _onGroup() {
    if (widget.group.value != widget.id && _dx != 0) _settle(0);
  }

  void _settle(double to) {
    final d = Mo.of(context, const Duration(milliseconds: 240));
    if (d == Duration.zero) {
      _c.value = to;
    } else {
      // The controller is unbounded in pixels.
      _c.animateTo(to, duration: d, curve: Mo.expo);
    }
  }

  void _start(DragStartDetails d) {
    _c.stop();
    widget.group.value = widget.id;
  }

  void _update(DragUpdateDetails d) {
    var next = _dx - d.primaryDelta!;
    if (next < 0) next = 0;
    // Resist past the full-swipe point.
    if (next > _width) next = _width;
    _c.value = next;
    final armed = next >= _fullAt;
    if (armed != _armed) {
      _armed = armed;
      Haptic.tick();
    }
  }

  void _end(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0); // positive = flung left
    if (_armed) {
      _armed = false;
      _settle(0);
      widget.group.closeAll();
      widget.actions.last.onTap();
      return;
    }
    if (v > 400 || (_dx > _open / 2 && v > -400)) {
      _settle(_open);
    } else {
      _settle(0);
      if (widget.group.value == widget.id) widget.group.closeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        _width = math.max(1, box.maxWidth);
        final dx = _dx;
        final full = dx >= _fullAt;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          child: Stack(
            children: [
              if (dx > 0)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Rd.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < widget.actions.length; i++)
                          _button(
                            widget.actions[i],
                            // Each button takes its share of what's revealed;
                            // on a full swipe the last one takes it all.
                            width: full
                                ? (i == widget.actions.length - 1 ? dx : 0)
                                : dx / widget.actions.length,
                          ),
                      ],
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(-dx, 0),
                child: AbsorbPointer(
                  absorbing: dx > 0,
                  child: widget.child,
                ),
              ),
              // Tapping the slid row closes it.
              if (dx > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: math.max(0, _width - dx),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _settle(0);
                      widget.group.closeAll();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _button(SwipeAction a, {required double width}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      color: a.color,
      child: width < 24
          ? null
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _settle(0);
                  widget.group.closeAll();
                  a.onTap();
                },
                child: ClipRect(
                  child: OverflowBox(
                    minWidth: 0,
                    maxWidth: SwipeRow.actionWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(a.icon, size: 20, color: a.foreground),
                        const SizedBox(height: 4),
                        Text(
                          a.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: a.foreground,
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
