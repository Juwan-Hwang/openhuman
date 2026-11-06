/// Design tokens for the OpenHuman console — the "Darkroom" language.
///
/// OpenHuman is two people in one conversation; the client is where one
/// of them reads and answers. It stays open all day beside other work,
/// so it is dark, warm-neutral and quiet. Exactly one colour is allowed
/// to shout: [Dk.signal], the brand's Apricot, and only for "your move"
/// (someone is waiting on you) and keyboard focus. Everything else keeps
/// a calm hue, so a glance at the window says whose move it is.
///
/// Widgets never write a colour, size or duration literal — they read
/// one of these. Changing the product's look is a change to this file.
library;

import 'package:flutter/material.dart';

/// Colours.
///
/// Two palettes on one set of names: [Dk.use] picks the one the app
/// draws with. Widgets read a colour at build time, so the app rebuilds
/// its whole tree when the choice changes.
class Dk {
  // Brand (assets/brand): Ink, Apricot, Paper.
  static const Color brandInk = Color(0xFF16171C);
  static const Color brandPaper = Color(0xFFF7F2EA);
  static const Color apricot = Color(0xFFFF8A5C);

  /// Windows' own close-button red, so the caption reads as native.
  static const Color closeRed = Color(0xFFC42B1C);

  static DkPalette _p = DkPalette.dark;

  /// The palette in use.
  static DkPalette get palette => _p;

  static Brightness get brightness => _p.brightness;
  static bool get light => _p.brightness == Brightness.light;

  /// Draw with the light or the dark palette from now on.
  static void use(Brightness b) =>
      _p = b == Brightness.light ? DkPalette.light : DkPalette.dark;

  static Color get ink => _p.ink;
  static Color get paper => _p.paper;
  static Color get bg => _p.bg;
  static Color get p1 => _p.p1;
  static Color get p2 => _p.p2;
  static Color get p3 => _p.p3;
  static Color get p4 => _p.p4;
  static Color get line => _p.line;
  static Color get line2 => _p.line2;
  static Color get t1 => _p.t1;
  static Color get t2 => _p.t2;
  static Color get t3 => _p.t3;
  static Color get t4 => _p.t4;
  static Color get prose => _p.prose;
  static Color get scrim => _p.scrim;
  static Color get shadow => _p.shadow;
  static Color get signal => _p.signal;
  static Color get signalSoft => _p.signalSoft;
  static Color get signalRing => _p.signalRing;
  static Color get signalEdge => _p.signalEdge;
  static Color get signalGlow => _p.signalGlow;
  static Color get signalInk => _p.signalInk;
  static Color get signalCode => _p.signalCode;
  static Color get ok => _p.ok;
  static Color get okSoft => _p.okSoft;
  static Color get okEdge => _p.okEdge;
  static Color get warn => _p.warn;
  static Color get warnSoft => _p.warnSoft;
  static Color get blue => _p.blue;
  static Color get blueSoft => _p.blueSoft;
  static Color get blueFloor => _p.blueFloor;
  static Color get blueLine => _p.blueLine;
  static Color get danger => _p.danger;
  static Color get dangerSoft => _p.dangerSoft;
  static Color get dangerEdge => _p.dangerEdge;
  static Color get mine => _p.mine;
  static Color get onMine => _p.onMine;
  static Color get mineCode => _p.mineCode;
  static Color get mineMuted => _p.mineMuted;
  static Color get t1Soft => _p.t1Soft;
  static Color get bgFade => _p.bgFade;
  static Color get scrimDeep => _p.scrimDeep;
  static Color get codeFloor => _p.codeFloor;
  static Color get codeHead => _p.codeHead;
  static Color get codeInk => _p.codeInk;
  static Color get diffAdd => _p.diffAdd;
  static Color get diffDel => _p.diffDel;
  static Color get dangerInk => _p.dangerInk;
  static Color get onHue => _p.onHue;
  static Color get focus => _p.focus;
  static Color get mineFloor => _p.mineFloor;
  static Color get mineEdge => _p.mineEdge;
  static Color get hover => _p.hover;
  static Color get imageFloor => _p.imageFloor;
  static List<Color> get hues => _p.hues;
}

/// One full set of colours. Comments on [DkPalette.dark] say what each is for.
class DkPalette {
  const DkPalette({
    required this.brightness,
    required this.ink,
    required this.paper,
    required this.bg,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    required this.line,
    required this.line2,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.t4,
    required this.prose,
    required this.scrim,
    required this.shadow,
    required this.signal,
    required this.signalSoft,
    required this.signalRing,
    required this.signalEdge,
    required this.signalGlow,
    required this.signalInk,
    required this.signalCode,
    required this.ok,
    required this.okSoft,
    required this.okEdge,
    required this.warn,
    required this.warnSoft,
    required this.blue,
    required this.blueSoft,
    required this.blueFloor,
    required this.blueLine,
    required this.danger,
    required this.dangerSoft,
    required this.dangerEdge,
    required this.mine,
    required this.onMine,
    required this.mineCode,
    required this.mineMuted,
    required this.t1Soft,
    required this.bgFade,
    required this.scrimDeep,
    required this.codeFloor,
    required this.codeHead,
    required this.codeInk,
    required this.diffAdd,
    required this.diffDel,
    required this.dangerInk,
    required this.onHue,
    required this.focus,
    required this.mineFloor,
    required this.mineEdge,
    required this.hover,
    required this.imageFloor,
    required this.hues,
  });

  final Brightness brightness;
  final Color ink;
  final Color paper;
  final Color bg;
  final Color p1;
  final Color p2;
  final Color p3;
  final Color p4;
  final Color line;
  final Color line2;
  final Color t1;
  final Color t2;
  final Color t3;
  final Color t4;
  final Color prose;
  final Color scrim;
  final Color shadow;
  final Color signal;
  final Color signalSoft;
  final Color signalRing;
  final Color signalEdge;
  final Color signalGlow;
  final Color signalInk;
  final Color signalCode;
  final Color ok;
  final Color okSoft;
  final Color okEdge;
  final Color warn;
  final Color warnSoft;
  final Color blue;
  final Color blueSoft;
  final Color blueFloor;
  final Color blueLine;
  final Color danger;
  final Color dangerSoft;
  final Color dangerEdge;
  final Color mine;
  final Color onMine;
  final Color mineCode;
  final Color mineMuted;
  final Color t1Soft;
  final Color bgFade;
  final Color scrimDeep;
  final Color codeFloor;
  final Color codeHead;
  final Color codeInk;
  final Color diffAdd;
  final Color diffDel;
  final Color dangerInk;
  final Color onHue;
  final Color focus;
  final Color mineFloor;
  final Color mineEdge;
  final Color hover;
  final Color imageFloor;
  final List<Color> hues;

  /// Darkroom: warm paper on Ink. Apricot means "your move".
  static const dark = DkPalette(
    brightness: Brightness.dark,
    ink: Color(0xFF16171C),
    paper: Color(0xFFF7F2EA),
    bg: Color(0xFF0F1014),
    p1: Color(0xFF131418),
    p2: Color(0xFF16171C),
    p3: Color(0xFF1E1F25),
    p4: Color(0xFF272830),
    line: Color(0xFF23242B),
    line2: Color(0xFF30313A),
    t1: Color(0xFFF7F2EA),
    t2: Color(0xFFA9A59E),
    t3: Color(0xFF706E6A),
    t4: Color(0xFF4B4B53),
    prose: Color(0xFFECE7DE),
    scrim: Color(0xB3060709),
    shadow: Color(0x99000000),
    signal: Color(0xFFFF8A5C),
    signalSoft: Color(0x1FFF8A5C),
    signalRing: Color(0x2EFF8A5C),
    signalEdge: Color(0x59FF8A5C),
    signalGlow: Color(0x17FF8A5C),
    signalInk: Color(0xFF1F0D05),
    signalCode: Color(0xFFFFD2BF),
    ok: Color(0xFF9BE15D),
    okSoft: Color(0x1A9BE15D),
    okEdge: Color(0x479BE15D),
    warn: Color(0xFFE0B252),
    warnSoft: Color(0x1AE0B252),
    blue: Color(0xFF7AA7FF),
    blueSoft: Color(0x1A7AA7FF),
    blueFloor: Color(0xFF10151F),
    blueLine: Color(0xFF263350),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0x1AFF6B6B),
    dangerEdge: Color(0x47FF6B6B),
    mine: Color(0xFFF7F2EA),
    onMine: Color(0xFF16171C),
    mineCode: Color(0xFFE8E1D5),
    mineMuted: Color(0xFF6E6A62),
    t1Soft: Color(0xFFDCD7CE),
    bgFade: Color(0xE60F1014),
    scrimDeep: Color(0xEB050506),
    codeFloor: Color(0xFF0C0D10),
    codeHead: Color(0xFF121317),
    codeInk: Color(0xFFBDBAB3),
    diffAdd: Color(0xFFB6EC86),
    diffDel: Color(0xFFFF8F8F),
    dangerInk: Color(0xFFFFB3B3),
    onHue: Color(0xFF111216),
    focus: Color(0x59FF8A5C),
    mineFloor: Color(0xFF211F21),
    mineEdge: Color(0xFF353135),
    hover: Color(0x0AF7F2EA),
    imageFloor: Color(0xFF17181D),
    hues: [
      Color(0xFF6E8BE0), // slate blue
      Color(0xFF8BBF5E), // moss
      Color(0xFFC9A44A), // brass
      Color(0xFFB07AD6), // lilac
      Color(0xFF4FB3A9), // teal
      Color(0xFFC77C9A), // rose
      Color(0xFF7FA6C9), // steel
      Color(0xFFA3B86C), // olive
    ],
  );

  /// Daylight: Ink on warm paper. The same roles, inverted; Apricot is
  /// a step deeper so it still reads on a light floor.
  static const light = DkPalette(
    brightness: Brightness.light,
    ink: Color(0xFFF7F2EA),
    paper: Color(0xFF16171C),
    bg: Color(0xFFF6F4F0),
    p1: Color(0xFFEFECE6),
    p2: Color(0xFFFFFFFF),
    p3: Color(0xFFE8E4DD),
    p4: Color(0xFFDDD8D0),
    line: Color(0xFFE4E0D8),
    line2: Color(0xFFD3CEC4),
    t1: Color(0xFF16171C),
    t2: Color(0xFF5C5A55),
    t3: Color(0xFF85827C),
    t4: Color(0xFFB0ADA6),
    prose: Color(0xFF222328),
    scrim: Color(0x3816171C),
    shadow: Color(0x2416171C),
    signal: Color(0xFFF2763F),
    signalSoft: Color(0x1FF2763F),
    signalRing: Color(0x33F2763F),
    signalEdge: Color(0x73F2763F),
    signalGlow: Color(0x14F2763F),
    signalInk: Color(0xFF1F0D05),
    signalCode: Color(0xFF8A3A14),
    ok: Color(0xFF3F8F1C),
    okSoft: Color(0x1A3F8F1C),
    okEdge: Color(0x473F8F1C),
    warn: Color(0xFFA87410),
    warnSoft: Color(0x1AA87410),
    blue: Color(0xFF2F62D6),
    blueSoft: Color(0x142F62D6),
    blueFloor: Color(0xFFEEF3FD),
    blueLine: Color(0xFFC8D6F4),
    danger: Color(0xFFD13A3A),
    dangerSoft: Color(0x14D13A3A),
    dangerEdge: Color(0x47D13A3A),
    mine: Color(0xFF16171C),
    onMine: Color(0xFFF7F2EA),
    mineCode: Color(0xFF2B2C33),
    mineMuted: Color(0xFF9B978F),
    t1Soft: Color(0xFF34353B),
    bgFade: Color(0xE6F6F4F0),
    scrimDeep: Color(0xEB050506),
    codeFloor: Color(0xFFF2EFE9),
    codeHead: Color(0xFFE9E5DE),
    codeInk: Color(0xFF3A3834),
    diffAdd: Color(0xFF2C7A10),
    diffDel: Color(0xFFC02E2E),
    dangerInk: Color(0xFFA12424),
    onHue: Color(0xFF111216),
    focus: Color(0x73F2763F),
    mineFloor: Color(0xFFEFEBE4),
    mineEdge: Color(0xFFDFD9CF),
    hover: Color(0x0A16171C),
    imageFloor: Color(0xFFEAE7E1),
    hues: [
      Color(0xFF6E8BE0), // slate blue
      Color(0xFF8BBF5E), // moss
      Color(0xFFC9A44A), // brass
      Color(0xFFB07AD6), // lilac
      Color(0xFF4FB3A9), // teal
      Color(0xFFC77C9A), // rose
      Color(0xFF7FA6C9), // steel
      Color(0xFFA3B86C), // olive
    ],
  );
}

/// Fixed sizes: chrome, panes, avatars, glyphs.
class Sz {
  /// Desktop title bar (own chrome).
  static const double titleBar = 34;
  static const double caption = 46;

  /// Pane headers: the list's search bar, the conversation header and
  /// the details header share one height, so their hairlines meet.
  static const double bar = 64;
  static const double barCompact = 56;

  /// Glyphs.
  static const double glyph = 18;
  static const double glyphSm = 15;
  static const double glyphXs = 13;
  static const double glyphLg = 22;
  static const double stroke = 1.6;

  /// Avatars.
  static const double avatarXs = 20;
  static const double avatarSm = 28;
  static const double avatar = 34;
  static const double avatarMd = 40;
  static const double avatarLg = 64;

  /// Hit targets. Touch is fixed at 44 by the platform guidelines.
  static const double hit = 32;
  static const double hitBar = 34;
  static const double hitTouch = 44;

  /// Panes (resizable).
  static const double listMin = 248;
  static const double listDefault = 296;
  static const double listMax = 420;
  static const double detailsMin = 300;
  static const double detailsDefault = 340;
  static const double detailsMax = 520;

  /// Width the desktop opens with the list showing.
  static const double listOpensFrom = 840;

  /// Longest comfortable line of message prose.
  static const double measure = 720;

  /// Widest a single image tile grows.
  static const double imageMax = 360;
  static const double imageGridMax = 480;

  /// Status dots.
  static const double dot = 7;
  static const double dotSm = 6;

  /// Focus ring width.
  static const double ring = 2;
}

/// Spacing on a 4 px grid.
class Sp {
  static const double x05 = 2;
  static const double x1 = 4;
  static const double x15 = 6;
  static const double x2 = 8;
  static const double x25 = 10;
  static const double x3 = 12;
  static const double x35 = 14;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x7 = 28;
  static const double x8 = 32;
  static const double x9 = 36;
  static const double x10 = 40;
  static const double x12 = 48;

  /// Width of the timeline gutter (time stamps + rail).
  static const double gutter = 104;

  /// Widest the stream column grows on a large window.
  static const double column = 1180;

  /// Longest comfortable line of message prose.
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

  /// Leaving: quick and plain, so what replaces it is not kept waiting.
  static const Curve exit = Curves.easeIn;

  /// How far a thing rises as it enters.
  static const double rise = 8;

  /// Hover and focus need to feel instant.
  static const Duration instant = Duration(milliseconds: 90);

  /// How long "copied" and similar confirmations stay up.
  static const Duration confirm = Duration(milliseconds: 1600);

  /// The breathing "your move" dot.
  static const Duration breath = Duration(milliseconds: 2400);

  /// Whether this context asked for less motion (the platform's
  /// "reduce motion" switch). Transitions then cut instead of moving.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or nothing when motion is reduced.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

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

  static TextStyle get prose => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 15,
        height: 1.75,
        color: Dk.prose,
      );
  static TextStyle get body => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 14,
        height: 1.6,
        color: Dk.t1,
      );
  static TextStyle get small => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 12.5,
        height: 1.5,
        color: Dk.t2,
      );
  static TextStyle get label => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 11,
        height: 1.3,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
        color: Dk.t3,
      );
  static TextStyle get title => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 20,
        height: 1.2,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w700,
        color: Dk.t1,
      );
  static TextStyle get name => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: cjk,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: Dk.t1,
      );
  static TextStyle get meta => TextStyle(
        fontFamily: monoFace,
        fontFamilyFallback: cjk,
        fontSize: 11,
        height: 1.4,
        color: Dk.t3,
      );
  static TextStyle get code => TextStyle(
        fontFamily: monoFace,
        fontFamilyFallback: cjk,
        fontSize: 12.5,
        height: 1.8,
        color: Dk.codeInk,
      );
}
