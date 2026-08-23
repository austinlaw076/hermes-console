import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'component_profile.dart';
import 'theme_profile.dart';

enum ThemeProfileDecodeMode { import, persisted, builtin }

final class ThemeProfileCodecException implements Exception {
  final String code;
  final String field;
  final String message;

  const ThemeProfileCodecException(this.code, this.message, {this.field = ''});

  @override
  String toString() => 'ThemeProfileCodecException($code, $field): $message';
}

final class UnsupportedThemeSchemaException extends ThemeProfileCodecException {
  final int schemaVersion;

  const UnsupportedThemeSchemaException(this.schemaVersion)
    : super(
        'future_schema',
        'Theme schema $schemaVersion is newer than this app supports',
        field: 'schema_version',
      );
}

final class ThemeProfileDecodeResult {
  final ThemeProfile profile;
  final List<ThemeProfileWarning> warnings;

  const ThemeProfileDecodeResult({
    required this.profile,
    this.warnings = const [],
  });
}

/// Defensive codec for the `hermes-console-theme` JSON v1 contract.
abstract final class ThemeProfileCodec {
  static const String format = 'hermes-console-theme';
  static const int maxBytes = 64 * 1024;
  static const int maxDepth = 8;
  static const int maxMapEntries = 64;
  static const int maxArrayEntries = 32;
  static const int maxStringLength = 256;

  static const Set<String> packagedFontFamilies = {
    'Inter',
    'Montserrat',
    'Nunito',
    'JetBrainsMono',
  };

  /// Profiles saved by earlier Theme Studio catalogs remain readable while
  /// resolving every retired family to a bundled OFL equivalent.
  static const Map<String, String> _legacyFontFamilies = {
    'Satoshi': 'Inter',
    'GeneralSans': 'Inter',
    'Switzer': 'Inter',
    'Supreme': 'Montserrat',
    'CabinetGrotesk': 'Montserrat',
    'ClashGrotesk': 'Montserrat',
    'Chillax': 'Nunito',
    'Sentient': 'Montserrat',
    'Zodiak': 'Montserrat',
    'Manrope': 'Inter',
    'Outfit': 'Inter',
    'PlusJakartaSans': 'Inter',
    'PublicSans': 'Inter',
    'Sora': 'Inter',
    'SpaceGrotesk': 'Inter',
  };

  static const Set<String> packagedCodeFontFamilies = {
    'JetBrainsMono',
    'monospace',
  };

  static const Set<String> _forbiddenKeys = {
    'token',
    'api_key',
    'authorization',
    'cookie',
    'connection',
    'connection_id',
    'session',
    'session_id',
    'prompt',
    'transcript',
    'host',
    'cwd',
    'path',
    'url',
    'css_url',
    'device_id',
    'username',
    'author_email',
  };

  static ThemeProfileDecodeResult decodeBytes(
    Uint8List bytes, {
    ThemeProfileDecodeMode mode = ThemeProfileDecodeMode.import,
  }) {
    if (bytes.length > maxBytes) {
      throw const ThemeProfileCodecException(
        'payload_too_large',
        'Theme payload exceeds 64 KiB',
      );
    }
    late final String raw;
    try {
      raw = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const ThemeProfileCodecException(
        'invalid_utf8',
        'Theme payload is not valid UTF-8',
      );
    }
    return decode(raw, mode: mode);
  }

  static ThemeProfileDecodeResult decode(
    String raw, {
    ThemeProfileDecodeMode mode = ThemeProfileDecodeMode.import,
  }) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const ThemeProfileCodecException(
        'payload_too_large',
        'Theme payload exceeds 64 KiB',
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ThemeProfileCodecException(
        'invalid_json',
        'Theme payload is not valid JSON',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ThemeProfileCodecException(
        'invalid_root',
        'Theme payload must contain one JSON object',
      );
    }
    _validateStructure(decoded, depth: 1, path: r'$');
    _rejectForbiddenKeys(decoded, path: r'$');

    if (decoded['format'] != format) {
      throw const ThemeProfileCodecException(
        'invalid_format',
        'Unknown theme document format',
        field: 'format',
      );
    }
    final schema = decoded['schema_version'];
    if (schema is! int) {
      throw const ThemeProfileCodecException(
        'invalid_schema',
        'schema_version must be an integer',
        field: 'schema_version',
      );
    }
    if (schema > themeProfileSchemaVersion) {
      throw UnsupportedThemeSchemaException(schema);
    }
    if (schema != themeProfileSchemaVersion) {
      throw ThemeProfileCodecException(
        'unsupported_schema',
        'Theme schema $schema is not supported',
        field: 'schema_version',
      );
    }

    final profileMap = _requiredMap(decoded, 'profile', r'$');
    final warnings = <ThemeProfileWarning>[];

    final id = _requiredString(profileMap, 'id', 'profile');
    if (!_isSafeId(id)) {
      throw const ThemeProfileCodecException(
        'invalid_id',
        'Theme id must be a safe local identifier',
        field: 'profile.id',
      );
    }

    final name = _requiredString(profileMap, 'name', 'profile').trim();
    if (name.isEmpty ||
        _graphemeLength(name) > 48 ||
        _containsControlCharacter(name)) {
      throw const ThemeProfileCodecException(
        'invalid_name',
        'Theme name must contain 1 to 48 grapheme clusters',
        field: 'profile.name',
      );
    }

    final source = _parseSource(
      _requiredString(profileMap, 'source', 'profile'),
      mode,
    );
    final basePresetId = _optionalString(
      profileMap,
      'base_preset_id',
      'profile',
    );
    if (basePresetId != null && !_isSafeId(basePresetId)) {
      throw const ThemeProfileCodecException(
        'invalid_base_preset',
        'base_preset_id must be a safe local identifier',
        field: 'profile.base_preset_id',
      );
    }

    final brightness = switch (_requiredString(
      profileMap,
      'brightness',
      'profile',
    )) {
      'dark' => ThemeProfileBrightness.dark,
      'light' => ThemeProfileBrightness.light,
      _ => throw const ThemeProfileCodecException(
        'invalid_brightness',
        'brightness must be dark or light',
        field: 'profile.brightness',
      ),
    };
    final draft = profileMap['draft'];
    if (draft is! bool) {
      throw const ThemeProfileCodecException(
        'invalid_draft',
        'draft must be a boolean',
        field: 'profile.draft',
      );
    }

    final paletteMap = _requiredMap(profileMap, 'palette', 'profile');
    Color color(String key) => _parseColor(
      _requiredString(paletteMap, key, 'profile.palette'),
      'profile.palette.$key',
    );
    final palette = ThemePalette(
      background: color('background'),
      surface: color('surface'),
      surfaceVariant: color('surface_variant'),
      accent: color('accent'),
      accentHover: color('accent_hover'),
      accentText: color('accent_text'),
      secondary: color('secondary'),
      onAccent: color('on_accent'),
      textPrimary: color('text_primary'),
      textSecondary: color('text_secondary'),
      textDisabled: color('text_disabled'),
      error: color('error'),
      success: color('success'),
      warning: color('warning'),
      divider: color('divider'),
    );

    final typographyMap = _requiredMap(profileMap, 'typography', 'profile');
    var fontFamily = _requiredString(
      typographyMap,
      'font_family',
      'profile.typography',
    );
    final migratedFont = _legacyFontFamilies[fontFamily];
    if (migratedFont != null) {
      warnings.add(
        ThemeProfileWarning(
          code: 'font_migrated',
          field: 'profile.typography.font_family',
          message: '$fontFamily was replaced by $migratedFont',
        ),
      );
      fontFamily = migratedFont;
    } else if (!packagedFontFamilies.contains(fontFamily)) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'font_fallback',
          field: 'profile.typography.font_family',
          message: 'Font is not packaged; Inter will be used',
        ),
      );
      fontFamily = 'Inter';
    }
    var codeFontFamily = _requiredString(
      typographyMap,
      'code_font_family',
      'profile.typography',
    );
    if (!packagedCodeFontFamilies.contains(codeFontFamily)) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'code_font_fallback',
          field: 'profile.typography.code_font_family',
          message: 'Code font is not packaged; monospace will be used',
        ),
      );
      codeFontFamily = 'monospace';
    }
    final titleWeight = typographyMap['title_weight'];
    if (titleWeight is! int ||
        !const {400, 500, 600, 700, 800}.contains(titleWeight)) {
      throw const ThemeProfileCodecException(
        'invalid_title_weight',
        'title_weight must be one of 400, 500, 600, 700 or 800',
        field: 'profile.typography.title_weight',
      );
    }
    final titleSpacingRaw = typographyMap['title_spacing'];
    if (titleSpacingRaw is! num ||
        !titleSpacingRaw.isFinite ||
        titleSpacingRaw < -0.5 ||
        titleSpacingRaw > 3) {
      throw const ThemeProfileCodecException(
        'invalid_title_spacing',
        'title_spacing must be finite and between -0.5 and 3.0',
        field: 'profile.typography.title_spacing',
      );
    }
    final uppercaseTitles = typographyMap['uppercase_titles'];
    if (uppercaseTitles is! bool) {
      throw const ThemeProfileCodecException(
        'invalid_uppercase_titles',
        'uppercase_titles must be a boolean',
        field: 'profile.typography.uppercase_titles',
      );
    }
    final typography = ThemeTypography(
      fontFamily: fontFamily,
      codeFontFamily: codeFontFamily,
      titleWeight: titleWeight,
      titleSpacing: titleSpacingRaw.toDouble(),
      uppercaseTitles: uppercaseTitles,
    );

    var componentProfileId = _requiredString(
      profileMap,
      'component_profile_id',
      'profile',
    );
    if (!ComponentProfiles.ids.contains(componentProfileId)) {
      warnings.add(
        const ThemeProfileWarning(
          code: 'component_profile_fallback',
          field: 'profile.component_profile_id',
          message: 'Unknown component profile; minimal will be used',
        ),
      );
      componentProfileId = ComponentProfiles.minimal.id;
    }

    final metadataMap = _requiredMap(profileMap, 'metadata', 'profile');
    final createdWith = _boundedMetadataString(
      metadataMap,
      'created_with',
      fallback: 'Hermes Console',
      maxLength: 48,
    );
    final createdWithSchema = _positiveMetadataInt(
      metadataMap,
      'created_with_schema',
      fallback: themeProfileSchemaVersion,
    );
    final derivationVersion = _positiveMetadataInt(
      metadataMap,
      'derivation_version',
      fallback: 1,
    );
    final description = _boundedMetadataString(
      metadataMap,
      'description',
      maxLength: 160,
      nullable: true,
    );

    return ThemeProfileDecodeResult(
      profile: ThemeProfile(
        id: id,
        name: name,
        source: source,
        basePresetId: basePresetId,
        brightness: brightness,
        draft: draft,
        palette: palette,
        typography: typography,
        componentProfileId: componentProfileId,
        metadata: ThemeMetadata(
          createdWith: createdWith!,
          createdWithSchema: createdWithSchema,
          derivationVersion: derivationVersion,
          description: description,
        ),
      ),
      warnings: List.unmodifiable(warnings),
    );
  }

  static String encode(ThemeProfile profile, {bool allowBuiltin = false}) {
    if (profile.schemaVersion != themeProfileSchemaVersion) {
      throw ThemeProfileCodecException(
        'unsupported_schema',
        'Cannot export theme schema ${profile.schemaVersion}',
        field: 'schema_version',
      );
    }
    if (profile.isBuiltin && !allowBuiltin) {
      throw const ThemeProfileCodecException(
        'builtin_export_requires_copy',
        'Duplicate a built-in theme before exporting it',
        field: 'profile.source',
      );
    }
    final document = toDocument(profile);
    _assertExportAllowlist(document);
    final encoded = jsonEncode(document);
    if (utf8.encode(encoded).length > maxBytes) {
      throw const ThemeProfileCodecException(
        'payload_too_large',
        'Theme payload exceeds 64 KiB',
      );
    }
    return encoded;
  }

  static Map<String, dynamic> toDocument(ThemeProfile profile) => {
    'format': format,
    'schema_version': themeProfileSchemaVersion,
    'profile': toProfileMap(profile),
  };

  static Map<String, dynamic> toProfileMap(ThemeProfile profile) => {
    'id': profile.id,
    'name': profile.name,
    'source': profile.source.name,
    if (profile.basePresetId != null) 'base_preset_id': profile.basePresetId,
    'brightness': profile.brightness.name,
    'draft': profile.draft,
    'palette': {
      'background': colorToCanonical(profile.palette.background),
      'surface': colorToCanonical(profile.palette.surface),
      'surface_variant': colorToCanonical(profile.palette.surfaceVariant),
      'accent': colorToCanonical(profile.palette.accent),
      'accent_hover': colorToCanonical(profile.palette.accentHover),
      'accent_text': colorToCanonical(profile.palette.accentText),
      'secondary': colorToCanonical(profile.palette.secondary),
      'on_accent': colorToCanonical(profile.palette.onAccent),
      'text_primary': colorToCanonical(profile.palette.textPrimary),
      'text_secondary': colorToCanonical(profile.palette.textSecondary),
      'text_disabled': colorToCanonical(profile.palette.textDisabled),
      'error': colorToCanonical(profile.palette.error),
      'success': colorToCanonical(profile.palette.success),
      'warning': colorToCanonical(profile.palette.warning),
      'divider': colorToCanonical(profile.palette.divider),
    },
    'typography': {
      'font_family': profile.typography.fontFamily,
      'code_font_family': profile.typography.codeFontFamily,
      'title_weight': profile.typography.titleWeight,
      'title_spacing': profile.typography.titleSpacing,
      'uppercase_titles': profile.typography.uppercaseTitles,
    },
    'component_profile_id': profile.componentProfileId,
    'metadata': {
      'created_with': profile.metadata.createdWith,
      'created_with_schema': profile.metadata.createdWithSchema,
      'derivation_version': profile.metadata.derivationVersion,
      if (profile.metadata.description != null)
        'description': profile.metadata.description,
    },
  };

  static String colorToCanonical(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static void _validateStructure(
    Object? value, {
    required int depth,
    required String path,
  }) {
    if (depth > maxDepth) {
      throw ThemeProfileCodecException(
        'max_depth',
        'Theme JSON nesting exceeds $maxDepth',
        field: path,
      );
    }
    if (value is Map) {
      if (value.length > maxMapEntries) {
        throw ThemeProfileCodecException(
          'max_map_entries',
          'Theme object contains too many fields',
          field: path,
        );
      }
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ThemeProfileCodecException(
            'invalid_key',
            'Theme object keys must be strings',
            field: path,
          );
        }
        _validateStructure(
          entry.value,
          depth: depth + 1,
          path: '$path.${entry.key}',
        );
      }
      return;
    }
    if (value is List) {
      if (value.length > maxArrayEntries) {
        throw ThemeProfileCodecException(
          'max_array_entries',
          'Theme array contains too many entries',
          field: path,
        );
      }
      for (var index = 0; index < value.length; index++) {
        _validateStructure(
          value[index],
          depth: depth + 1,
          path: '$path[$index]',
        );
      }
      return;
    }
    if (value is String && value.runes.length > maxStringLength) {
      throw ThemeProfileCodecException(
        'max_string_length',
        'Theme string exceeds $maxStringLength characters',
        field: path,
      );
    }
    if (value is double && !value.isFinite) {
      throw ThemeProfileCodecException(
        'non_finite_number',
        'Theme numbers must be finite',
        field: path,
      );
    }
  }

  static void _rejectForbiddenKeys(Object? value, {required String path}) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (_forbiddenKeys.contains(key) || key.endsWith('_url')) {
          throw ThemeProfileCodecException(
            'forbidden_field',
            'Theme payload contains a forbidden field',
            field: '$path.$key',
          );
        }
        _rejectForbiddenKeys(entry.value, path: '$path.$key');
      }
    } else if (value is List) {
      for (var index = 0; index < value.length; index++) {
        _rejectForbiddenKeys(value[index], path: '$path[$index]');
      }
    }
  }

  static void _assertExportAllowlist(Map<String, dynamic> document) {
    // Export is constructed from a strict allowlist. Keep a final assertion so
    // future schema edits cannot accidentally add operational or secret keys.
    void visit(Object? value, String path) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase();
          if (_forbiddenKeys.contains(key) || key.endsWith('_url')) {
            throw ThemeProfileCodecException(
              'unsafe_export',
              'Theme export contains a forbidden field',
              field: '$path.$key',
            );
          }
          visit(entry.value, '$path.$key');
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index++) {
          visit(value[index], '$path[$index]');
        }
      }
    }

    visit(document, r'$');
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value is! Map<String, dynamic>) {
      throw ThemeProfileCodecException(
        'invalid_type',
        '$key must be an object',
        field: '$path.$key',
      );
    }
    return value;
  }

  static String _requiredString(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value is! String) {
      throw ThemeProfileCodecException(
        'invalid_type',
        '$key must be a string',
        field: '$path.$key',
      );
    }
    return value;
  }

  static String? _optionalString(
    Map<String, dynamic> parent,
    String key,
    String path,
  ) {
    final value = parent[key];
    if (value == null) return null;
    if (value is! String) {
      throw ThemeProfileCodecException(
        'invalid_type',
        '$key must be a string or null',
        field: '$path.$key',
      );
    }
    return value;
  }

  static ThemeProfileSource _parseSource(
    String raw,
    ThemeProfileDecodeMode mode,
  ) {
    final parsed = switch (raw) {
      'builtin' => ThemeProfileSource.builtin,
      'custom' => ThemeProfileSource.custom,
      'imported' => ThemeProfileSource.imported,
      _ => throw const ThemeProfileCodecException(
        'invalid_source',
        'Unknown theme source',
        field: 'profile.source',
      ),
    };
    if (mode != ThemeProfileDecodeMode.builtin &&
        parsed == ThemeProfileSource.builtin) {
      throw const ThemeProfileCodecException(
        'builtin_import_forbidden',
        'An imported theme cannot claim built-in status',
        field: 'profile.source',
      );
    }
    if (mode == ThemeProfileDecodeMode.import) {
      return ThemeProfileSource.imported;
    }
    return parsed;
  }

  static Color _parseColor(String raw, String field) {
    final match = RegExp(r'^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');
    if (!match.hasMatch(raw)) {
      throw ThemeProfileCodecException(
        'invalid_color',
        'Color must be #RRGGBB or #AARRGGBB',
        field: field,
      );
    }
    final canonical = raw.length == 7 ? '#FF${raw.substring(1)}' : raw;
    final value = int.parse(canonical.substring(1), radix: 16);
    if ((value >> 24) == 0) {
      throw ThemeProfileCodecException(
        'transparent_essential_color',
        'Palette colors cannot be fully transparent',
        field: field,
      );
    }
    return Color(value);
  }

  static String? _boundedMetadataString(
    Map<String, dynamic> metadata,
    String key, {
    required int maxLength,
    String? fallback,
    bool nullable = false,
  }) {
    final value = metadata[key];
    if (value == null) return nullable ? null : fallback;
    if (value is! String || value.runes.length > maxLength) {
      throw ThemeProfileCodecException(
        'invalid_metadata',
        '$key must be a string no longer than $maxLength characters',
        field: 'profile.metadata.$key',
      );
    }
    return value;
  }

  static int _positiveMetadataInt(
    Map<String, dynamic> metadata,
    String key, {
    required int fallback,
  }) {
    final value = metadata[key];
    if (value == null) return fallback;
    if (value is! int || value < 1) {
      throw ThemeProfileCodecException(
        'invalid_metadata',
        '$key must be a positive integer',
        field: 'profile.metadata.$key',
      );
    }
    return value;
  }

  static bool _isSafeId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value);

  static bool _containsControlCharacter(String value) =>
      value.runes.any((rune) => rune < 0x20 || (rune >= 0x7F && rune <= 0x9F));

  /// Small, dependency-free grapheme counter covering combining marks, emoji
  /// modifiers, regional-indicator flags and ZWJ emoji sequences.
  static int _graphemeLength(String value) {
    var count = 0;
    var previousWasJoiner = false;
    var regionalRun = 0;
    for (final rune in value.runes) {
      if (rune == 0x200D) {
        previousWasJoiner = true;
        continue;
      }
      final regional = rune >= 0x1F1E6 && rune <= 0x1F1FF;
      if (_isGraphemeExtender(rune) || previousWasJoiner) {
        previousWasJoiner = false;
        if (!regional) regionalRun = 0;
        continue;
      }
      previousWasJoiner = false;
      if (regional) {
        if (regionalRun.isEven) count++;
        regionalRun++;
      } else {
        regionalRun = 0;
        count++;
      }
    }
    return count;
  }

  static bool _isGraphemeExtender(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x1AB0 && rune <= 0x1AFF) ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x20D0 && rune <= 0x20FF) ||
      (rune >= 0xFE00 && rune <= 0xFE0F) ||
      (rune >= 0xFE20 && rune <= 0xFE2F) ||
      (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
      (rune >= 0xE0100 && rune <= 0xE01EF) ||
      (rune >= 0xE0020 && rune <= 0xE007F);
}
