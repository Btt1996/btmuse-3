import 'package:flutter/material.dart';

/// Theme variants (v3.0.5, item 12).
///
/// A variant is a palette AND a layout: each one carries its own surface
/// colors, accent gradient, corner radius, and list density, so switching
/// themes changes the format of the design, not just its colors.
///
/// * [BttThemeVariant.signature] — the shipped look: deep near-black
///   surfaces with the BT violet → magenta → pink-red gradient, 18 px
///   cards, standard density.
/// * [BttThemeVariant.mono] — black & white: true-black surfaces, a
///   white/silver accent (no hue), squarer 10 px cards, compact density.
/// * [BttThemeVariant.aurora] — warm dark: deep plum-brown surfaces with
///   an amber → rose gradient, rounder 26 px cards, comfortable density.
///
/// The tokens are plain `const` data. [BttColors.applyVariant] copies
/// them into the mutable statics the 400+ existing call sites read, and
/// [BttTheme.buildDarkTheme] takes the same tokens for the ThemeData
/// slots (card shape, chips, list density, inputs) — so a variant changes
/// both the palette and the layout in one place.
enum BttThemeVariant {
  signature,
  mono,
  aurora;

  String get id => name;

  String get displayName => switch (this) {
        BttThemeVariant.signature => 'Signature',
        BttThemeVariant.mono => 'Mono',
        BttThemeVariant.aurora => 'Aurora',
      };

  String get description => switch (this) {
        BttThemeVariant.signature =>
          'Deep near-black with the BT violet → magenta → pink gradient. The shipped Btmus look.',
        BttThemeVariant.mono =>
          'Black & white. No hue, squarer cards, tighter lists — minimal and flat.',
        BttThemeVariant.aurora =>
          'Warm plum dark with an amber → rose gradient, rounder cards, roomier lists.',
      };

  static BttThemeVariant fromId(String? id) {
    for (final v in BttThemeVariant.values) {
      if (v.id == id) return v;
    }
    return BttThemeVariant.signature;
  }
}

class BttThemeTokens {
  final BttThemeVariant variant;

  final Color bgObsidian;
  final Color bgElevated;
  final Color bgCard;
  final Color bgCardHighlight;
  final Color borderSubtle;
  final Color borderStrong;

  final Color accentViolet;
  final Color accentMagenta;
  final Color accentPink;
  final LinearGradient accentGradient;

  final Color glassSurface;

  final Color success;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color danger;
  final Color warning;

  /// Corner radius for cards, inputs and sheets in this variant.
  final double cardRadius;

  /// List-tile density: Mono is compact, Signature standard,
  /// Aurora comfortable.
  final VisualDensity listDensity;

  const BttThemeTokens({
    required this.variant,
    required this.bgObsidian,
    required this.bgElevated,
    required this.bgCard,
    required this.bgCardHighlight,
    required this.borderSubtle,
    required this.borderStrong,
    required this.accentViolet,
    required this.accentMagenta,
    required this.accentPink,
    required this.accentGradient,
    required this.glassSurface,
    required this.success,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.warning,
    required this.cardRadius,
    required this.listDensity,
  });
}

/// Signature — the shipped Btmus look (tokens copied from BttColors).
const BttThemeTokens signatureTokens = BttThemeTokens(
  variant: BttThemeVariant.signature,
  bgObsidian: Color(0xFF05070B),
  bgElevated: Color(0xFF0C111B),
  bgCard: Color(0xFF121926),
  bgCardHighlight: Color(0xFF182233),
  borderSubtle: Color(0x1FFFFFFF),
  borderStrong: Color(0x33FFFFFF),
  accentViolet: Color(0xFF6202E1),
  accentMagenta: Color(0xFFC4009B),
  accentPink: Color(0xFFF70E42),
  accentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6202E1), Color(0xFFC4009B), Color(0xFFF70E42)],
  ),
  glassSurface: Color(0x0FFFFFFF),
  success: Color(0xFF34D399),
  textPrimary: Color(0xFFF8FAFC),
  textSecondary: Color(0xFF94A3B8),
  textMuted: Color(0xFF64748B),
  danger: Color(0xFFEF4444),
  warning: Color(0xFFF59E0B),
  cardRadius: 18,
  listDensity: VisualDensity.standard,
);

/// Mono — black & white. Accents are white/silver; the "gradient" is a
/// white → light-gray ramp, so gradient surfaces read as solid light.
const BttThemeTokens monoTokens = BttThemeTokens(
  variant: BttThemeVariant.mono,
  bgObsidian: Color(0xFF000000),
  bgElevated: Color(0xFF0A0A0A),
  bgCard: Color(0xFF141414),
  bgCardHighlight: Color(0xFF1E1E1E),
  borderSubtle: Color(0x1FFFFFFF),
  borderStrong: Color(0x33FFFFFF),
  accentViolet: Color(0xFFE5E5E5),
  accentMagenta: Color(0xFFD4D4D4),
  accentPink: Color(0xFFFFFFFF),
  accentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFE5E5E5), Color(0xFFD4D4D4)],
  ),
  glassSurface: Color(0x0FFFFFFF),
  success: Color(0xFF34D399),
  textPrimary: Color(0xFFF5F5F5),
  textSecondary: Color(0xFFA3A3A3),
  textMuted: Color(0xFF737373),
  danger: Color(0xFFEF4444),
  warning: Color(0xFFF59E0B),
  cardRadius: 10,
  listDensity: VisualDensity.compact,
);

/// Aurora — warm plum dark, amber → rose accent, rounder cards.
const BttThemeTokens auroraTokens = BttThemeTokens(
  variant: BttThemeVariant.aurora,
  bgObsidian: Color(0xFF14090B),
  bgElevated: Color(0xFF1E0F14),
  bgCard: Color(0xFF2A1620),
  bgCardHighlight: Color(0xFF35202A),
  borderSubtle: Color(0x1FFFFFFF),
  borderStrong: Color(0x33FFFFFF),
  accentViolet: Color(0xFFF59E0B),
  accentMagenta: Color(0xFFF43F5E),
  accentPink: Color(0xFFFB923C),
  accentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFF43F5E), Color(0xFFFB923C)],
  ),
  glassSurface: Color(0x0FFFFFFF),
  success: Color(0xFF34D399),
  textPrimary: Color(0xFFFFF7ED),
  textSecondary: Color(0xFFD6A99A),
  textMuted: Color(0xFF9C7A72),
  danger: Color(0xFFEF4444),
  warning: Color(0xFFFBBF24),
  cardRadius: 26,
  listDensity: VisualDensity.comfortable,
);

BttThemeTokens tokensFor(BttThemeVariant variant) => switch (variant) {
      BttThemeVariant.signature => signatureTokens,
      BttThemeVariant.mono => monoTokens,
      BttThemeVariant.aurora => auroraTokens,
    };
