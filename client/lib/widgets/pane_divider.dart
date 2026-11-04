/// A draggable divider between two panes, like a native split view.
///
/// A 1 px hairline with a 7 px hit area; it lights up on hover and while
/// dragging. Double-click restores the pane's default width.
library;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

class PaneDivider extends StatefulWidget {
  const PaneDivider({
    super.key,
    required this.onDrag,
    this.onReset,
    this.invert = false,
  });

  /// Horizontal drag delta in logical pixels.
  final void Function(double dx) onDrag;
  final VoidCallback? onReset;

  /// The pane being sized is on the divider's right: dragging left
  /// grows it, so the delta is negated.
  final bool invert;

  @override
  State<PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<PaneDivider> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hover || _drag;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _drag = true),
        onHorizontalDragEnd: (_) => setState(() => _drag = false),
        onHorizontalDragCancel: () => setState(() => _drag = false),
        onHorizontalDragUpdate: (d) =>
            widget.onDrag(widget.invert ? -d.delta.dx : d.delta.dx),
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: Mo.fast,
              width: lit ? 2 : 1,
              color: _drag
                  ? Dk.signal
                  : lit
                      ? Dk.t4
                      : Dk.line,
            ),
          ),
        ),
      ),
    );
  }
}
