// ─── Btmus 2.00 theme tokens ────────────────────────────────────────────────
// Phase 2, Stream C — typography / spacing normalization.
// Redesign (2026-11-22): BT monogram brand — violet → magenta → pink-red
// gradient sampled from the new logo. The old cyan / gold / green brand
// accents are retired; green survives only as the functional `success`
// color (downloaded / synced / complete states), never as brand.
//
// FONTS (unchanged — do not change families, colors, layout, or content):
//   Body    — Plus Jakarta Sans (GoogleFonts.plusJakartaSansTextTheme)
//   Display — Manrope, w700, letterSpacing -0.4 (display + app-bar titles)
//   Labels  — JetBrains Mono, w500 (labelSmall)
//   GoogleFonts appears ONLY in this file.
//
// TYPE SCALE — every fontSize in the app must be one of these values.
//   Caption  11 / 11.5 ......... labelSmall (JetBrains Mono; theme default 11.5)
//   Body     12 / 12.5 / 13.5 ... bodyMedium (theme default 13.5)
//   Title    14.5 / 15 / 16 ..... titleMedium (theme default 16) / bodyLarge (15)
//   Display  22 / 26 / 32 ...... headlineMedium 22, displayMedium 26,
//                                 displayLarge 32 (Manrope)
//   The theme slots below already sit on this scale, with ONE documented
//   exception: titleLarge 18 — the section-header size used by ~14 call
//   sites (Home, Import Center, Settings, ...). It is kept at 18:
//   shrinking it to 16 would restyle those screens, which is out of scope
//   for this normalization-only pass. Coordinator to decide whether 18
//   joins the scale or those headers move to 16 in a later pass.
//   Deliberately NOT on this scale (kept as-is, do not "fix"):
//   lyrics_view.dart 9 / 11 / 16 / 17 / 21 — intentional synced-lyrics
//   hierarchy; settings_screen.dart 11 pt captions.
//   Known off-scale overrides left in files outside this stream's scope
//   (flagged in REPORT.md, not changed here): 13 pt in backup_screen.dart,
//   full_screen_player.dart, storage_dashboard.dart; 14 pt in
//   storage_dashboard.dart.
//
// SPACING SCALE — the only spacing values used in the app:
//   4 / 8 / 12 / 16 / 24 / 32  (see BttSpacing below).
//   Theme-level values in this file use BttSpacing constants. Corner radii
//   (card 18, input 14, snackbar 12) are NOT spacing and are unchanged.
//   Spacing inside full_screen_player.dart / mini_player.dart is owned by
//   another stream and is not touched here.
// ──────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BttColors {
  static const Color bgObsidian = Color(0xFF05070B);
  static const Color bgElevated = Color(0xFF0C111B);
  static const Color bgCard = Color(0xFF121926);
  static const Color bgCardHighlight = Color(0xFF182233);
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);

  // BT monogram brand — gradient sampled from the new logo pixels:
  // violet #6202E1 → magenta #C4009B → pink-red #F70E42.
  // accentPink is the primary accent; accentViolet the secondary;
  // accentMagenta the warm highlight. Use accentGradient wherever the
  // widget supports a gradient (progress bars, play buttons, primary
  // surfaces); otherwise use the single accent that fits the context.
  static const Color accentViolet = Color(0xFF6202E1);
  static const Color accentMagenta = Color(0xFFC4009B);
  static const Color accentPink = Color(0xFFF70E42);
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentViolet, accentMagenta, accentPink],
  );

  // Glass surface: white at ~6% over the dark background.
  static const Color glassSurface = Color(0x0FFFFFFF);

  // Functional state colors — not brand. `success` keeps the old green
  // value for downloaded / synced / complete states only.
  static const Color success = Color(0xFF34D399);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  /// Card depth: black 40%, blur 24, offset (0, 8). Apply to featured /
  /// playing cards and elevated surfaces; keep flat cards border-only.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

/// Spacing scale for Btmus 2.00 (Phase 2, Stream C).
///
/// The only spacing values in the app: 4 / 8 / 12 / 16 / 24 / 32.
/// Theme-level spacing in this file uses these constants; screen-level
/// spacing is normalized to the same scale by the owning streams.
class BttSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
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
        primary: BttColors.accentPink,
        secondary: BttColors.accentViolet,
        tertiary: BttColors.accentMagenta,
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
        titleLarge: displayStyle.copyWith(fontSize: 18), // Section-header size — documented exception to the type scale (see header comment); kept as-is, do not restyle.
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
        shadowColor: Colors.black,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: BttSpacing.s16, vertical: BttSpacing.s16),
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
          borderSide: const BorderSide(color: BttColors.accentViolet, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        // SliderThemeData has no gradient-track slot: the solid primary
        // accent is used here. Custom progress bars (fullscreen player,
        // mini-player) paint BttColors.accentGradient themselves.
        activeTrackColor: BttColors.accentPink,
        inactiveTrackColor: BttColors.borderStrong,
        thumbColor: Colors.white,
        overlayColor: BttColors.accentPink.withValues(alpha: 0.18),
        trackHeight: BttSpacing.s4,
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
