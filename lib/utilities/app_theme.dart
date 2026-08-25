import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design system for the app.
///
/// Consolidates the colors / type / shapes that were previously scattered
/// as one-off literals across screens (e.g. Color(0xff1546A0),
/// Color(0xFF0070BA), Color(0xff243656), Color(0xffF5F7FA) ...) into a
/// single, consistent, Wise-style palette. Import this file and use
/// `AppColors` / `AppRadii` / `AppShadows` instead of hardcoded literals.
class AppColors {
  AppColors._();

  // Brand — single consistent deep ink-blue (was split between
  // 0xff1546A0 and 0xFF0070BA across screens).
  static const Color primary = Color(0xFF163172);
  static const Color primaryDark = Color(0xFF0E2154);
  static const Color primaryLight = Color(0xFF2C4A9E);
  static const Color accent = Color(0xFF9FE870); // Wise-style lime accent

  // Neutrals / ink
  static const Color ink = Color(0xFF1A2138); // primary text (was 0xff243656)
  static const Color inkMuted = Color(0xFF566073); // secondary text (was 0xff343a40)
  static const Color textMuted = Color(0xFF8A94A6); // tertiary text (was 0xff929BAB)
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF5F7FA); // soft background (was 0xffF5F7FA)
  static const Color surfaceSunken = Color(0xFFEEF1F6);
  static const Color border = Color(0xFFE6E9EF);
  static const Color divider = Color(0xFFEDEFF3);

  // Semantic
  static const Color success = Color(0xFF1FB17A); // credit (was 0xff37d39b, deepened for AA contrast)
  static const Color successBg = Color(0xFFE7F8EF);
  static const Color danger = Color(0xFFE6577C); // debit (was 0xfff47090)
  static const Color dangerBg = Color(0xFFFCEAEF);
  static const Color warning = Color(0xFFE3A008);
  static const Color warningBg = Color(0xFFFCF3DA);

  static const Color scaffold = Color(0xFFFAFBFD);
}

class AppRadii {
  AppRadii._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 100;
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.primaryDark.withOpacity(0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  static List<BoxShadow> raised = [
    BoxShadow(
      color: AppColors.primaryDark.withOpacity(0.10),
      blurRadius: 32,
      offset: const Offset(0, 12),
      spreadRadius: -10,
    ),
  ];

  static List<BoxShadow> none = const [];
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
}

/// Builds the single ThemeData used app-wide.
ThemeData buildAppTheme() {
  final baseTextTheme = GoogleFonts.manropeTextTheme();

  final textTheme = baseTextTheme.copyWith(
    displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w700),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w600),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: AppColors.ink),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
    bodySmall: baseTextTheme.bodySmall?.copyWith(color: AppColors.textMuted),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
        color: AppColors.ink, fontWeight: FontWeight.w600),
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffold,
    primaryColor: AppColors.primary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.primaryLight,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    fontFamily: textTheme.bodyMedium?.fontFamily,
    textTheme: textTheme,
    splashColor: AppColors.primary.withOpacity(0.06),
    highlightColor: Colors.transparent,
    dividerColor: AppColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.ink),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Manrope',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Manrope',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Manrope',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Manrope',
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
      labelStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: AppColors.ink),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      textStyle: const TextStyle(
          color: AppColors.ink, fontSize: 14, fontFamily: 'Manrope'),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
  );
}
