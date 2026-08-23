import 'dart:convert';

import 'package:hermes_android/core/theme/theme_profile.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';

Map<String, dynamic> validThemeDocument({
  String id = 'b3be2e40-9fe6-4fc1-9fb5-9eb18844df76',
  String name = 'Mi terminal ambar',
  String source = 'custom',
  bool draft = false,
  String componentProfileId = 'minimal',
  String fontFamily = 'Inter',
  String codeFontFamily = 'JetBrainsMono',
}) => {
  'format': 'hermes-console-theme',
  'schema_version': 1,
  'profile': {
    'id': id,
    'name': name,
    'source': source,
    'base_preset_id': 'amber',
    'brightness': 'dark',
    'draft': draft,
    'palette': <String, dynamic>{
      'background': '#FF0B0C0E',
      'surface': '#FF15171A',
      'surface_variant': '#FF22252A',
      'accent': '#FFE8821C',
      'accent_hover': '#FFF4A043',
      'accent_text': '#FFF4A043',
      'secondary': '#FF4FB8C9',
      'on_accent': '#FF111111',
      'text_primary': '#FFF3F3F3',
      'text_secondary': '#FFB6B8BC',
      'text_disabled': '#FF74777D',
      'error': '#FFFF6B6B',
      'success': '#FF4BCB78',
      'warning': '#FFFFBE55',
      'divider': '#FF3B3E44',
    },
    'typography': <String, dynamic>{
      'font_family': fontFamily,
      'code_font_family': codeFontFamily,
      'title_weight': 700,
      'title_spacing': 0.5,
      'uppercase_titles': false,
    },
    'component_profile_id': componentProfileId,
    'metadata': <String, dynamic>{
      'created_with': 'Hermes Console',
      'created_with_schema': 1,
      'derivation_version': 1,
      'description': 'Local theme fixture',
    },
  },
};

String validThemeJson({
  String id = 'b3be2e40-9fe6-4fc1-9fb5-9eb18844df76',
  String name = 'Mi terminal ambar',
  String source = 'custom',
  bool draft = false,
}) => jsonEncode(
  validThemeDocument(id: id, name: name, source: source, draft: draft),
);

ThemeProfile validCustomTheme({
  String id = 'b3be2e40-9fe6-4fc1-9fb5-9eb18844df76',
  String name = 'Mi terminal ambar',
  bool draft = false,
}) => ThemeProfileCodec.decode(
  validThemeJson(id: id, name: name, draft: draft),
  mode: ThemeProfileDecodeMode.persisted,
).profile;
