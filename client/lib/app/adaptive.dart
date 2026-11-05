/// Window classes, so one layout serves a phone, a tablet and a desktop.
///
/// The console reads its class from the window width (Material's
/// compact / medium / expanded breakpoints) and its input from the
/// platform: a touch device gets 44 pt targets and no hover-only
/// affordances, whatever its width.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

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
///
/// The stream is a peer conversation: the other person's messages sit
/// on the left behind a lane that holds their avatar, mine sit on the
/// right. [lane] is that avatar column; [side] is the margin on both
/// edges, which the composer and the strips between them share.
class StreamMetrics {
  const StreamMetrics._({
    required this.side,
    required this.avatar,
    required this.phone,
  });

  /// Margin on both edges of the stream.
  final double side;

  /// Avatar beside the first message of a run.
  final double avatar;

  /// A phone-width column: tighter lanes, clocks always shown (there is
  /// no hover to reveal them).
  final bool phone;

  /// The avatar lane: the avatar and the gap after it.
  double get lane => avatar + (phone ? Sp.x2 : Sp.x3);

  static const _wide = StreamMetrics._(
    side: Sp.x8,
    avatar: Sz.avatar,
    phone: false,
  );
  static const _mid = StreamMetrics._(
    side: Sp.x6,
    avatar: Sz.avatar,
    phone: false,
  );
  static const _phone = StreamMetrics._(
    side: Sp.x3,
    avatar: Sz.avatarSm,
    phone: true,
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
