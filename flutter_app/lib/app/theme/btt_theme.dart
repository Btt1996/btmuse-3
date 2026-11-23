// ─── Btmus 3.0.5 theme tokens ─────────────────────────────────────────────
// Phase 2, Stream C — typography / spacing normalization.
// Redesign (2026-11-22): BT monogram brand — violet → magenta → pink-red
// gradient sampled from the new logo. The old cyan / gold / green brand
// accents are retired; green survives only as the functional `success`
// color (downloaded / synced / complete states), never as brand.
//
// THEMES (v3.0.5, item 12): the palette is no longer `const` —
// [BttColors.applyVariant] swaps these statics at runtime when the user
// picks Signature / Mono / Aurora in Settings, and every call site reads
// the current values on its next build. Do NOT re-add `const` to a
// `BttColors` reference: `const` widgets that used them had their `const`
// removed in the v3.0.5 pass (the analyzer enforces this). The token sets
// live in `btt_theme_variant.dart`; `signatureTokens` holds the values
// below, so the default look is unchanged.
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
import 'package:btmu/app/theme/btt_theme_variant.dart';

class BttColors {
  // Mutable theme statics (v3.0.5, item 12). Defaults are the Signature
  // tokens; [applyVariant] swaps them all at once. Call sites read these
  // on every build, so a theme change takes effect on the next rebuild
  // without touching any screen.
  static Color bgObsidian = signatureTokens.bgObsidian;
  static Color bgElevated = signatureTokens.bgElevated;
  static Color bgCard = signatureTokens.bgCard;
  static Color bgCardHighlight = signatureTokens.bgCardHighlight;
  static Color borderSubtle = signatureTokens.borderSubtle;
  static Color borderStrong = signatureTokens.borderStrong;

  // BT monogram brand — gradient sampled from the new logo pixels:
  // violet #6202E1 → magenta #C4009B → pink-red #F70E42.
  // accentPink is the primary accent; accentViolet the secondary;
  // accentMagenta the warm highlight. Use accentGradient wherever the
  // widget supports a gradient (progress bars, play buttons, primary
  // surfaces); otherwise use the single accent that fits the context.
  static Color accentViolet = signatureTokens.accentViolet;
  static Color accentMagenta = signatureTokens.accentMagenta;
  static Color accentPink = signatureTokens.accentPink;
  static LinearGradient accentGradient = signatureTokens.accentGradient;

  // Glass surface: white at ~6% over the dark background.
  static Color glassSurface = signatureTokens.glassSurface;

  // Functional state colors — not brand. `success` keeps the old green
  // value for downloaded / synced / complete states only.
  static Color success = signatureTokens.success;

  static Color textPrimary = signatureTokens.textPrimary;
  static Color textSecondary = signatureTokens.textSecondary;
  static Color textMuted = signatureTokens.textMuted;

  static Color danger = signatureTokens.danger;
  static Color warning = signatureTokens.warning;

  /// The variant currently applied. [tokens] is its token set.
  static BttThemeVariant currentVariant = BttThemeVariant.signature;

  static BttThemeTokens get tokens => tokensFor(currentVariant);

  /// Swaps the whole palette to [variant]. Idempotent and cheap; call
  /// it before the first build and on every theme change, then rebuild
  /// the app (the MaterialApp watches the theme provider).
  static void applyVariant(BttThemeVariant variant) {
    final t = tokensFor(variant);
    currentVariant = variant;
    bgObsidian = t.bgObsidian;
    bgElevated = t.bgElevated;
    bgCard = t.bgCard;
    bgCardHighlight = t.bgCardHighlight;
    borderSubtle = t.borderSubtle;
    borderStrong = t.borderStrong;
    accentViolet = t.accentViolet;
    accentMagenta = t.accentMagenta;
    accentPink = t.accentPink;
    accentGradient = t.accentGradient;
    glassSurface = t.glassSurface;
    success = t.success;
    textPrimary = t.textPrimary;
    textSecondary = t.textSecondary;
    textMuted = t.textMuted;
    danger = t.danger;
    warning = t.warning;
  }

  /// Card depth: black 40%, blur 24, offset (0, 8). Apply to featured /
  /// playing cards and elevated surfaces; keep flat cards border-only.
  /// Theme-independent, so it stays const.
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
  /// Builds the dark theme for [variant] (default Signature).
  ///
  /// Layout changes per variant (v3.0.5, item 12) — not just colors:
  /// card/input corner radius comes from the tokens, list-tile density
  /// follows the variant, and chips get the variant's radius + selected
  /// color. Screens that hard-code their own radii keep them; the theme
  /// slots below are what change format app-wide.
  ///
  /// [customFontFamily] is the family name of a user-imported font
  /// (item 9), already loaded via FontLoader before the app starts.
  /// When set, body + display text use it instead of Plus Jakarta Sans /
  /// Manrope; the small JetBrains Mono labels stay Mono by design.
  static ThemeData buildDarkTheme({
    BttThemeVariant variant = BttThemeVariant.signature,
    String? customFontFamily,
  }) {
    final base = ThemeData.dark().textTheme;
    return buildDarkThemeFromTextThemes(
      variant: variant,
      bodyTextTheme: customFontFamily != null
          ? base.apply(fontFamily: customFontFamily)
          : GoogleFonts.plusJakartaSansTextTheme(base),
      displayStyle: customFontFamily != null
          ? TextStyle(
              fontFamily: customFontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            )
          : GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
      monoTextTheme: GoogleFonts.jetBrainsMonoTextTheme(base),
      customFontFamily: customFontFamily,
    );
  }

  /// Pure ThemeData mapping, testable without GoogleFonts: the caller
  /// supplies the three text themes (production passes the Google fonts,
  /// tests pass plain `ThemeData.dark().textTheme`). The custom font, when
  /// given, is applied to body + display only — the mono labels are
  /// always the [monoTextTheme] labels, untouched.
  static ThemeData buildDarkThemeFromTextThemes({
    BttThemeVariant variant = BttThemeVariant.signature,
    required TextTheme bodyTextTheme,
    required TextStyle displayStyle,
    required TextTheme monoTextTheme,
    String? customFontFamily,
  }) {
    final tokens = tokensFor(variant);
    final baseText = bodyTextTheme;
    final monoLabel = monoTextTheme.labelSmall?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: tokens.bgObsidian,
      colorScheme: ColorScheme.dark(
        primary: tokens.accentPink,
        secondary: tokens.accentViolet,
        tertiary: tokens.accentMagenta,
        surface: tokens.bgElevated,
        error: tokens.danger,
        onPrimary: tokens.bgObsidian,
        onSecondary: tokens.bgObsidian,
        onSurface: tokens.textPrimary,
      ),
      textTheme: baseText.copyWith(
        displayLarge: displayStyle.copyWith(fontSize: 32, color: tokens.textPrimary),
        displayMedium: displayStyle.copyWith(fontSize: 26, color: tokens.textPrimary),
        headlineMedium: displayStyle.copyWith(fontSize: 22, color: tokens.textPrimary),
        titleLarge: displayStyle.copyWith(fontSize: 18, color: tokens.textPrimary), // Section-header size — documented exception to the type scale (see header comment); kept as-is, do not restyle.
        titleMedium: baseText.titleMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          color: tokens.textPrimary,
          fontSize: 15,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontSize: 13.5,
        ),
        labelSmall: monoLabel?.copyWith(color: tokens.textMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bgObsidian,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: displayStyle.copyWith(fontSize: 22, color: tokens.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: tokens.bgCard,
        elevation: 0,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.borderSubtle,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.bgElevated,
        hintStyle: TextStyle(color: tokens.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: BttSpacing.s16, vertical: BttSpacing.s16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius * 0.75),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius * 0.75),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius * 0.75),
          borderSide: BorderSide(color: tokens.accentViolet, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        // SliderThemeData has no gradient-track slot: the solid primary
        // accent is used here. Custom progress bars (fullscreen player,
        // mini-player) paint BttColors.accentGradient themselves.
        activeTrackColor: tokens.accentPink,
        inactiveTrackColor: tokens.borderStrong,
        thumbColor: Colors.white,
        overlayColor: tokens.accentPink.withValues(alpha: 0.18),
        trackHeight: BttSpacing.s4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.bgCardHighlight,
        contentTextStyle: TextStyle(color: tokens.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      // Variant layout slots: chips (the segment/filter rows on Library,
      // Import and X2) and list tiles follow the variant's radius and
      // density, so a theme changes the format of lists, not just color.
      chipTheme: ChipThemeData(
        backgroundColor: tokens.bgCard,
        selectedColor: tokens.accentPink.withValues(alpha: 0.2),
        disabledColor: tokens.bgCard,
        labelStyle: TextStyle(color: tokens.textSecondary, fontSize: 12.5),
        secondaryLabelStyle: TextStyle(color: tokens.accentPink, fontSize: 12.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius * 0.75),
          side: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: tokens.bgCard,
        dense: tokens.listDensity == VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
      ),
    );
  }
}
