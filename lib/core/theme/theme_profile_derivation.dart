import 'package:flutter/material.dart';

import 'theme_contrast.dart';
import 'theme_profile.dart';

@immutable
final class ThemePaletteDerivation {
  final ThemePalette palette;
  final List<ThemeProfileWarning> warnings;

  const ThemePaletteDerivation({
    required this.palette,
    this.warnings = const [],
  });
}

abstract final class ThemeProfileDeriver {
  static const int currentDerivationVersion = 1;

  /// Adapta los cinco colores base al modo visual de destino. Cambiar solo el
  /// enum `brightness` no aclara una paleta oscura: background y surface siguen
  /// siendo negros y la preview parece no responder. Esta conversión conserva
  /// el carácter cromático, pero mueve superficies y texto al extremo correcto
  /// y garantiza el contraste mínimo de los colores funcionales.
  static ThemeBasicSeeds adaptBasicSeedsForBrightness(
    ThemeBasicSeeds seeds, {
    required ThemeProfileBrightness brightness,
  }) {
    final light = brightness == ThemeProfileBrightness.light;
    final background = ThemeContrast.blend(
      seeds.background,
      light ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      light ? 0.92 : 0.94,
    );
    final surface = ThemeContrast.blend(
      seeds.surface,
      light ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      light ? 0.97 : 0.88,
    );
    final textSeed = ThemeContrast.blend(
      seeds.textPrimary,
      light ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      light ? 0.88 : 0.90,
    );
    final textPrimary = ThemeContrast.adjustForContrast(textSeed, [
      background,
      surface,
    ], minimum: 4.5);
    final accent = ThemeContrast.adjustForContrast(seeds.accent, [
      background,
      surface,
    ], minimum: 3);
    final secondary = ThemeContrast.adjustForContrast(seeds.secondary, [
      background,
      surface,
    ], minimum: 3);
    return ThemeBasicSeeds(
      background: background,
      surface: surface,
      accent: accent,
      secondary: secondary,
      textPrimary: textPrimary,
    );
  }

  static ThemePaletteDerivation deriveBasicPalette(
    ThemeBasicSeeds seeds, {
    required ThemeProfileBrightness brightness,
    int derivationVersion = currentDerivationVersion,
  }) {
    if (derivationVersion != currentDerivationVersion) {
      throw ArgumentError.value(
        derivationVersion,
        'derivationVersion',
        'Unsupported theme palette derivation version',
      );
    }

    final warnings = <ThemeProfileWarning>[];
    if (ThemeContrast.ratio(seeds.textPrimary, seeds.background) < 4.5 ||
        ThemeContrast.ratio(seeds.textPrimary, seeds.surface) < 4.5) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'seed_text_contrast',
          field: 'text_primary',
          message:
              'The selected primary text does not meet normal-text contrast',
        ),
      );
    }
    if (ThemeContrast.ratio(seeds.accent, seeds.surface) < 3) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'seed_accent_contrast',
          field: 'accent',
          message: 'The selected accent may not distinguish essential controls',
        ),
      );
    }
    if ([
      seeds.background,
      seeds.surface,
      seeds.accent,
      seeds.secondary,
      seeds.textPrimary,
    ].any((color) => (color.toARGB32() >> 24) != 0xFF)) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'seed_alpha',
          field: 'palette',
          message: 'Translucent seed colors may render differently by surface',
        ),
      );
    }

    final dark = brightness == ThemeProfileBrightness.dark;
    final surfaceVariant = ThemeContrast.blend(
      seeds.surface,
      seeds.textPrimary,
      dark ? 0.10 : 0.07,
    );
    final accentHover = ThemeContrast.blend(
      seeds.accent,
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      0.18,
    );
    final onAccent = ThemeContrast.bestBlackOrWhite(seeds.accent);
    final accentText = ThemeContrast.adjustForContrast(seeds.accent, [
      seeds.background,
    ], minimum: 4.5);

    final textSecondarySeed = ThemeContrast.blend(
      seeds.textPrimary,
      seeds.background,
      0.24,
    );
    final textSecondary = ThemeContrast.adjustForContrast(textSecondarySeed, [
      seeds.background,
      seeds.surface,
    ], minimum: 4.5);
    final textDisabled = ThemeContrast.blend(
      seeds.textPrimary,
      seeds.background,
      dark ? 0.48 : 0.52,
    );
    final divider = ThemeContrast.blend(
      seeds.surface,
      seeds.textPrimary,
      dark ? 0.16 : 0.20,
    );

    final stateSeeds = dark
        ? const (
            error: Color(0xFFFF6B6B),
            success: Color(0xFF4BCB78),
            warning: Color(0xFFFFBE55),
          )
        : const (
            error: Color(0xFFB3261E),
            success: Color(0xFF166534),
            warning: Color(0xFF8A4B08),
          );
    final error = ThemeContrast.adjustForContrast(stateSeeds.error, [
      seeds.surface,
    ], minimum: 4.5);
    final success = ThemeContrast.adjustForContrast(stateSeeds.success, [
      seeds.surface,
    ], minimum: 3);
    final warning = ThemeContrast.adjustForContrast(stateSeeds.warning, [
      seeds.surface,
    ], minimum: 3);

    return ThemePaletteDerivation(
      palette: ThemePalette(
        // The five user-controlled seeds remain byte-identical.
        background: seeds.background,
        surface: seeds.surface,
        surfaceVariant: surfaceVariant,
        accent: seeds.accent,
        accentHover: accentHover,
        accentText: accentText,
        secondary: seeds.secondary,
        onAccent: onAccent,
        textPrimary: seeds.textPrimary,
        textSecondary: textSecondary,
        textDisabled: textDisabled,
        error: error,
        success: success,
        warning: warning,
        divider: divider,
      ),
      warnings: List.unmodifiable(warnings),
    );
  }
}
