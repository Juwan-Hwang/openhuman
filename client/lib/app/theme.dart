/// Material 3 theme for the OpenHuman client.
///
/// The palette, radii, type and motion come from the Aevum design
/// language: a neutral zinc ramp, generous corner radii, Manrope for
/// prose and Geist Mono for identifiers. Nothing here is chromatic —
/// the restraint is the point, and it leaves the message list as the
/// only thing competing for attention.
library;

import 'package:flutter/material.dart';

/// Corner radii, in the Aevum scale (`--radius: 0.875rem`).
///
/// 14px is the base; the rest are multipliers of it, matching the
/// `--radius-*` tokens rather than Flutter's 4/8/12 defaults.
class AppRadius {
  static const double sm = 8;
  static const double md = 11;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;
}

/// Motion vocabulary, carried over from Aevum.
class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  /// Decisive, settles late — the Aevum `--ease-expo`.
  static const Cubic expo = Cubic(0.16, 1, 0.3, 1);

  /// Softer landing for small state changes.
  static const Cubic softOut = Cubic(0.22, 1, 0.36, 1);
}

/// The zinc ramp, converted from the Aevum oklch tokens.
///
/// These are the Tailwind zinc values the tokens resolve to; keeping
/// them named here means a colour is never written into a widget.
class Zinc {
  static const Color c50 = Color(0xFFFAFAFA);
  static const Color c100 = Color(0xFFF4F4F5);
  static const Color c200 = Color(0xFFE4E4E7);
  static const Color c400 = Color(0xFFA1A1AA);
  static const Color c500 = Color(0xFF71717B);
  static const Color c600 = Color(0xFF52525B);
  static const Color c700 = Color(0xFF3F3F46);
  static const Color c800 = Color(0xFF27272A);
  static const Color c900 = Color(0xFF18181B);
  static const Color c950 = Color(0xFF09090B);
}

/// The sans face for prose.
const String _sans = 'Manrope';

/// The mono face for ids, labels and anything a reader may copy.
const String _mono = 'GeistMono';

/// What to fall back to when a glyph is missing from the above — which
/// for Chinese is always. Kept as a constant so it can ride along in
/// `const` text styles.
const List<String> _fallback = ['PingFangSF'];

/// Hover and press feedback in the surface's own colour.
///
/// Left to default, Material tints the overlay with `primary`, which on a
/// neutral palette is the one place an unexpected cast shows up. On the
/// desktop there is no ripple to lean on, so hover is the entire
/// acknowledgement that a control is live.
Color _overlay(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.06);

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

    // Aevum sets 1.6 on the body and lets headings tighten from there.
    textTheme: TextTheme(
      displaySmall: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.7,
        height: 1.1,
      ),
      headlineSmall: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      titleMedium: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      titleSmall: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodyMedium: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodySmall: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: const TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
      labelSmall: const TextStyle(
        fontFamily: _mono, fontFamilyFallback: _fallback,
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
        fontFamily: _sans, fontFamilyFallback: _fallback,
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 10,
      titleTextStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? Zinc.c200 : Zinc.c900,
        foregroundColor: isDark ? Zinc.c950 : Zinc.c50,
        overlayColor: overlay,
        elevation: 0,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: _sans, fontFamilyFallback: _fallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
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
          fontFamily: _sans, fontFamilyFallback: _fallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
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
          fontFamily: _sans, fontFamilyFallback: _fallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
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
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? Zinc.c900 : Zinc.c100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 14,
        color: scheme.onSurfaceVariant,
      ),
      // A border you can always see: a bare underline disappears into
      // the surface on a chat screen.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.onSurface, width: 1.5),
      ),
    ),

    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      titleTextStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 14,
        height: 1.6,
        color: scheme.onSurfaceVariant,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: isDark ? Zinc.c800 : Zinc.c900,
      contentTextStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 13,
        color: isDark ? Zinc.c50 : Zinc.c50,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      textStyle: TextStyle(
        fontFamily: _sans, fontFamilyFallback: _fallback,
        fontSize: 13,
        color: scheme.onSurface,
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
      radius: const Radius.circular(AppRadius.pill),
      thumbVisibility: WidgetStateProperty.all(false),
      trackVisibility: WidgetStateProperty.all(false),
      crossAxisMargin: 2,
    ),

    // Selection is inverted rather than tinted, as in Aevum.
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: (isDark ? Zinc.c50 : Zinc.c950).withValues(alpha: 0.18),
      cursorColor: scheme.onSurface,
      selectionHandleColor: scheme.onSurface,
    ),

    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
  );
}

/// The light theme — the default.
final ThemeData lightTheme = _base(
  Brightness.light,
  const ColorScheme(
    brightness: Brightness.light,
    surface: Color(0xFFFFFFFF),
    onSurface: Zinc.c950,
    surfaceContainerHighest: Zinc.c100,
    surfaceContainerLow: Zinc.c50,
    surfaceContainerHigh: Zinc.c100,
    onSurfaceVariant: Zinc.c500,
    primary: Zinc.c900,
    onPrimary: Zinc.c50,
    primaryContainer: Zinc.c100,
    onPrimaryContainer: Zinc.c950,
    secondary: Zinc.c100,
    onSecondary: Zinc.c950,
    secondaryContainer: Zinc.c100,
    onSecondaryContainer: Zinc.c950,
    error: Color(0xFFE7000B),
    onError: Color(0xFFFFFFFF),
    outline: Zinc.c200,
    outlineVariant: Zinc.c200,
    shadow: Color(0x1A000000),
    scrim: Color(0x1A000000),
  ),
);

/// The dark theme.
final ThemeData darkTheme = _base(
  Brightness.dark,
  const ColorScheme(
    brightness: Brightness.dark,
    surface: Zinc.c950,
    onSurface: Zinc.c50,
    surfaceContainerHighest: Zinc.c800,
    surfaceContainerLow: Zinc.c900,
    surfaceContainerHigh: Zinc.c900,
    onSurfaceVariant: Zinc.c400,
    primary: Zinc.c200,
    onPrimary: Zinc.c950,
    primaryContainer: Zinc.c800,
    onPrimaryContainer: Zinc.c50,
    secondary: Zinc.c800,
    onSecondary: Zinc.c50,
    secondaryContainer: Zinc.c800,
    onSecondaryContainer: Zinc.c50,
    error: Color(0xFFFF6467),
    onError: Zinc.c950,
    outline: Zinc.c800,
    outlineVariant: Zinc.c800,
    shadow: Color(0x33000000),
    scrim: Color(0x33000000),
  ),
);
