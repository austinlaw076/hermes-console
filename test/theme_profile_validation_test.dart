import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/theme_contrast.dart';
import 'package:hermes_android/core/theme/theme_profile.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';
import 'package:hermes_android/core/theme/theme_profile_derivation.dart';
import 'package:hermes_android/core/theme/theme_profile_validator.dart';

import 'support/theme_profile_fixtures.dart';

void main() {
  group('ThemeContrast', () {
    test('uses the WCAG ratio and treats the exact threshold as passing', () {
      const foreground = Color(0xFF747474);
      const background = Color(0xFF000000);
      final exact = ThemeContrast.ratio(foreground, background);

      expect(
        ThemeContrast.ratio(Colors.white, Colors.black),
        closeTo(21, 1e-9),
      );
      expect(
        ThemeContrast.meets(foreground, background, minimum: exact + 0.0001),
        isFalse,
      );
      expect(
        ThemeContrast.meets(foreground, background, minimum: exact),
        isTrue,
      );
      expect(
        ThemeContrast.meets(foreground, background, minimum: exact - 0.0001),
        isTrue,
      );
    });

    test('composites alpha instead of ignoring it', () {
      const halfWhite = Color(0x80FFFFFF);
      const black = Color(0xFF000000);
      expect(
        ThemeContrast.ratio(halfWhite, black),
        lessThan(ThemeContrast.ratio(Colors.white, black)),
      );
    });

    test('reports when no single foreground can meet every surface', () {
      const foreground = Color(0xFF7F7F7F);
      final result = ThemeContrast.adjustForContrastResult(foreground, const [
        Color(0xFFDDA1FF),
        Color(0xFF141414),
      ], minimum: 4.5);

      expect(result.achieved, isFalse);
      expect(result.worstRatio, lessThan(4.5));
    });
  });

  group('ThemeProfileDeriver', () {
    const seeds = ThemeBasicSeeds(
      background: Color(0xFF0B0C0E),
      surface: Color(0xFF15171A),
      accent: Color(0xFFE8821C),
      secondary: Color(0xFF4FB8C9),
      textPrimary: Color(0xFFF3F3F3),
    );

    test(
      'is deterministic and preserves all five user seeds byte-for-byte',
      () {
        final first = ThemeProfileDeriver.deriveBasicPalette(
          seeds,
          brightness: ThemeProfileBrightness.dark,
        );
        final second = ThemeProfileDeriver.deriveBasicPalette(
          seeds,
          brightness: ThemeProfileBrightness.dark,
        );

        expect(first.palette, second.palette);
        expect(first.warnings, second.warnings);
        expect(first.palette.background, seeds.background);
        expect(first.palette.surface, seeds.surface);
        expect(first.palette.accent, seeds.accent);
        expect(first.palette.secondary, seeds.secondary);
        expect(first.palette.textPrimary, seeds.textPrimary);
      },
    );

    test('derives readable onAccent, accentText and informational text', () {
      final result = ThemeProfileDeriver.deriveBasicPalette(
        seeds,
        brightness: ThemeProfileBrightness.dark,
      );
      final palette = result.palette;

      expect(
        ThemeContrast.ratio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ThemeContrast.ratio(palette.accentText, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ThemeContrast.ratio(palette.textSecondary, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ThemeContrast.ratio(palette.textSecondary, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ThemeContrast.ratio(palette.error, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('adapts dark seeds into an actually light, readable palette', () {
      final adapted = ThemeProfileDeriver.adaptBasicSeedsForBrightness(
        seeds,
        brightness: ThemeProfileBrightness.light,
      );

      expect(adapted.background.computeLuminance(), greaterThan(0.7));
      expect(adapted.surface.computeLuminance(), greaterThan(0.8));
      expect(
        ThemeContrast.ratio(adapted.textPrimary, adapted.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ThemeContrast.ratio(adapted.accent, adapted.surface),
        greaterThanOrEqualTo(3),
      );
    });

    test('reports unsafe seeds instead of silently modifying them', () {
      const unsafe = ThemeBasicSeeds(
        background: Color(0xFF101010),
        surface: Color(0xFF111111),
        accent: Color(0xFF121212),
        secondary: Color(0xFF131313),
        textPrimary: Color(0xFF141414),
      );
      final result = ThemeProfileDeriver.deriveBasicPalette(
        unsafe,
        brightness: ThemeProfileBrightness.dark,
      );
      expect(
        result.warnings.map((warning) => warning.code),
        containsAll(['seed_text_contrast', 'seed_accent_contrast']),
      );
      expect(result.palette.textPrimary, unsafe.textPrimary);
      expect(result.palette.accent, unsafe.accent);
    });

    test('rejects unknown derivation versions', () {
      expect(
        () => ThemeProfileDeriver.deriveBasicPalette(
          seeds,
          brightness: ThemeProfileBrightness.dark,
          derivationVersion: 2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ThemeProfileValidator and repair', () {
    test('accepts the canonical fixture and evaluates every required pair', () {
      final validation = ThemeProfileValidator.validate(validCustomTheme());
      expect(validation.syntaxErrors, isEmpty);
      expect(validation.contrastFailures, isEmpty);
      expect(validation.isDraftSavable, isTrue);
      expect(validation.isActivatable, isTrue);
    });

    test('invalid contrast remains draft-savable but not activatable', () {
      final profile = validCustomTheme(draft: true);
      final invalid = profile.copyWith(
        palette: profile.palette.copyWith(
          accentText: profile.palette.background,
        ),
      );
      final validation = ThemeProfileValidator.validate(invalid);

      expect(validation.isDraftSavable, isTrue);
      expect(validation.isActivatable, isFalse);
      expect(
        validation.contrastFailures,
        contains(
          isA<ThemeContrastFailure>()
              .having(
                (failure) => failure.foregroundToken,
                'foreground',
                'accent_text',
              )
              .having(
                (failure) => failure.backgroundToken,
                'background',
                'background',
              ),
        ),
      );
    });

    test('repair is deterministic, visible and never mutates the original', () {
      final original = validCustomTheme(draft: true);
      final invalid = original.copyWith(
        palette: original.palette.copyWith(
          accentText: original.palette.background,
        ),
      );

      final first = ThemeProfileValidator.proposeRepair(invalid);
      final second = ThemeProfileValidator.proposeRepair(invalid);
      expect(first.changes.length, 1);
      expect(first.changes.first.token, 'accent_text');
      expect(first.changes.first.to, second.changes.first.to);
      expect(first.changes.first.ratioBefore, lessThan(4.5));
      expect(first.changes.first.ratioAfter, greaterThanOrEqualTo(4.5));
      expect(invalid.palette.accentText, invalid.palette.background);

      final repaired = first.applyTo(invalid).copyWith(draft: false);
      expect(ThemeProfileValidator.validate(repaired).isActivatable, isTrue);
    });

    test('repair resolves the exact light-background dark-theme draft', () {
      const seeds = ThemeBasicSeeds(
        background: Color(0xFFDDA1FF),
        surface: Color(0xFF141414),
        accent: Color(0xFFDCD5FF),
        secondary: Color(0xFFFFFFEB),
        textPrimary: Color(0xFF7F7F7F),
      );
      final derived = ThemeProfileDeriver.deriveBasicPalette(
        seeds,
        brightness: ThemeProfileBrightness.dark,
      );
      final profile = validCustomTheme(draft: true).copyWith(
        brightness: ThemeProfileBrightness.dark,
        palette: derived.palette,
      );

      final before = ThemeProfileValidator.validate(profile);
      expect(before.contrastFailures, hasLength(3));

      final proposal = ThemeProfileValidator.proposeRepair(profile);
      final repaired = proposal.applyTo(profile);

      expect(proposal.isComplete, isTrue);
      expect(proposal.remainingFailures, isEmpty);
      expect(proposal.repairedPalette.background, const Color(0xFF1B131F));
      expect(proposal.repairedPalette.textSecondary, const Color(0xFF807E81));
      expect(
        ThemeProfileValidator.validate(repaired).contrastFailures,
        isEmpty,
      );
      expect(profile.palette.background, seeds.background);
    });

    test('programmatically invalid syntax cannot be saved as a draft', () {
      final profile = validCustomTheme().copyWith(
        componentProfileId: 'does-not-exist',
      );
      final validation = ThemeProfileValidator.validate(profile);
      expect(validation.syntaxErrors, isNotEmpty);
      expect(validation.isDraftSavable, isFalse);
      expect(validation.normalizedProfile, isNull);
    });

    test(
      'translucent non-zero colors warn while zero alpha is a syntax error',
      () {
        final profile = validCustomTheme();
        final translucent = profile.copyWith(
          palette: profile.palette.copyWith(divider: const Color(0x803B3E44)),
        );
        expect(
          ThemeProfileValidator.validate(
            translucent,
          ).warnings.map((warning) => warning.code),
          contains('translucent_color'),
        );

        final transparent = profile.copyWith(
          palette: profile.palette.copyWith(divider: const Color(0x003B3E44)),
        );
        expect(
          ThemeProfileValidator.validate(transparent).isDraftSavable,
          isFalse,
        );
      },
    );

    test('canonical encoding of repaired colors remains explicit ARGB', () {
      final profile = validCustomTheme();
      final encoded = ThemeProfileCodec.encode(profile);
      expect(encoded, contains('#FFE8821C'));
      expect(encoded, isNot(contains('#E8821C"')));
    });
  });
}
