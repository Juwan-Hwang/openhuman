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
  // Brand (assets/brand): Ink, Apricot, Paper. Apricot is "the human" in
  // the mark, so in the console it is exactly the human's colour: it lights
  // up when the human is the one being waited on, and nowhere else.
  static const Color ink = Color(0xFF16171C);
  static const Color apricot = Color(0xFFFF8A5C);
  static const Color paper = Color(0xFFF7F2EA);

  // Surfaces, from the window floor up. Built on Ink, a cool near-black.
  static const Color bg = Color(0xFF0F1014);
  static const Color p1 = Color(0xFF131418); // side panes
  static const Color p2 = ink; // cards, composer
  static const Color p3 = Color(0xFF1E1F25); // selected row, chips
  static const Color p4 = Color(0xFF272830); // hover on p3, code

  // Hairlines.
  static const Color line = Color(0xFF23242B);
  static const Color line2 = Color(0xFF30313A);

  // Text, warm paper down to a quiet grey.
  static const Color t1 = paper;
  static const Color t2 = Color(0xFFA9A59E);
  static const Color t3 = Color(0xFF706E6A);
  static const Color t4 = Color(0xFF4B4B53);
  static const Color prose = Color(0xFFECE7DE); // long agent text

  /// Scrim behind modal sheets and overlay panes.
  static const Color scrim = Color(0xB3060709);

  /// Long soft shadow under floating things (menus, composer).
  static const Color shadow = Color(0x99000000);

  /// "Your move." The one loud colour: the brand's Apricot.
  static const Color signal = apricot;
  static const Color signalSoft = Color(0x1FFF8A5C); // 12 %
  static const Color signalRing = Color(0x2EFF8A5C); // 18 %
  static const Color signalEdge = Color(0x59FF8A5C); // 35 %, card border
  static const Color signalGlow = Color(0x17FF8A5C); // 9 %, card halo
  static const Color signalInk = Color(0xFF1F0D05); // text on signal
  static const Color signalCode = Color(0xFFFFD2BF);

  /// Agent running / success.
  static const Color ok = Color(0xFF9BE15D);
  static const Color okSoft = Color(0x1A9BE15D);
  static const Color okEdge = Color(0x479BE15D);

  /// Connecting, retrying.
  static const Color warn = Color(0xFFE0B252);
  static const Color warnSoft = Color(0x1AE0B252);

  /// API task, links, tools.
  static const Color blue = Color(0xFF7AA7FF);
  static const Color blueSoft = Color(0x1A7AA7FF);
  static const Color blueFloor = Color(0xFF10151F);
  static const Color blueLine = Color(0xFF263350);

  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerSoft = Color(0x1AFF6B6B);
  static const Color dangerEdge = Color(0x47FF6B6B);

  /// The human's own bubble: the brand's Paper.
  static const Color mine = paper;
  static const Color onMine = ink;
  static const Color mineCode = Color(0xFFE8E1D5);
  static const Color mineMuted = Color(0xFF6E6A62);

  /// Text a step under t1, for unread-looking rows.
  static const Color t1Soft = Color(0xFFDCD7CE);

  /// The window floor at 90 %: the fade the composer floats on.
  static const Color bgFade = Color(0xE60F1014);

  /// Near-black behind a full-screen image.
  static const Color scrimDeep = Color(0xEB050506);

  /// Code blocks: body and header strip.
  static const Color codeFloor = Color(0xFF0C0D10);
  static const Color codeHead = Color(0xFF121317);
  static const Color codeInk = Color(0xFFBDBAB3);
  static const Color diffAdd = Color(0xFFB6EC86);
  static const Color diffDel = Color(0xFFFF8F8F);
  static const Color dangerInk = Color(0xFFFFB3B3);

  /// Windows' own close-button red, so the caption reads as native.
  static const Color closeRed = Color(0xFFC42B1C);

  /// Identity hues for agents. None sits near Apricot: that hue belongs
  /// to the human alone.
  static const List<Color> hues = [
    Color(0xFF6E8BE0), // slate blue
    Color(0xFF8BBF5E), // moss
    Color(0xFFC9A44A), // brass
    Color(0xFFB07AD6), // lilac
    Color(0xFF4FB3A9), // teal
    Color(0xFFC77C9A), // rose
  ];
  static const Color onHue = Color(0xFF111216);
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

  /// Ambient motion: loops that run on their own (the mark's wink, the
  /// breathing state dot). Off under test, so frames can settle; the
  /// platform's "reduce motion" switch turns them off too.
  static bool ambient = true;

  static bool get loops =>
      ambient &&
      !WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
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
    color: Dk.codeInk,
  );
}
