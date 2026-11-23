import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/theme/btt_theme_variant.dart';

void main() {

  group('BttThemeVariant ids', () {
    test('every variant round-trips through fromId', () {
      for (final v in BttThemeVariant.values) {
        expect(BttThemeVariant.fromId(v.id), v);
      }
    });

    test('unknown / empty ids fall back to Signature, never crash', () {
      expect(BttThemeVariant.fromId('nope'), BttThemeVariant.signature);
      expect(BttThemeVariant.fromId(''), BttThemeVariant.signature);
      expect(BttThemeVariant.fromId(null), BttThemeVariant.signature);
    });

    test('ids are distinct and stable', () {
      expect(
        BttThemeVariant.values.map((v) => v.id).toSet().length,
        BttThemeVariant.values.length,
      );
      expect(BttThemeVariant.signature.id, 'signature');
      expect(BttThemeVariant.mono.id, 'mono');
      expect(BttThemeVariant.aurora.id, 'aurora');
    });
  });

  group('theme tokens differ per variant', () {
    test('Signature, Mono and Aurora have different surfaces and accents', () {
      final sig = tokensFor(BttThemeVariant.signature);
      final mono = tokensFor(BttThemeVariant.mono);
      final aurora = tokensFor(BttThemeVariant.aurora);
      expect(mono.bgObsidian, isNot(sig.bgObsidian));
      expect(aurora.bgObsidian, isNot(sig.bgObsidian));
      expect(mono.accentPink, isNot(sig.accentPink));
      expect(aurora.accentPink, isNot(sig.accentPink));
    });

    test('layout tokens differ: Mono is compact + tight radius, Aurora roomy', () {
      final sig = tokensFor(BttThemeVariant.signature);
      final mono = tokensFor(BttThemeVariant.mono);
      final aurora = tokensFor(BttThemeVariant.aurora);
      expect(mono.cardRadius, lessThan(sig.cardRadius));
      expect(aurora.cardRadius, greaterThan(sig.cardRadius));
      expect(mono.listDensity, VisualDensity.compact);
      expect(aurora.listDensity, VisualDensity.comfortable);
      expect(sig.listDensity, VisualDensity.standard);
    });

    test('every variant keeps a real gradient (3 accent colors)', () {
      for (final v in BttThemeVariant.values) {
        final t = tokensFor(v);
        expect(t.accentGradient.colors.length, 3);
        expect(t.accentGradient.colors.toSet().length, 3);
      }
    });
  });

  group('BttColors.applyVariant', () {
    tearDown(() => BttColors.applyVariant(BttThemeVariant.signature));

    test('applyVariant switches every static field to the variant tokens', () {
      BttColors.applyVariant(BttThemeVariant.mono);
      final mono = tokensFor(BttThemeVariant.mono);
      expect(BttColors.bgObsidian, mono.bgObsidian);
      expect(BttColors.bgCard, mono.bgCard);
      expect(BttColors.accentViolet, mono.accentViolet);
      expect(BttColors.accentPink, mono.accentPink);
      expect(BttColors.textPrimary, mono.textPrimary);
      expect(BttColors.borderSubtle, mono.borderSubtle);
      expect(BttColors.currentVariant, BttThemeVariant.mono);
      expect(BttColors.tokens, mono);
    });

    test('applying Signature restores the original palette', () {
      BttColors.applyVariant(BttThemeVariant.aurora);
      BttColors.applyVariant(BttThemeVariant.signature);
      final sig = tokensFor(BttThemeVariant.signature);
      expect(BttColors.bgObsidian, sig.bgObsidian);
      expect(BttColors.accentPink, sig.accentPink);
    });
  });

  group('BttTheme.buildDarkTheme(variant:)', () {
    // Tests use the pure mapping (plain text themes) so they never touch
    // GoogleFonts, which cannot load fonts in unit tests (no network,
    // no bundled font assets).
    ThemeData themeFor({BttThemeVariant variant = BttThemeVariant.signature, String? customFontFamily}) {
      final base = ThemeData.dark().textTheme;
      final body = customFontFamily != null ? base.apply(fontFamily: customFontFamily) : base;
      final display = customFontFamily != null
          ? const TextStyle(fontFamily: 'BttCustom', fontWeight: FontWeight.w700, letterSpacing: -0.4)
          : const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, letterSpacing: -0.4);
      return BttTheme.buildDarkThemeFromTextThemes(
        variant: variant,
        bodyTextTheme: body,
        displayStyle: display,
        monoTextTheme: base.copyWith(labelSmall: base.labelSmall?.copyWith(fontFamily: 'JetBrains Mono')),
        customFontFamily: customFontFamily,
      );
    }

    test('scaffold background + card radius follow the variant', () {
      // Card radius lives in cardTheme.shape (RoundedRectangleBorder).
      double cardRadiusOf(ThemeData t) {
        final shape = t.cardTheme.shape;
        expect(shape, isA<RoundedRectangleBorder>());
        final radius = (shape as RoundedRectangleBorder)
            .borderRadius
            .resolve(TextDirection.ltr);
        return radius.topLeft.x;
      }

      final sig = themeFor(variant: BttThemeVariant.signature);
      final mono = themeFor(variant: BttThemeVariant.mono);
      final aurora = themeFor(variant: BttThemeVariant.aurora);
      expect(sig.scaffoldBackgroundColor, tokensFor(BttThemeVariant.signature).bgObsidian);
      expect(mono.scaffoldBackgroundColor, tokensFor(BttThemeVariant.mono).bgObsidian);
      expect(aurora.scaffoldBackgroundColor, tokensFor(BttThemeVariant.aurora).bgObsidian);
      expect(cardRadiusOf(sig), tokensFor(BttThemeVariant.signature).cardRadius);
      expect(cardRadiusOf(mono), tokensFor(BttThemeVariant.mono).cardRadius);
      expect(cardRadiusOf(aurora), tokensFor(BttThemeVariant.aurora).cardRadius);
      expect(cardRadiusOf(mono), lessThan(cardRadiusOf(sig)));
      expect(cardRadiusOf(aurora), greaterThan(cardRadiusOf(sig)));
    });

    test('custom font family overrides body + display when given', () {
      final themed = themeFor(customFontFamily: 'BttCustom');
      expect(themed.textTheme.bodyMedium?.fontFamily, 'BttCustom');
      expect(themed.textTheme.displayLarge?.fontFamily, 'BttCustom');
      // Small mono labels stay JetBrains Mono by design — the custom font
      // never touches them.
      expect(themed.textTheme.labelSmall?.fontFamily, 'JetBrains Mono');
    });

    test('no custom font keeps the built-in fonts', () {
      final themed = themeFor();
      expect(themed.textTheme.bodyMedium?.fontFamily, isNot('BttCustom'));
      expect(themed.textTheme.labelSmall?.fontFamily, 'JetBrains Mono');
    });
  });
}
