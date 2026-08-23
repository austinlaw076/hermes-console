import 'package:flutter/material.dart';

import 'component_profile.dart';
import 'theme_contrast.dart';
import 'theme_profile.dart';
import 'theme_profile_derivation.dart';

@immutable
final class ThemeSyntaxIssue {
  final String code;
  final String field;
  final String message;

  const ThemeSyntaxIssue({
    required this.code,
    required this.field,
    required this.message,
  });
}

@immutable
final class ThemeContrastFailure {
  final String foregroundToken;
  final String backgroundToken;
  final double ratio;
  final double minimum;

  const ThemeContrastFailure({
    required this.foregroundToken,
    required this.backgroundToken,
    required this.ratio,
    required this.minimum,
  });
}

@immutable
final class ThemeValidationResult {
  final List<ThemeSyntaxIssue> syntaxErrors;
  final List<ThemeContrastFailure> contrastFailures;
  final List<ThemeProfileWarning> warnings;
  final ThemeProfile? normalizedProfile;

  const ThemeValidationResult({
    this.syntaxErrors = const [],
    this.contrastFailures = const [],
    this.warnings = const [],
    this.normalizedProfile,
  });

  bool get isDraftSavable => syntaxErrors.isEmpty && normalizedProfile != null;
  bool get isActivatable => isDraftSavable && contrastFailures.isEmpty;
}

@immutable
final class ThemeRepairChange {
  final String token;
  final Color from;
  final Color to;
  final double ratioBefore;
  final double ratioAfter;
  final String against;

  const ThemeRepairChange({
    required this.token,
    required this.from,
    required this.to,
    required this.ratioBefore,
    required this.ratioAfter,
    required this.against,
  });
}

@immutable
final class ThemeRepairProposal {
  final List<ThemeRepairChange> changes;
  final ThemePalette repairedPalette;
  final List<ThemeContrastFailure> remainingFailures;

  const ThemeRepairProposal({
    required this.changes,
    required this.repairedPalette,
    this.remainingFailures = const [],
  });

  bool get isEmpty => changes.isEmpty;
  bool get isComplete => remainingFailures.isEmpty;

  ThemeProfile applyTo(ThemeProfile profile) =>
      profile.copyWith(palette: repairedPalette);
}

abstract final class ThemeProfileValidator {
  static const Map<String, List<(String, double)>> _contrastRequirements = {
    'text_primary': [('background', 4.5), ('surface', 4.5)],
    'text_secondary': [('background', 4.5), ('surface', 4.5)],
    'on_accent': [('accent', 4.5)],
    'accent_text': [('background', 4.5)],
    'error': [('surface', 4.5)],
    'accent': [('surface', 3.0)],
  };

  static ThemeValidationResult validate(ThemeProfile profile) {
    final syntax = <ThemeSyntaxIssue>[];
    final warnings = <ThemeProfileWarning>[];

    if (profile.schemaVersion != themeProfileSchemaVersion) {
      syntax.add(
        const ThemeSyntaxIssue(
          code: 'schema',
          field: 'schema_version',
          message: 'Unsupported theme schema',
        ),
      );
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(profile.id)) {
      syntax.add(
        const ThemeSyntaxIssue(
          code: 'id',
          field: 'id',
          message: 'Unsafe theme id',
        ),
      );
    }
    final name = profile.name.trim();
    if (name.isEmpty || name.runes.length > 192) {
      // The codec performs true grapheme-oriented validation. This larger rune
      // bound catches unsafe programmatic construction without rejecting valid
      // multi-codepoint emoji names already accepted by the codec.
      syntax.add(
        const ThemeSyntaxIssue(
          code: 'name',
          field: 'name',
          message: 'Invalid theme name',
        ),
      );
    }
    if (!ComponentProfiles.ids.contains(profile.componentProfileId)) {
      syntax.add(
        const ThemeSyntaxIssue(
          code: 'component_profile',
          field: 'component_profile_id',
          message: 'Unknown component profile',
        ),
      );
    }
    if (!const {
          400,
          500,
          600,
          700,
          800,
        }.contains(profile.typography.titleWeight) ||
        !profile.typography.titleSpacing.isFinite ||
        profile.typography.titleSpacing < -0.5 ||
        profile.typography.titleSpacing > 3) {
      syntax.add(
        const ThemeSyntaxIssue(
          code: 'typography',
          field: 'typography',
          message: 'Invalid theme typography',
        ),
      );
    }

    const essentialTokens = [
      'background',
      'surface',
      'surface_variant',
      'accent',
      'accent_hover',
      'accent_text',
      'secondary',
      'on_accent',
      'text_primary',
      'text_secondary',
      'text_disabled',
      'error',
      'success',
      'warning',
      'divider',
    ];
    for (final token in essentialTokens) {
      final alpha =
          (profile.palette.colorForToken(token).toARGB32() >> 24) & 0xFF;
      if (alpha == 0) {
        syntax.add(
          ThemeSyntaxIssue(
            code: 'transparent_color',
            field: token,
            message: '$token cannot be fully transparent',
          ),
        );
      } else if (alpha != 0xFF) {
        warnings.add(
          ThemeProfileWarning(
            code: 'translucent_color',
            field: token,
            message: '$token is translucent and depends on its surface',
          ),
        );
      }
    }

    final contrastFailures = <ThemeContrastFailure>[];
    void requireContrast(String foreground, String background, double minimum) {
      final ratio = ThemeContrast.ratio(
        profile.palette.colorForToken(foreground),
        profile.palette.colorForToken(background),
      );
      if (!ThemeContrast.meets(
        profile.palette.colorForToken(foreground),
        profile.palette.colorForToken(background),
        minimum: minimum,
      )) {
        contrastFailures.add(
          ThemeContrastFailure(
            foregroundToken: foreground,
            backgroundToken: background,
            ratio: ratio,
            minimum: minimum,
          ),
        );
      }
    }

    for (final requirement in _contrastRequirements.entries) {
      for (final background in requirement.value) {
        requireContrast(requirement.key, background.$1, background.$2);
      }
    }

    if (ThemeContrast.ratio(
          profile.palette.textDisabled,
          profile.palette.background,
        ) <
        3) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'disabled_contrast',
          field: 'text_disabled',
          message: 'Disabled text is below the recommended 3:1 contrast',
        ),
      );
    }

    return ThemeValidationResult(
      syntaxErrors: List.unmodifiable(syntax),
      contrastFailures: List.unmodifiable(contrastFailures),
      warnings: List.unmodifiable(warnings),
      normalizedProfile: syntax.isEmpty ? profile : null,
    );
  }

  static ThemeRepairProposal proposeRepair(ThemeProfile profile) {
    final originalPalette = profile.palette;
    final wasBasicDerived = _matchesBasicDerivation(profile);
    var working = profile;

    // Changing a shared surface can create a secondary foreground failure.
    // Revalidate after each deterministic pass until stable, without mutating
    // [profile]. Eight passes cover every dependency in the required-pair
    // graph while leaving headroom for a background/accent interaction.
    for (var pass = 0; pass < 8; pass++) {
      final validation = validate(working);
      if (validation.contrastFailures.isEmpty) break;
      final grouped = <String, List<ThemeContrastFailure>>{};
      for (final failure in validation.contrastFailures) {
        grouped.putIfAbsent(failure.foregroundToken, () => []).add(failure);
      }

      var nextPalette = working.palette;
      var changed = false;
      for (final entry in grouped.entries) {
        final current = nextPalette.colorForToken(entry.key);
        final requirements = _contrastRequirements[entry.key] ?? const [];
        final backgroundTokens = requirements
            .map((requirement) => requirement.$1)
            .toList(growable: false);
        final backgrounds = backgroundTokens
            .map(nextPalette.colorForToken)
            .toList(growable: false);
        final minimum = requirements
            .map((requirement) => requirement.$2)
            .reduce((left, right) => left > right ? left : right);
        final adjustment = ThemeContrast.adjustForContrastResult(
          current,
          backgrounds,
          minimum: minimum,
        );

        if (adjustment.achieved) {
          if (adjustment.color != current) {
            nextPalette = nextPalette.withToken(entry.key, adjustment.color);
            changed = true;
          }
          continue;
        }

        // A foreground cannot always contrast with two surfaces that sit at
        // opposite luminance extremes. Prefer preserving the user's text and
        // move only the incoherent surface towards the declared brightness.
        // This is the exact case that previously made repair oscillate.
        final surfaceEndpoint =
            profile.brightness == ThemeProfileBrightness.dark
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF);
        var harmonized = nextPalette;
        var canPreserveForeground = true;
        for (final backgroundToken in backgroundTokens) {
          final background = harmonized.colorForToken(backgroundToken);
          if (ThemeContrast.meets(current, background, minimum: minimum)) {
            continue;
          }
          final repairedBackground = _adjustBackgroundToward(
            background,
            surfaceEndpoint,
            foreground: current,
            minimum: minimum,
          );
          if (repairedBackground == null) {
            canPreserveForeground = false;
            break;
          }
          harmonized = harmonized.withToken(
            backgroundToken,
            repairedBackground,
          );
        }
        if (canPreserveForeground) {
          if (harmonized != nextPalette) {
            nextPalette = harmonized;
            changed = true;
          }
          continue;
        }

        // Last deterministic fallback: bring the required surfaces just far
        // enough towards the theme side that a white (dark theme) or black
        // (light theme) foreground can satisfy all of them, then make the
        // smallest foreground adjustment. The proposal remains explicit and
        // is revalidated before the UI may apply it.
        final foregroundEndpoint =
            profile.brightness == ThemeProfileBrightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);
        var coherent = nextPalette;
        for (final backgroundToken in backgroundTokens) {
          final background = coherent.colorForToken(backgroundToken);
          final repairedBackground = _adjustBackgroundToward(
            background,
            surfaceEndpoint,
            foreground: foregroundEndpoint,
            minimum: minimum,
          );
          coherent = coherent.withToken(
            backgroundToken,
            repairedBackground ?? surfaceEndpoint,
          );
        }
        final coherentBackgrounds = backgroundTokens
            .map(coherent.colorForToken)
            .toList(growable: false);
        final coherentAdjustment = ThemeContrast.adjustForContrastResult(
          current,
          coherentBackgrounds,
          minimum: minimum,
        );
        if (coherentAdjustment.achieved) {
          coherent = coherent.withToken(entry.key, coherentAdjustment.color);
          if (coherent != nextPalette) {
            nextPalette = coherent;
            changed = true;
          }
        } else if (adjustment.color != current) {
          // Keep the best-effort color visible in the proposal, but the final
          // validation below will mark it incomplete and prevent application.
          nextPalette = nextPalette.withToken(entry.key, adjustment.color);
          changed = true;
        }
      }
      if (!changed) break;
      working = working.copyWith(palette: nextPalette);
    }

    // Basic mode promises deterministic derived tokens. If the incoming
    // palette still matched that promise, re-derive after repairing a seed so
    // hidden tokens do not drift from what the editor would generate. An
    // advanced/imported palette that has manual token edits stays untouched.
    if (wasBasicDerived) {
      final seeds = ThemeBasicSeeds(
        background: working.palette.background,
        surface: working.palette.surface,
        accent: working.palette.accent,
        secondary: working.palette.secondary,
        textPrimary: working.palette.textPrimary,
      );
      working = working.copyWith(
        palette: ThemeProfileDeriver.deriveBasicPalette(
          seeds,
          brightness: working.brightness,
        ).palette,
      );
    }

    final changes = <ThemeRepairChange>[];
    const tokens = [
      'background',
      'surface',
      'surface_variant',
      'accent',
      'accent_hover',
      'accent_text',
      'secondary',
      'on_accent',
      'text_primary',
      'text_secondary',
      'text_disabled',
      'error',
      'success',
      'warning',
      'divider',
    ];
    final originalFailures = validate(profile).contrastFailures;
    for (final token in tokens) {
      final from = originalPalette.colorForToken(token);
      final to = working.palette.colorForToken(token);
      if (from == to) continue;
      final relatedForeground = originalFailures.where(
        (failure) => failure.foregroundToken == token,
      );
      final relatedBackground = originalFailures.where(
        (failure) => failure.backgroundToken == token,
      );
      final against = relatedForeground.isNotEmpty
          ? relatedForeground.first.backgroundToken
          : relatedBackground.isNotEmpty
          ? relatedBackground.first.foregroundToken
          : 'background';
      changes.add(
        ThemeRepairChange(
          token: token,
          from: from,
          to: to,
          ratioBefore: ThemeContrast.ratio(
            from,
            originalPalette.colorForToken(against),
          ),
          ratioAfter: ThemeContrast.ratio(
            to,
            working.palette.colorForToken(against),
          ),
          against: against,
        ),
      );
    }

    return ThemeRepairProposal(
      changes: List.unmodifiable(changes),
      repairedPalette: working.palette,
      remainingFailures: List.unmodifiable(validate(working).contrastFailures),
    );
  }

  static Color? _adjustBackgroundToward(
    Color background,
    Color endpoint, {
    required Color foreground,
    required double minimum,
  }) {
    if (ThemeContrast.meets(foreground, background, minimum: minimum)) {
      return background;
    }
    for (var step = 1; step <= 1000; step++) {
      final candidate = ThemeContrast.blend(background, endpoint, step / 1000);
      if (ThemeContrast.meets(foreground, candidate, minimum: minimum)) {
        return candidate;
      }
    }
    return null;
  }

  static bool _matchesBasicDerivation(ThemeProfile profile) {
    final expected = ThemeProfileDeriver.deriveBasicPalette(
      ThemeBasicSeeds(
        background: profile.palette.background,
        surface: profile.palette.surface,
        accent: profile.palette.accent,
        secondary: profile.palette.secondary,
        textPrimary: profile.palette.textPrimary,
      ),
      brightness: profile.brightness,
    ).palette;
    const tokens = [
      'background',
      'surface',
      'surface_variant',
      'accent',
      'accent_hover',
      'accent_text',
      'secondary',
      'on_accent',
      'text_primary',
      'text_secondary',
      'text_disabled',
      'error',
      'success',
      'warning',
      'divider',
    ];
    return tokens.every(
      (token) =>
          expected.colorForToken(token) == profile.palette.colorForToken(token),
    );
  }
}
