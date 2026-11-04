/// Design tokens for the OpenHuman console — the "Darkroom" language.
///
/// The console is a desktop instrument that stays open all day, so it is
/// dark, warm-neutral and quiet. Exactly one colour is allowed to shout:
/// [Dk.signal], and only when the human is the one being waited on.
/// Everything else (running, API task, done) has its own calm hue so a
/// glance at the window says whose move it is.
///
/// Widgets never write a colour, size or duration literal — they read
/// one of these. Changing the product's look is a change to this file.
library;

import 'package:flutter/material.dart';

/// Colours.
class Dk {
  // Surfaces, from the window floor up.
  static const Color bg = Color(0xFF0A0A0B);
  static const Color p1 = Color(0xFF111113); // side panes
  static const Color p2 = Color(0xFF17171A); // cards, composer
  static const Color p3 = Color(0xFF1E1E22); // selected row, chips
  static const Color p4 = Color(0xFF26262B); // hover on p3, code

  // Hairlines.
  static const Color line = Color(0xFF26262B);
  static const Color line2 = Color(0xFF33333A);

  // Text, warm white down to a quiet grey.
  static const Color t1 = Color(0xFFF2F0EB);
  static const Color t2 = Color(0xFFA5A39E);
  static const Color t3 = Color(0xFF6B6A67);
  static const Color t4 = Color(0xFF4A4A50);
  static const Color prose = Color(0xFFE9E6DF); // long agent text

  /// "Your move." The one loud colour.
  static const Color signal = Color(0xFFFF5B1F);
  static const Color signalSoft = Color(0x1FFF5B1F); // 12 %
  static const Color signalRing = Color(0x2EFF5B1F); // 18 %
  static const Color signalInk = Color(0xFF140701); // text on signal
  static const Color signalCode = Color(0xFFFFC9A8);

  /// Agent running / success.
  static const Color ok = Color(0xFF9BE15D);
  static const Color okSoft = Color(0x1A9BE15D);

  /// API task, links, tools.
  static const Color blue = Color(0xFF7AA7FF);
  static const Color blueSoft = Color(0x1A7AA7FF);
  static const Color blueFloor = Color(0xFF10151F);
  static const Color blueLine = Color(0xFF263350);

  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerSoft = Color(0x1AFF6B6B);

  /// The human's own bubble: inverted paper.
  static const Color mine = t1;
  static const Color onMine = Color(0xFF121212);
  static const Color mineCode = Color(0xFFE3DFD6);
}

/// Spacing on a 4 px grid.
class Sp {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x9 = 36;

  /// Width of the timeline gutter (time stamps + rail).
  static const double gutter = 104;

  /// Widest the stream column grows on a large window.
  static const double column = 1180;

  /// Longest comfortable line of agent prose.
  static const double measure = 760;
}

/// Corner radii.
class Rd {
  static const double xs = 5;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 18;
  static const double pill = 999;
}

/// Motion.
class Mo {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 420);
  static const Cubic expo = Cubic(0.16, 1, 0.3, 1);
  static const Cubic soft = Cubic(0.22, 1, 0.36, 1);
}

/// Type.
class Ty {
  static const String sans = 'Manrope';
  static const String monoFace = 'GeistMono';
  static const List<String> cjk = ['NotoSansSC'];

  static const TextStyle prose = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 15,
    height: 1.75,
    color: Dk.prose,
  );
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 14,
    height: 1.6,
    color: Dk.t1,
  );
  static const TextStyle small = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 12.5,
    height: 1.5,
    color: Dk.t2,
  );
  static const TextStyle label = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: Dk.t3,
  );
  static const TextStyle title = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 20,
    height: 1.2,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w700,
    color: Dk.t1,
  );
  static const TextStyle name = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjk,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: Dk.t1,
  );
  static const TextStyle meta = TextStyle(
    fontFamily: monoFace,
    fontFamilyFallback: cjk,
    fontSize: 11,
    height: 1.4,
    color: Dk.t3,
  );
  static const TextStyle code = TextStyle(
    fontFamily: monoFace,
    fontFamilyFallback: cjk,
    fontSize: 12.5,
    height: 1.8,
    color: Color(0xFFBDBAB3),
  );
}
