import 'package:flutter/material.dart';

/// Versioned, local-only theme model used by Theme Studio and import/export.
///
/// It deliberately contains no connection, session or filesystem fields.
const int themeProfileSchemaVersion = 1;

enum ThemeProfileSource { builtin, custom, imported }

enum ThemeProfileBrightness { dark, light }

@immutable
final class ThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color accent;
  final Color accentHover;
  final Color accentText;
  final Color secondary;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color error;
  final Color success;
  final Color warning;
  final Color divider;

  const ThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.accent,
    required this.accentHover,
    required this.accentText,
    required this.secondary,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.error,
    required this.success,
    required this.warning,
    required this.divider,
  });

  ThemePalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? accent,
    Color? accentHover,
    Color? accentText,
    Color? secondary,
    Color? onAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? error,
    Color? success,
    Color? warning,
    Color? divider,
  }) => ThemePalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    accent: accent ?? this.accent,
    accentHover: accentHover ?? this.accentHover,
    accentText: accentText ?? this.accentText,
    secondary: secondary ?? this.secondary,
    onAccent: onAccent ?? this.onAccent,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled: textDisabled ?? this.textDisabled,
    error: error ?? this.error,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    divider: divider ?? this.divider,
  );

  Color colorForToken(String token) => switch (token) {
    'background' => background,
    'surface' => surface,
    'surface_variant' => surfaceVariant,
    'accent' => accent,
    'accent_hover' => accentHover,
    'accent_text' => accentText,
    'secondary' => secondary,
    'on_accent' => onAccent,
    'text_primary' => textPrimary,
    'text_secondary' => textSecondary,
    'text_disabled' => textDisabled,
    'error' => error,
    'success' => success,
    'warning' => warning,
    'divider' => divider,
    _ => throw ArgumentError.value(token, 'token', 'Unknown palette token'),
  };

  ThemePalette withToken(String token, Color color) => switch (token) {
    'background' => copyWith(background: color),
    'surface' => copyWith(surface: color),
    'surface_variant' => copyWith(surfaceVariant: color),
    'accent' => copyWith(accent: color),
    'accent_hover' => copyWith(accentHover: color),
    'accent_text' => copyWith(accentText: color),
    'secondary' => copyWith(secondary: color),
    'on_accent' => copyWith(onAccent: color),
    'text_primary' => copyWith(textPrimary: color),
    'text_secondary' => copyWith(textSecondary: color),
    'text_disabled' => copyWith(textDisabled: color),
    'error' => copyWith(error: color),
    'success' => copyWith(success: color),
    'warning' => copyWith(warning: color),
    'divider' => copyWith(divider: color),
    _ => throw ArgumentError.value(token, 'token', 'Unknown palette token'),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemePalette &&
          background == other.background &&
          surface == other.surface &&
          surfaceVariant == other.surfaceVariant &&
          accent == other.accent &&
          accentHover == other.accentHover &&
          accentText == other.accentText &&
          secondary == other.secondary &&
          onAccent == other.onAccent &&
          textPrimary == other.textPrimary &&
          textSecondary == other.textSecondary &&
          textDisabled == other.textDisabled &&
          error == other.error &&
          success == other.success &&
          warning == other.warning &&
          divider == other.divider;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    surfaceVariant,
    accent,
    accentHover,
    accentText,
    secondary,
    onAccent,
    textPrimary,
    textSecondary,
    textDisabled,
    error,
    success,
    warning,
    divider,
  );
}

@immutable
final class ThemeTypography {
  final String fontFamily;
  final String codeFontFamily;
  final int titleWeight;
  final double titleSpacing;
  final bool uppercaseTitles;

  const ThemeTypography({
    required this.fontFamily,
    required this.codeFontFamily,
    required this.titleWeight,
    required this.titleSpacing,
    required this.uppercaseTitles,
  });

  ThemeTypography copyWith({
    String? fontFamily,
    String? codeFontFamily,
    int? titleWeight,
    double? titleSpacing,
    bool? uppercaseTitles,
  }) => ThemeTypography(
    fontFamily: fontFamily ?? this.fontFamily,
    codeFontFamily: codeFontFamily ?? this.codeFontFamily,
    titleWeight: titleWeight ?? this.titleWeight,
    titleSpacing: titleSpacing ?? this.titleSpacing,
    uppercaseTitles: uppercaseTitles ?? this.uppercaseTitles,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeTypography &&
          fontFamily == other.fontFamily &&
          codeFontFamily == other.codeFontFamily &&
          titleWeight == other.titleWeight &&
          titleSpacing == other.titleSpacing &&
          uppercaseTitles == other.uppercaseTitles;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    codeFontFamily,
    titleWeight,
    titleSpacing,
    uppercaseTitles,
  );
}

@immutable
final class ThemeMetadata {
  final String createdWith;
  final int createdWithSchema;
  final int derivationVersion;
  final String? description;

  const ThemeMetadata({
    this.createdWith = 'Hermes Console',
    this.createdWithSchema = themeProfileSchemaVersion,
    this.derivationVersion = 1,
    this.description,
  });

  ThemeMetadata copyWith({
    String? createdWith,
    int? createdWithSchema,
    int? derivationVersion,
    String? description,
    bool clearDescription = false,
  }) => ThemeMetadata(
    createdWith: createdWith ?? this.createdWith,
    createdWithSchema: createdWithSchema ?? this.createdWithSchema,
    derivationVersion: derivationVersion ?? this.derivationVersion,
    description: clearDescription ? null : (description ?? this.description),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeMetadata &&
          createdWith == other.createdWith &&
          createdWithSchema == other.createdWithSchema &&
          derivationVersion == other.derivationVersion &&
          description == other.description;

  @override
  int get hashCode => Object.hash(
    createdWith,
    createdWithSchema,
    derivationVersion,
    description,
  );
}

@immutable
final class ThemeProfile {
  final int schemaVersion;
  final String id;
  final String name;
  final ThemeProfileSource source;
  final String? basePresetId;
  final ThemeProfileBrightness brightness;
  final bool draft;
  final ThemePalette palette;
  final ThemeTypography typography;
  final String componentProfileId;
  final ThemeMetadata metadata;

  const ThemeProfile({
    this.schemaVersion = themeProfileSchemaVersion,
    required this.id,
    required this.name,
    required this.source,
    this.basePresetId,
    required this.brightness,
    required this.draft,
    required this.palette,
    required this.typography,
    required this.componentProfileId,
    required this.metadata,
  });

  bool get isBuiltin => source == ThemeProfileSource.builtin;
  bool get isEditable => !isBuiltin;

  ThemeProfile copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    ThemeProfileSource? source,
    String? basePresetId,
    bool clearBasePresetId = false,
    ThemeProfileBrightness? brightness,
    bool? draft,
    ThemePalette? palette,
    ThemeTypography? typography,
    String? componentProfileId,
    ThemeMetadata? metadata,
  }) => ThemeProfile(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    id: id ?? this.id,
    name: name ?? this.name,
    source: source ?? this.source,
    basePresetId: clearBasePresetId
        ? null
        : (basePresetId ?? this.basePresetId),
    brightness: brightness ?? this.brightness,
    draft: draft ?? this.draft,
    palette: palette ?? this.palette,
    typography: typography ?? this.typography,
    componentProfileId: componentProfileId ?? this.componentProfileId,
    metadata: metadata ?? this.metadata,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeProfile &&
          schemaVersion == other.schemaVersion &&
          id == other.id &&
          name == other.name &&
          source == other.source &&
          basePresetId == other.basePresetId &&
          brightness == other.brightness &&
          draft == other.draft &&
          palette == other.palette &&
          typography == other.typography &&
          componentProfileId == other.componentProfileId &&
          metadata == other.metadata;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    name,
    source,
    basePresetId,
    brightness,
    draft,
    palette,
    typography,
    componentProfileId,
    metadata,
  );
}

@immutable
final class ThemeBasicSeeds {
  final Color background;
  final Color surface;
  final Color accent;
  final Color secondary;
  final Color textPrimary;

  const ThemeBasicSeeds({
    required this.background,
    required this.surface,
    required this.accent,
    required this.secondary,
    required this.textPrimary,
  });
}

@immutable
final class ThemeProfileWarning {
  final String code;
  final String field;
  final String message;

  const ThemeProfileWarning({
    required this.code,
    required this.field,
    required this.message,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeProfileWarning &&
          code == other.code &&
          field == other.field &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, field, message);
}
