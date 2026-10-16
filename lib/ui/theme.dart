import 'package:flutter/material.dart';

/// Design tokens from DESIGN.md ("Tapo Inspired — TV and Mobile"), TV
/// profile. Sizes are logical units on the 960 × 540 TV canvas.
class TopoColors {
  static const primary = Color(0xFF0288E3); // decorative accents only
  static const primaryAction = Color(0xFF0067AD); // filled actions, blue text
  static const primaryPressed = Color(0xFF005A99); // pressed + focus outline
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF595757);
  static const neutral = Color(0xFFF2F9FF); // app background
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSelected = Color(0xFFE1F5FF);
  static const surfacePressed = Color(0xFFE6F7FF);
  static const onSurface = Color(0xFF000000);
  static const muted = Color(0xFF595757);
  static const outline = Color(0xFFD0EAFB); // decorative only
  static const disabledSurface = Color(0xFFEDEEEE);
  static const disabledText = Color(0xFF595757);
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF147D52);
  static const media = Color(0xFF101820); // backdrop for controls on video
  static const onMedia = Color(0xFFFFFFFF);
}

class TopoText {
  static const display = TextStyle(fontSize: 36, fontWeight: FontWeight.w700, height: 1.2, color: TopoColors.onSurface);
  static const headline = TextStyle(fontSize: 28, fontWeight: FontWeight.w500, height: 1.25, color: TopoColors.onSurface);
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.3, color: TopoColors.onSurface);
  static const body = TextStyle(fontSize: 18, fontWeight: FontWeight.w400, height: 1.5, color: TopoColors.onSurface);
  static const label = TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.3, color: TopoColors.onSurface);
  static const caption = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.4, color: TopoColors.muted);
}

class TopoRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 999.0;
}

class TopoSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const x2 = 24.0;
  static const x3 = 32.0;
  static const x4 = 48.0;
  static const sectionGap = 32.0;
  static const cardGap = 20.0;
  static const cardPadding = 20.0;
  static const focusGap = 3.0;
  static const focusWidth = 3.0;
}

class TopoMotion {
  static const press = Duration(milliseconds: 120);
  static const focus = Duration(milliseconds: 160);
  static const navigation = Duration(milliseconds: 220);
  static const curve = Curves.easeOut;
}

/// Standard card shadow.
const cardShadow = [BoxShadow(color: Color(0x1410486E), blurRadius: 8, offset: Offset(0, 2))];

/// Featured panel: pale gradient with the reference's offset shadow.
const featuredGradient = LinearGradient(
  begin: Alignment.bottomLeft,
  end: Alignment.topRight,
  stops: [0.1, 1],
  colors: [Color(0xFFFAFDF8), Color(0xFFE6F7FF)],
);
const featuredShadow = [BoxShadow(color: TopoColors.outline, offset: Offset(3, 3))];

/// Overscan-safe padding for TV screens.
const tvSafePadding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TopoColors.primary,
    brightness: Brightness.light,
    primary: TopoColors.primaryAction,
    onPrimary: TopoColors.onPrimary,
    surface: TopoColors.surface,
    onSurface: TopoColors.onSurface,
    error: TopoColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TopoColors.neutral,
    // Aktiv Grotesk is not bundled; fall back to the Android system sans.
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displaySmall: TopoText.display,
      headlineSmall: TopoText.headline,
      titleLarge: TopoText.title,
      bodyLarge: TopoText.body,
      bodyMedium: TopoText.caption,
      labelLarge: TopoText.label,
    ),
    // Focus is shown by our own outline, never by splash or hover effects.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
    dialogTheme: const DialogThemeData(backgroundColor: TopoColors.surface),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: TopoColors.primaryAction),
  );
}
