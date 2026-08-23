import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'component_profile.dart';
import 'theme_profile.dart';

/// Lossless bridge from the existing immutable preset catalog to ThemeProfile.
///
/// It reads [AppTheme] but does not change its storage or ThemeData behavior.
abstract final class ThemeProfileAdapter {
  static List<ThemeProfile> get builtinProfiles =>
      List.unmodifiable(AppTheme.presets.map(fromPreset));

  static ThemeProfile fromPreset(HermesThemePreset preset) {
    final colors = preset.colors;
    return ThemeProfile(
      id: preset.id,
      name: preset.name,
      source: ThemeProfileSource.builtin,
      basePresetId: preset.id,
      brightness: preset.brightness == Brightness.dark
          ? ThemeProfileBrightness.dark
          : ThemeProfileBrightness.light,
      draft: false,
      palette: ThemePalette(
        background: colors.background,
        surface: colors.surface,
        surfaceVariant: colors.surfaceVariant,
        accent: colors.accent,
        accentHover: colors.accentHover,
        accentText: colors.accentText,
        secondary: preset.secondary ?? colors.accentHover,
        onAccent: colors.onAccent,
        textPrimary: colors.textPrimary,
        textSecondary: colors.textSecondary,
        textDisabled: colors.textDisabled,
        error: colors.error,
        success: colors.success,
        warning: colors.warning,
        divider: colors.divider,
      ),
      typography: ThemeTypography(
        fontFamily: preset.fontFamily,
        codeFontFamily: 'JetBrainsMono',
        titleWeight: preset.titleWeight.value,
        titleSpacing: preset.titleSpacing,
        uppercaseTitles: preset.uppercaseTitles,
      ),
      componentProfileId: ComponentProfiles.minimal.id,
      metadata: ThemeMetadata(description: preset.tagline),
    );
  }

  static ThemeProfile duplicatePreset(
    HermesThemePreset preset, {
    required String id,
    required String name,
  }) => fromPreset(
    preset,
  ).copyWith(id: id, name: name, source: ThemeProfileSource.custom);

  static HermesThemeColors colorsFromProfile(ThemeProfile profile) =>
      HermesThemeColors(
        background: profile.palette.background,
        surface: profile.palette.surface,
        surfaceVariant: profile.palette.surfaceVariant,
        accent: profile.palette.accent,
        accentHover: profile.palette.accentHover,
        accentText: profile.palette.accentText,
        secondary: profile.palette.secondary,
        onAccent: profile.palette.onAccent,
        textPrimary: profile.palette.textPrimary,
        textSecondary: profile.palette.textSecondary,
        textDisabled: profile.palette.textDisabled,
        error: profile.palette.error,
        success: profile.palette.success,
        warning: profile.palette.warning,
        divider: profile.palette.divider,
        uppercaseTitles: profile.typography.uppercaseTitles,
      );

  static String resolveLegacyBuiltinId(String? id) =>
      AppTheme.themeIdFromLegacy(id);

  static bool isBuiltinId(String id) =>
      AppTheme.presets.any((preset) => preset.id == id);
}
