/// Window classes, so one layout serves a phone, a tablet and a desktop.
///
/// The console reads its class from the window width (Material's
/// compact / medium / expanded breakpoints) and its input from the
/// platform: a touch device gets 44 pt targets and no hover-only
/// affordances, whatever its width.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum Fit {
  /// Phones, and a desktop window dragged very narrow: one pane at a time.
  compact,

  /// Tablets and half-screen windows: list + stream, side panes overlay.
  medium,

  /// Desktop: all three panes side by side.
  expanded;

  static const double mediumFrom = 640;
  static const double expandedFrom = 1100;

  static Fit forWidth(double w) => w < mediumFrom
      ? Fit.compact
      : w < expandedFrom
          ? Fit.medium
          : Fit.expanded;

  static Fit of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == Fit.compact;
  bool get isExpanded => this == Fit.expanded;
}

/// Whether the primary pointer is a finger. Overridable for tests.
class Touch {
  static bool? debugOverride;

  static bool get primary {
    final o = debugOverride;
    if (o != null) return o;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Smallest hit target edge for the current input.
  static double get target => primary ? 44 : 32;
}

/// Stream geometry per window class.
class StreamMetrics {
  const StreamMetrics._({
    required this.gutter,
    required this.right,
    required this.cardPad,
    required this.rail,
  });

  /// Left gutter holding the clock and rail. Zero on phones: the clock
  /// moves beside the speaker's name and the rail is dropped.
  final double gutter;

  /// Right margin of the stream.
  final double right;

  /// Inner padding of a request card.
  final EdgeInsets cardPad;

  /// Whether the timeline rail is drawn.
  final bool rail;

  static const _wide = StreamMetrics._(
    gutter: 104,
    right: 36,
    cardPad: EdgeInsets.fromLTRB(24, 20, 24, 20),
    rail: true,
  );
  static const _mid = StreamMetrics._(
    gutter: 76,
    right: 24,
    cardPad: EdgeInsets.fromLTRB(22, 18, 22, 18),
    rail: true,
  );
  static const _phone = StreamMetrics._(
    gutter: 16,
    right: 16,
    cardPad: EdgeInsets.fromLTRB(16, 14, 16, 14),
    rail: false,
  );

  /// Chosen by the stream's own width, not the window's, so a desktop
  /// window with both side panes open still gets a sensible column.
  static StreamMetrics forWidth(double w) => w < 560
      ? _phone
      : w < 820
          ? _mid
          : _wide;
}

/// Hands [StreamMetrics] down to the stream, the composer and the strips
/// between them, measured once from the column they share.
class StreamScope extends InheritedWidget {
  const StreamScope({super.key, required this.metrics, required super.child});
  final StreamMetrics metrics;

  static StreamMetrics of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<StreamScope>();
    return s?.metrics ??
        StreamMetrics.forWidth(MediaQuery.sizeOf(context).width);
  }

  @override
  bool updateShouldNotify(StreamScope old) => old.metrics != metrics;
}

/// Measures its own width and provides [StreamScope] for [child].
class StreamColumn extends StatelessWidget {
  const StreamColumn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => StreamScope(
        metrics: StreamMetrics.forWidth(c.maxWidth),
        child: child,
      ),
    );
  }
}
