import 'package:flutter/material.dart';

/// BusBee's visual language: white pages, black ink, thin black outlines,
/// grey pills, bold grotesque headings and a few loud accent blocks
/// (inspired by the TinkerHub app).
abstract final class AppColors {
  static const ink = Color(0xFF0B0B0B);
  static const paper = Colors.white;

  /// Secondary text.
  static const muted = Color(0xFF6B6B6B);

  /// Hints, disabled text, "ahead" parts of the timeline.
  static const faint = Color(0xFFB5B5B5);

  /// Pill and round-button backgrounds.
  static const pill = Color(0xFFF1F1F1);

  /// Hairlines between list rows.
  static const divider = Color(0xFFEAEAEA);

  // Accent blocks.
  static const violet = Color(0xFF5B5BE6);
  static const mint = Color(0xFF5CE07A);
  static const sun = Color(0xFFFFD84D);
  static const blush = Color(0xFFF3A6F0);

  static const danger = Color(0xFFD93025);
  static const live = Color(0xFF1DB954);
}

abstract final class AppFonts {
  static const display = 'BricolageGrotesque';
  static const body = 'Manrope';
}

/// Shared text styles. Headings use the display font, everything else Manrope.
abstract final class AppText {
  static const hero = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const heading = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.ink,
  );

  static const secondary = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );

  /// Upper-case labels on pills and outlined buttons ("VIEW ALL").
  static const label = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: AppColors.ink,
  );

  static const button = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
}

abstract final class AppTheme {
  static const double outline = 1.2;

  static ThemeData light() {
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: AppColors.ink, width: outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppFonts.body,
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: const ColorScheme.light(
        primary: AppColors.ink,
        onPrimary: AppColors.paper,
        secondary: AppColors.violet,
        surface: AppColors.paper,
        onSurface: AppColors.ink,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.ink),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper,
        hintStyle: AppText.body.copyWith(color: AppColors.faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.ink, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: outline),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        errorStyle: const TextStyle(color: AppColors.danger),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.paper,
          disabledBackgroundColor: AppColors.ink.withValues(alpha: 0.6),
          disabledForegroundColor: AppColors.paper,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          textStyle: AppText.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: outline),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: AppText.label.copyWith(fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.pill,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: AppText.label,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.body.copyWith(color: AppColors.paper),
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    );
  }
}
