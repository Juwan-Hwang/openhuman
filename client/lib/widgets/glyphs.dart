/// The console's own line icons.
///
/// Drawn, not loaded: each glyph is a few strokes on a 24-unit grid with
/// round caps and joins — the same pen as the brand mark's chevron — so
/// the chrome reads as one hand rather than a borrowed icon font. The
/// stroke stays 1.6 logical pixels at the default 18 px and scales with
/// the glyph, so a small glyph never turns spidery.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/tokens.dart';

enum Glyph {
  search,
  sidebar,
  details,
  back,
  close,
  more,
  send,
  arrowDown,
  check,
  delivered,
  clock,
  alert,
  retry,
  offline,
  invite,
  copy,
  eye,
  eyeOff,
  key,
  server,
  people,
  personAdd,
  person,
  trash,
  restore,
  terminal,
  edit,
  save,
  image,
  plus,
  chevronDown,
  chevronRight,
  done,
  link,
  mention,
  minimize,
  maximize,
  unmaximize,
  bell,
  speaker,
  mic,
  film,
  shield,
  quiz,
  attach,
  folder,
  appearance,
}

/// A glyph at [size] in [color]. Purely decorative unless [semantic] is
/// given; buttons carry their own label.
class GlyphIcon extends StatelessWidget {
  GlyphIcon(
    this.glyph, {
    super.key,
    this.size = Sz.glyph,
    Color? color,
    this.semantic,
  }) : color = color ?? Dk.t2;

  final Glyph glyph;
  final double size;
  final Color color;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, color),
    );
    if (semantic == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semantic, image: true, child: paint);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    // 1.6 px at 18 px, scaled with the glyph, expressed in grid units.
    final px = (Sz.stroke * size.width / Sz.glyph).clamp(1.2, 2.4);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = px / k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.scale(k);
    _draw(canvas, stroke, fill);
    canvas.restore();
  }

  void _draw(Canvas c, Paint s, Paint f) {
    void line(double x1, double y1, double x2, double y2) =>
        c.drawLine(Offset(x1, y1), Offset(x2, y2), s);
    void poly(List<double> p, {bool close = false}) {
      final path = Path()..moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
      if (close) path.close();
      c.drawPath(path, s);
    }

    void circle(double x, double y, double r) =>
        c.drawCircle(Offset(x, y), r, s);
    void dot(double x, double y, [double r = 1.25]) =>
        c.drawCircle(Offset(x, y), r, f);
    void rrect(double l, double t, double r, double b, double rad) =>
        c.drawRRect(
          RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)),
          s,
        );
    void arc(double x, double y, double r, double from, double sweep) =>
        c.drawArc(
          Rect.fromCircle(center: Offset(x, y), radius: r),
          from,
          sweep,
          false,
          s,
        );
    // A person: head and shoulders.
    void person(double x, double y, double scale) {
      circle(x, y - 3.2 * scale, 3.2 * scale);
      final p = Path()
        ..moveTo(x - 6 * scale, y + 7.5 * scale)
        ..cubicTo(
          x - 6 * scale,
          y + 3.6 * scale,
          x - 3.4 * scale,
          y + 1.8 * scale,
          x,
          y + 1.8 * scale,
        )
        ..cubicTo(
          x + 3.4 * scale,
          y + 1.8 * scale,
          x + 6 * scale,
          y + 3.6 * scale,
          x + 6 * scale,
          y + 7.5 * scale,
        );
      c.drawPath(p, s);
    }

    const pi = math.pi;
    switch (glyph) {
      case Glyph.search:
        circle(10.5, 10.5, 6);
        line(15, 15, 19.5, 19.5);
      case Glyph.sidebar:
        rrect(3.5, 4.5, 20.5, 19.5, 3);
        line(9.5, 4.5, 9.5, 19.5);
      case Glyph.details:
        rrect(3.5, 4.5, 20.5, 19.5, 3);
        line(14.5, 4.5, 14.5, 19.5);
        line(16.8, 8.5, 18.2, 8.5);
        line(16.8, 11.5, 18.2, 11.5);
      case Glyph.back:
        poly([11, 5.5, 4.5, 12, 11, 18.5]);
        line(5, 12, 19.5, 12);
      case Glyph.close:
        line(6.5, 6.5, 17.5, 17.5);
        line(17.5, 6.5, 6.5, 17.5);
      case Glyph.more:
        dot(6, 12, 1.5);
        dot(12, 12, 1.5);
        dot(18, 12, 1.5);
      case Glyph.send:
        poly([6, 10.5, 12, 4.5, 18, 10.5]);
        line(12, 5, 12, 19.5);
      case Glyph.arrowDown:
        poly([6, 13.5, 12, 19.5, 18, 13.5]);
        line(12, 4.5, 12, 19);
      case Glyph.check:
        poly([5, 12.5, 9.8, 17, 19, 7]);
      case Glyph.delivered:
        poly([2.5, 12.5, 6.8, 16.5, 15, 7.5]);
        poly([11.5, 16, 12, 16.5, 20.5, 7.5]);
      case Glyph.clock:
        circle(12, 12, 8);
        poly([12, 7.5, 12, 12, 15, 14]);
      case Glyph.alert:
        circle(12, 12, 8);
        line(12, 7.8, 12, 12.8);
        dot(12, 16, 1.2);
      case Glyph.retry:
        arc(12, 12, 7, -pi * 0.35, pi * 1.65);
        poly([15.8, 3.6, 17.8, 6.2, 14.9, 7.9]);
      case Glyph.offline:
        // A plug pulled from its socket.
        line(4, 20, 8, 16);
        rrect(7.2, 9.8, 14.2, 16.8, 2.2);
        line(10, 9.8, 10, 7);
        line(13.6, 13.4, 16.4, 13.4);
        line(14.2, 6, 18.2, 2);
        poly([12.8, 8.4, 15.8, 5.4, 18.6, 8.2, 15.6, 11.2]);
      case Glyph.invite:
        // A person, with a line reaching out from them.
        person(9.5, 10.5, 1);
        arc(16, 8.5, 3.2, -pi * 0.42, pi * 0.84);
        arc(16, 8.5, 6.2, -pi * 0.36, pi * 0.72);
      case Glyph.copy:
        rrect(8.5, 8.5, 19.5, 19.5, 2.5);
        poly([
          15.5,
          5.5,
          15.5,
          5.2,
          14.7,
          4.5,
          6,
          4.5,
          4.5,
          6,
          4.5,
          14.7,
          5.2,
          15.5,
          5.5,
          15.5
        ]);
      case Glyph.eye:
        final p = Path()
          ..moveTo(2.5, 12)
          ..quadraticBezierTo(12, 2.5, 21.5, 12)
          ..quadraticBezierTo(12, 21.5, 2.5, 12)
          ..close();
        c.drawPath(p, s);
        circle(12, 12, 2.8);
      case Glyph.eyeOff:
        final p = Path()
          ..moveTo(2.5, 12)
          ..quadraticBezierTo(12, 2.5, 21.5, 12)
          ..quadraticBezierTo(12, 21.5, 2.5, 12)
          ..close();
        c.drawPath(p, s);
        line(4.5, 4.5, 19.5, 19.5);
      case Glyph.key:
        circle(8, 15.5, 4);
        line(11, 12.5, 19.5, 4);
        line(16.5, 7, 19, 9.5);
        line(14.3, 9.2, 16.3, 11.2);
      case Glyph.server:
        rrect(4, 4.5, 20, 10.5, 2);
        rrect(4, 13.5, 20, 19.5, 2);
        dot(8, 7.5, 1.1);
        dot(8, 16.5, 1.1);
      case Glyph.people:
        person(9, 11, 0.95);
        arc(16.2, 7.8, 3, -pi * 0.55, pi * 1.1);
        final p = Path()
          ..moveTo(17.2, 13.2)
          ..cubicTo(19.8, 13.6, 21.4, 15.4, 21.4, 18.6);
        c.drawPath(p, s);
      case Glyph.personAdd:
        person(9.5, 10.5, 1);
        line(18.5, 8, 18.5, 14);
        line(15.5, 11, 21.5, 11);
      case Glyph.person:
        person(12, 10.5, 1.05);
      case Glyph.trash:
        line(4.5, 6.5, 19.5, 6.5);
        poly([9.5, 6.5, 9.5, 4.2, 14.5, 4.2, 14.5, 6.5]);
        poly([6.5, 6.5, 7.5, 19.5, 16.5, 19.5, 17.5, 6.5]);
        line(10.5, 10.5, 10.5, 15.5);
        line(13.5, 10.5, 13.5, 15.5);
      case Glyph.restore:
        arc(12.5, 12.5, 7, pi * 0.9, pi * 1.5);
        poly([3.6, 8.4, 5.4, 11.8, 8.8, 10.2]);
        poly([12.5, 9, 12.5, 12.5, 15, 14]);
      case Glyph.terminal:
        rrect(3, 4.5, 21, 19.5, 3);
        poly([7.5, 9.5, 10.5, 12, 7.5, 14.5]);
        line(12.5, 15, 16.5, 15);
      case Glyph.edit:
        poly([5, 19, 5.6, 15.4, 15.6, 5.4, 18.6, 8.4, 8.6, 18.4], close: true);
        line(13.4, 7.6, 16.4, 10.6);
      case Glyph.save:
        line(12, 4, 12, 14.5);
        poly([7.8, 10.5, 12, 14.7, 16.2, 10.5]);
        poly([4.5, 15, 4.5, 19.5, 19.5, 19.5, 19.5, 15]);
      case Glyph.image:
        rrect(3.5, 5, 20.5, 19, 3);
        circle(9, 10, 1.7);
        poly([4, 17.5, 9.5, 13, 13, 16, 15.5, 13.8, 20, 17.5]);
      case Glyph.plus:
        line(12, 5, 12, 19);
        line(5, 12, 19, 12);
      case Glyph.chevronDown:
        poly([6.5, 9.5, 12, 15, 17.5, 9.5]);
      case Glyph.chevronRight:
        poly([9.5, 6.5, 15, 12, 9.5, 17.5]);
      case Glyph.done:
        circle(12, 12, 8);
        poly([8.3, 12.3, 11, 15, 16, 9.6]);
      case Glyph.link:
        final a = Path()
          ..moveTo(10.5, 13.5)
          ..lineTo(13.5, 10.5);
        c.drawPath(a, s);
        rrect(2.8, 10.6, 12.2, 15.8, 2.6);
        rrect(11.8, 8.2, 21.2, 13.4, 2.6);
      case Glyph.mention:
        circle(12, 12, 3.4);
        final p = Path()
          ..moveTo(15.4, 9)
          ..lineTo(15.4, 13.6)
          ..cubicTo(15.4, 16, 19.6, 16.4, 19.6, 12)
          ..cubicTo(19.6, 7.6, 16.2, 4.4, 12, 4.4)
          ..cubicTo(7.6, 4.4, 4.4, 7.8, 4.4, 12)
          ..cubicTo(4.4, 16.4, 7.8, 19.6, 12, 19.6)
          ..lineTo(14.6, 19.2);
        c.drawPath(p, s);
      case Glyph.minimize:
        line(6.5, 12, 17.5, 12);
      case Glyph.maximize:
        rrect(6.5, 6.5, 17.5, 17.5, 1.5);
      case Glyph.unmaximize:
        rrect(5.5, 8.5, 15.5, 18.5, 1.5);
        poly([8.5, 5.5, 18.5, 5.5, 18.5, 15.5]);
      case Glyph.bell:
        final p = Path()
          ..moveTo(5.5, 16.5)
          ..lineTo(18.5, 16.5)
          ..cubicTo(17, 15, 17, 13.5, 17, 10.5)
          ..cubicTo(17, 7.4, 14.8, 5, 12, 5)
          ..cubicTo(9.2, 5, 7, 7.4, 7, 10.5)
          ..cubicTo(7, 13.5, 7, 15, 5.5, 16.5)
          ..close();
        c.drawPath(p, s);
        arc(12, 18.5, 2, 0, pi);
      case Glyph.speaker:
        poly([4.5, 9.5, 8, 9.5, 12.5, 5.5, 12.5, 18.5, 8, 14.5, 4.5, 14.5],
            close: true);
        arc(13.5, 12, 3.5, -pi * 0.3, pi * 0.6);
        arc(13.5, 12, 6.8, -pi * 0.3, pi * 0.6);
      case Glyph.mic:
        rrect(9, 3.5, 15, 14.5, 3);
        arc(12, 11, 6, 0, pi);
        line(12, 17, 12, 20.5);
      case Glyph.film:
        rrect(3.5, 5.5, 20.5, 18.5, 2.5);
        poly([10, 9.2, 15, 12, 10, 14.8], close: true);
      case Glyph.shield:
        final p = Path()
          ..moveTo(12, 3.5)
          ..lineTo(19, 6.2)
          ..lineTo(19, 11.5)
          ..cubicTo(19, 16, 15.8, 19, 12, 20.5)
          ..cubicTo(8.2, 19, 5, 16, 5, 11.5)
          ..lineTo(5, 6.2)
          ..close();
        c.drawPath(p, s);
        poly([9, 12, 11.2, 14.2, 15.2, 10]);
      case Glyph.quiz:
        rrect(4.5, 3.5, 19.5, 20.5, 3);
        poly([8, 8.5, 9.2, 9.7, 11.4, 7.5]);
        line(13.5, 8.6, 16.5, 8.6);
        poly([8, 14.5, 9.2, 15.7, 11.4, 13.5]);
        line(13.5, 14.6, 16.5, 14.6);
      case Glyph.attach:
        final p = Path()
          ..moveTo(17.5, 11)
          ..lineTo(11, 17.5)
          ..cubicTo(9, 19.5, 6, 19.5, 4.8, 18.2)
          ..cubicTo(3.5, 16.9, 3.5, 14, 5.5, 12)
          ..lineTo(12.6, 4.9)
          ..cubicTo(14, 3.5, 16, 3.5, 17.3, 4.8)
          ..cubicTo(18.6, 6.1, 18.6, 8.1, 17.2, 9.5)
          ..lineTo(10.4, 16.3)
          ..cubicTo(9.6, 17.1, 8.5, 17.1, 7.8, 16.4)
          ..cubicTo(7.1, 15.7, 7.1, 14.6, 7.9, 13.8)
          ..lineTo(13.8, 7.9);
        c.drawPath(p, s);
      case Glyph.appearance:
        circle(12, 12, 8.5);
        c.drawArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 8.5),
          -1.5708,
          3.14159,
          true,
          f,
        );
      case Glyph.folder:
        poly([
          3.5,
          7,
          3.5,
          18,
          4.5,
          19,
          19.5,
          19,
          20.5,
          18,
          20.5,
          9,
          19.5,
          8,
          11.5,
          8,
          9.5,
          5.5,
          4.5,
          5.5
        ], close: true);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
