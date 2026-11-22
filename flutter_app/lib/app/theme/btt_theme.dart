import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BttColors {
  static const Color bgObsidian = Color(0xFF05070B);
  static const Color bgElevated = Color(0xFF0C111B);
  static const Color bgCard = Color(0xFF121926);
  static const Color bgCardHighlight = Color(0xFF182233);
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);

  // Brand palette extracted directly from original geometric Btt Music logo
  static const Color cyanAccent = Color(0xFF24C7DB);
  static const Color goldAccent = Color(0xFFE5B842);
  static const Color greenAccent = Color(0xFF34D399);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
}

class BttTheme {
  static ThemeData buildDarkTheme() {
    final baseText = GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);
    final displayStyle = GoogleFonts.manrope(
      color: BttColors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BttColors.bgObsidian,
      colorScheme: const ColorScheme.dark(
        primary: BttColors.cyanAccent,
        secondary: BttColors.goldAccent,
        tertiary: BttColors.greenAccent,
        surface: BttColors.bgElevated,
        error: BttColors.danger,
        onPrimary: BttColors.bgObsidian,
        onSecondary: BttColors.bgObsidian,
        onSurface: BttColors.textPrimary,
      ),
      textTheme: baseText.copyWith(
        displayLarge: displayStyle.copyWith(fontSize: 32),
        displayMedium: displayStyle.copyWith(fontSize: 26),
        headlineMedium: displayStyle.copyWith(fontSize: 22),
        titleLarge: displayStyle.copyWith(fontSize: 18),
        titleMedium: baseText.titleMedium?.copyWith(
          color: BttColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          color: BttColors.textPrimary,
          fontSize: 15,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: BttColors.textSecondary,
          fontSize: 13.5,
        ),
        labelSmall: GoogleFonts.jetBrainsMono(
          color: BttColors.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: BttColors.bgObsidian,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: displayStyle.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: BttColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: BttColors.borderSubtle, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BttColors.borderSubtle,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BttColors.bgElevated,
        hintStyle: const TextStyle(color: BttColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BttColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BttColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BttColors.cyanAccent, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: BttColors.cyanAccent,
        inactiveTrackColor: BttColors.borderStrong,
        thumbColor: BttColors.textPrimary,
        overlayColor: BttColors.cyanAccent.withValues(alpha: 0.18),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BttColors.bgCardHighlight,
        contentTextStyle: const TextStyle(color: BttColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
