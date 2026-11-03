import 'package:flutter/material.dart';

/// BusBee's visual language: pitch-black pages, hairline borders, light
/// headings that fade from grey to white, silver buttons and soft
/// ember-orange glows. The values are sampled from the Dribbble shot
/// "Dark Gradient Hero Section #2" (Raafi G.).
abstract final class AppColors {
  static const background = Color(0xFF000000);

  /// Cards, inputs, the nav bar and badges.
  static const surface = Color(0xFF1A1A1A);

  /// Pills and round buttons on top of a surface.
  static const raised = Color(0xFF242424);

  /// Hairline borders and dividers (the badge outline).
  static const border = Color(0xFF363636);

  /// The slightly brighter outline of the floating nav bar.
  static const borderStrong = Color(0xFF474747);

  static const text = Color(0xFFFFFFFF);

  /// Top of the headline fade (it ends in [text]).
  static const headlineTop = Color(0xFFD4D4D4);

  /// Body copy under the headline.
  static const muted = Color(0xFFB7B7B7);

  /// Nav links and badge text.
  static const subtle = Color(0xFFA3A3A3);

  /// Hints, disabled text, "ahead" parts of the timeline.
  static const faint = Color(0xFF5E5E5E);

  /// The accent: the logo ring, "Read more" links, "next stop", the bus marker.
  static const ember = Color(0xFFFF872A);

  /// Glow colours, from the outer edge to the white-hot centre.
  static const emberDeep = Color(0xFFA84600);
  static const emberMid = Color(0xFFD4600E);
  static const peach = Color(0xFFF2BC94);
  static const glow = Color(0xFFFCECE2);

  /// Tan halo of the horizon arc (its rim is near white).
  static const horizon = Color(0xFFA87A58);

  /// Silver button gradient, top to bottom.
  static const silverTop = Color(0xFFF1F1F1);
  static const silverMid = Color(0xFFCACACA);
  static const silverBottom = Color(0xFFA5A3A3);

  /// Text on silver buttons and on the ember accent.
  static const onLight = Color(0xFF0A0A0A);

  static const danger = Color(0xFFFF5A4E);
  static const live = Color(0xFF4ADE80);
}

abstract final class AppFonts {
  static const body = 'Manrope';
}

/// Shared text styles. Headings are large and light with tight tracking.
abstract final class AppText {
  static const hero = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 40,
    fontWeight: FontWeight.w400,
    height: 1.1,
    letterSpacing: -1.6,
    color: AppColors.text,
  );

  static const title = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 26,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.8,
    color: AppColors.text,
  );

  static const heading = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.text,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.text,
  );

  static const secondary = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.muted,
  );

  /// Small labels on pills and badges.
  static const label = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: AppColors.text,
  );

  static const button = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
}

abstract final class AppTheme {
  static const double hairline = 1;
  static const double radius = 12;

  /// Metallic fill of the themed [ElevatedButton]s and other silver controls.
  static const silverGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.silverTop, AppColors.silverMid, AppColors.silverBottom],
  );

  static ThemeData dark() {
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      borderSide: BorderSide(color: AppColors.border, width: hairline),
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppFonts.body,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.text,
        onPrimary: AppColors.onLight,
        secondary: AppColors.ember,
        onSecondary: AppColors.onLight,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: const IconThemeData(color: AppColors.text),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.ember,
        selectionColor: AppColors.ember.withValues(alpha: 0.35),
        selectionHandleColor: AppColors.ember,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Black wells inside the grey panels.
        fillColor: AppColors.background,
        hintStyle: AppText.body.copyWith(color: AppColors.faint),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.muted, width: hairline),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: hairline),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: hairline),
        ),
        errorStyle: const TextStyle(color: AppColors.danger),
      ),
      // Silver, like "Get Started": the gradient is drawn by backgroundBuilder.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onLight,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: AppColors.onLight,
          shadowColor: Colors.transparent,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: buttonShape,
          textStyle: AppText.button,
        ).copyWith(
          backgroundBuilder: (context, states, child) => Opacity(
            opacity: states.contains(WidgetState.disabled) ? 0.6 : 1,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: silverGradient,
                borderRadius: BorderRadius.all(Radius.circular(radius)),
              ),
              child: child,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border, width: hairline),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: AppText.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          textStyle: AppText.button,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.raised,
        side: const BorderSide(color: AppColors.border, width: hairline),
        shape: const StadiumBorder(),
        labelStyle: AppText.label,
        iconTheme: const IconThemeData(color: AppColors.ember, size: 16),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.text),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.raised,
        contentTextStyle: AppText.body.copyWith(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          side: BorderSide(color: AppColors.border, width: hairline),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.raised,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppText.label,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: hairline, space: hairline),
    );
  }
}
