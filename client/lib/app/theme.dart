/// Material 3 theme for the OpenHuman client — the "Darkroom" language.
///
/// Values come from `tokens.dart`; this file only maps them onto
/// Material components so stock widgets (dialogs, menus, fields) look
/// native to the console. The console is dark only: it is a desktop
/// instrument that stays open all day, and its one loud colour, the
/// signal orange, only reads against the dark floor.
library;

import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'tokens.dart';

export 'tokens.dart';

/// The sans face for prose.
const String _sans = 'Manrope';

/// The mono face for ids, labels and anything a reader may copy.
const String _mono = 'GeistMono';

/// What to fall back to when a glyph is missing from the above — which
/// for Chinese is always. Kept as a constant so it can ride along in
/// `const` text styles.
const List<String> _fallback = ['NotoSansSC'];

/// Hover and press feedback in the surface's own colour.
///
/// Left to default, Material tints the overlay with `primary`, which on a
/// neutral palette is the one place an unexpected cast shows up. On the
/// desktop there is no ripple to lean on, so hover is the entire
/// acknowledgement that a control is live.
Color _overlay(ColorScheme scheme) => scheme.onSurface.withValues(alpha: 0.06);

/// Shared component styling that does not depend on the palette.
///
/// Kept apart from the two themes so the shapes stay identical when
/// switching between them.
ThemeData _base(Brightness brightness, ColorScheme scheme) {
  final isDark = brightness == Brightness.dark;
  final overlay = _overlay(scheme);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _sans, fontFamilyFallback: _fallback,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    // Keyboard focus is an emphasis, so it may borrow the signal.
    focusColor: Dk.signalSoft,
    hoverColor: Dk.p2,
    // One transition on every platform: a short fade with a small rise,
    // instead of Android's zoom on a phone and nothing on Windows.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Dk.p4,
        borderRadius: BorderRadius.circular(Rd.sm),
        border: Border.all(color: Dk.line2),
      ),
      textStyle: Ty.small.copyWith(color: Dk.t1, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),

    // Aevum sets 1.6 on the body and lets headings tighten from there.
    textTheme: TextTheme(
      displaySmall: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.7,
        height: 1.1,
      ),
      headlineSmall: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      titleMedium: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      titleSmall: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodyMedium: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodySmall: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: const TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
      labelSmall: const TextStyle(
        fontFamily: _mono,
        fontFamilyFallback: _fallback,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.3,
        height: 1.3,
      ),
    ),

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    ),

    // Flat surfaces; separation comes from borders, not elevation.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.md),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 10,
      titleTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? Dk.t1Soft : Dk.p2,
        foregroundColor: isDark ? Dk.bg : Dk.t1,
        overlayColor: overlay,
        elevation: 0,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: _sans,
          fontFamilyFallback: _fallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurface,
        overlayColor: overlay,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: _sans,
          fontFamilyFallback: _fallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        overlayColor: overlay,
        elevation: 0,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: _sans,
          fontFamilyFallback: _fallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        overlayColor: overlay,
        iconSize: 18,
        minimumSize: const Size(34, 34),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.sm),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? Dk.p2 : Dk.mineCode,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 14,
        color: scheme.onSurfaceVariant,
      ),
      // A border you can always see: a bare underline disappears into
      // the surface on a chat screen.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        borderSide: BorderSide(color: scheme.onSurface, width: 1.5),
      ),
    ),

    dialogTheme: DialogThemeData(
      elevation: 24,
      shadowColor: const Color(0xCC000000),
      backgroundColor: Dk.p1,
      surfaceTintColor: Colors.transparent,
      barrierColor: const Color(0xB3050506),
      insetPadding: const EdgeInsets.all(Sp.x8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.xl),
        side: const BorderSide(color: Dk.line2),
      ),
      titleTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 14,
        height: 1.6,
        color: scheme.onSurfaceVariant,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Dk.p3,
      actionTextColor: Dk.signal,
      contentTextStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 13,
        color: isDark ? Dk.t1 : Dk.t1,
      ),
      width: 420,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        side: const BorderSide(color: Dk.line2),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      shadowColor: const Color(0x66000000),
      color: Dk.p2,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        side: const BorderSide(color: Dk.line2),
      ),
      textStyle: TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _fallback,
        fontSize: 13,
        color: scheme.onSurface,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Dk.p1,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0xB3050506),
      // Sheets that want a handle draw their own.
      showDragHandle: false,
      constraints: BoxConstraints(maxWidth: 640),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl)),
        side: BorderSide(color: Dk.line2),
      ),
    ),

    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: scheme.outlineVariant,
    ),

    // Aevum's scrollbars: thin, rounded, coloured from the border ramp.
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(Rd.pill),
      thumbVisibility: WidgetStateProperty.all(false),
      trackVisibility: WidgetStateProperty.all(false),
      crossAxisMargin: 2,
    ),

    // Selection is inverted rather than tinted, as in Aevum.
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: (isDark ? Dk.t1 : Dk.bg).withValues(alpha: 0.18),
      cursorColor: Dk.signal,
      selectionHandleColor: Dk.signal,
    ),

    splashFactory: NoSplash.splashFactory,
    // Dense for a mouse; standard for a finger.
    visualDensity:
        Touch.primary ? VisualDensity.standard : VisualDensity.compact,
  );
}

/// The dark theme — the only one the console ships.
final ThemeData darkTheme = _base(
  Brightness.dark,
  const ColorScheme(
    brightness: Brightness.dark,
    surface: Dk.bg,
    onSurface: Dk.t1,
    surfaceContainerLowest: Dk.bg,
    surfaceContainerLow: Dk.p1,
    surfaceContainer: Dk.p1,
    surfaceContainerHigh: Dk.p2,
    surfaceContainerHighest: Dk.p3,
    onSurfaceVariant: Dk.t2,
    primary: Dk.t1,
    onPrimary: Dk.bg,
    primaryContainer: Dk.p3,
    onPrimaryContainer: Dk.t1,
    secondary: Dk.p3,
    onSecondary: Dk.t1,
    secondaryContainer: Dk.p3,
    onSecondaryContainer: Dk.t1,
    tertiary: Dk.signal,
    onTertiary: Dk.signalInk,
    tertiaryContainer: Dk.signalSoft,
    onTertiaryContainer: Dk.t1,
    error: Dk.danger,
    onError: Dk.bg,
    outline: Dk.line2,
    outlineVariant: Dk.line,
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
  ),
);

/// Kept for callers that still name it; the console is dark only.
final ThemeData lightTheme = darkTheme;
