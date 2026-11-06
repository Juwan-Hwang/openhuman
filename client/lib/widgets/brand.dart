/// The OpenHuman mark, drawn rather than loaded.
///
/// The symbol (assets/brand) is a prompt chevron — the agent's ">" that
/// doubles as a closed eye — beside a person in Apricot. It is painted
/// from the master geometry so it stays sharp at every size, and so the
/// chevron can wink: the ">" opens into a dot and snaps shut, the same
/// motion as assets/brand/motion/openhuman-symbol-wink.svg.
///
/// Below 32 logical pixels the brand ships a separate pixel-snapped
/// drawing; [BrandMark] switches to it on its own.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

/// The symbol: chevron + person.
class BrandMark extends StatefulWidget {
  BrandMark({
    super.key,
    this.size = 24,
    this.wink = BrandWink.none,
    Color? chevron,
    Color? human,
    this.tile = false,
  })  : chevron = chevron ?? Dk.paper,
        human = human ?? Dk.apricot;

  /// Edge of the square the mark is fitted into.
  final double size;

  /// Whether, and how often, the chevron winks.
  final BrandWink wink;

  final Color chevron;
  final Color human;

  /// Draw the Ink app-icon tile behind the mark.
  final bool tile;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

enum BrandWink {
  /// Still.
  none,

  /// One wink when the mark first appears.
  once,

  /// A wink every few seconds, for "working" and empty screens.
  idle,

  /// Back to back, for a busy wait such as connecting.
  busy,
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  // One cycle of the brand's motion file is 3.2 s with the wink at
  // 62–88 %. Here the wink alone is played, and the rest is a pause whose
  // length depends on the mode.
  static const _wink = Duration(milliseconds: 840);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _wink,
  );
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(BrandMark old) {
    super.didUpdateWidget(old);
    if (old.wink != widget.wink) _start();
  }

  Future<void> _start() async {
    final mode = widget.wink;
    if (mode == BrandWink.none) {
      _c.value = 0;
      return;
    }
    if (!Mo.loops) return;
    await Future<void>.delayed(const Duration(milliseconds: 420));
    while (_alive && mounted && widget.wink == mode) {
      await _c.forward(from: 0).orCancel.catchError((_) {});
      if (mode == BrandWink.once) return;
      await Future<void>.delayed(
        mode == BrandWink.busy
            ? const Duration(milliseconds: 380)
            : const Duration(milliseconds: 4200),
      );
    }
  }

  @override
  void dispose() {
    _alive = false;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'OpenHuman',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _MarkPainter(
              t: _c.value,
              chevron: widget.chevron,
              human: widget.human,
              tile: widget.tile,
              small: widget.size <= 32,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wink curve: keyframes of the brand motion file, re-timed to the wink
/// itself. Returns (squash 0..1, stroke scale).
(double, double) _winkAt(double t) {
  // Brand keyTimes 0.62 → 0.88 mapped onto 0 → 1:
  //   0.00 open   0.15 closing   0.31 shut   0.69 shut
  //   0.85 open   1.00 overshoot settles.
  double lerp(double a, double b, double x) => a + (b - a) * x;
  double ease(double x) => Curves.easeInOutCubic.transform(x.clamp(0, 1));
  if (t <= 0) return (0, 1);
  if (t < 0.15) return (lerp(0, 0.77, ease(t / 0.15)), lerp(1, 1.87, t / 0.15));
  if (t < 0.31) {
    final x = (t - 0.15) / 0.16;
    return (lerp(0.77, 1, ease(x)), lerp(1.87, 2.08, x));
  }
  if (t < 0.69) return (1, 2.08);
  if (t < 0.85) {
    final x = ease((t - 0.69) / 0.16);
    return (lerp(1, -0.06, x), lerp(2.08, 0.92, x));
  }
  final x = ease((t - 0.85) / 0.15);
  return (lerp(-0.06, 0, x), lerp(0.92, 1, x));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.t,
    required this.chevron,
    required this.human,
    required this.tile,
    required this.small,
  });

  final double t;
  final Color chevron;
  final Color human;
  final bool tile;
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    if (small && !tile) {
      _paintSmall(canvas, size);
      return;
    }
    // Master artboard is 256; the symbol sits in it under
    // translate(-26.28 -19.27) scale(1.11), as in the SVG.
    final k = size.width / 256;
    canvas.save();
    canvas.scale(k);
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 256, 256),
          const Radius.circular(56),
        ),
        Paint()..color = Dk.ink,
      );
    }
    canvas.translate(-26.28, -19.27);
    canvas.scale(1.11);
    _chevron(canvas, const Offset(60, 70), const Offset(90, 100),
        const Offset(60, 130), 24,
        center: const Offset(77, 100));
    final p = Paint()
      ..color = human
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(162, 100), 25, p);
    canvas.drawPath(
      _body(96, 148, 228, 187, 24, 203.5),
      p,
    );
    canvas.restore();
  }

  void _paintSmall(Canvas canvas, Size size) {
    final k = size.width / 32;
    canvas.save();
    canvas.scale(k);
    _chevron(canvas, const Offset(7, 9), const Offset(11, 13),
        const Offset(7, 17), 4,
        center: const Offset(9.4, 13));
    final p = Paint()..color = human;
    canvas.drawCircle(const Offset(20.5, 12.5), 3.5, p);
    canvas.drawPath(_body(13, 19, 28, 25, 3, 15), p);
    canvas.restore();
  }

  /// The ">" as a round-capped stroke. Winking pulls both arms into
  /// [center] and fattens the stroke into a dot.
  void _chevron(
    Canvas canvas,
    Offset a,
    Offset tip,
    Offset b,
    double width, {
    required Offset center,
  }) {
    final (squash, scale) = _winkAt(t);
    Offset pull(Offset o) => Offset.lerp(o, center, squash)!;
    final path = Path()
      ..moveTo(pull(a).dx, pull(a).dy)
      ..lineTo(pull(tip).dx, pull(tip).dy)
      ..lineTo(pull(b).dx, pull(b).dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = chevron
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Shoulders: a slab with rounded top corners whose bottom edge is a
  /// shallow arc, as in the master path.
  Path _body(
      double l, double top, double r, double bottom, double rad, double sag) {
    return Path()
      ..moveTo(l + rad, top)
      ..lineTo(r - rad, top)
      ..arcToPoint(Offset(r, top + rad), radius: Radius.circular(rad))
      ..lineTo(r, bottom)
      ..arcToPoint(Offset(l, bottom), radius: Radius.circular(sag))
      ..lineTo(l, top + rad)
      ..arcToPoint(Offset(l + rad, top), radius: Radius.circular(rad))
      ..close();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.t != t ||
      old.chevron != chevron ||
      old.human != human ||
      old.tile != tile ||
      old.small != small;
}

/// The custom-drawn lowercase wordmark: Paper on dark, Ink on light.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 18});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      Dk.light
          ? 'assets/brand/openhuman-wordmark-ink.png'
          : 'assets/brand/openhuman-wordmark-paper.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'OpenHuman',
      excludeFromSemantics: false,
    );
  }
}

/// Mark + wordmark on one line.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 22, this.wink = BrandWink.none});
  final double height;
  final BrandWink wink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: height * 1.35, wink: wink),
        SizedBox(width: height * 0.42),
        Padding(
          padding: EdgeInsets.only(top: height * 0.08),
          child: BrandWordmark(height: height * 0.78),
        ),
      ],
    );
  }
}

/// A soft Apricot bloom behind a hero mark: the only gradient the
/// console uses, and only on screens with nothing else to look at.
class BrandHalo extends StatelessWidget {
  const BrandHalo({super.key, required this.child, this.radius = 140});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HaloPainter(radius),
      child: child,
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          radius,
          [Dk.signalGlow, Dk.signalGlow.withValues(alpha: 0)],
          [0, 1],
        ),
    );
    // A single hairline orbit, a quarter turn of it brighter.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Dk.line;
    // The orbit never runs past the box it is painted in.
    final r = math.min(radius * 0.62, size.shortestSide / 2 - 6);
    canvas.drawCircle(c, r, ring);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi * 0.9,
      math.pi * 0.5,
      false,
      ring..color = Dk.line2,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.radius != radius;
}
