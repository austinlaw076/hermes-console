import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/theme_profile.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';

import 'support/theme_profile_fixtures.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Matcher _codecError(String code) => isA<ThemeProfileCodecException>().having(
  (error) => error.code,
  'code',
  code,
);

void main() {
  group('ThemeProfileCodec canonical v1', () {
    test('round-trips every canonical field deterministically', () {
      final decoded = ThemeProfileCodec.decode(
        validThemeJson(),
        mode: ThemeProfileDecodeMode.persisted,
      );
      final encoded = ThemeProfileCodec.encode(decoded.profile);
      final roundTrip = ThemeProfileCodec.decode(
        encoded,
        mode: ThemeProfileDecodeMode.persisted,
      );

      expect(roundTrip.profile, decoded.profile);
      expect(encoded, ThemeProfileCodec.encode(roundTrip.profile));
      expect(jsonDecode(encoded), validThemeDocument());
    });

    test('normalizes lowercase #RRGGBB to uppercase #AARRGGBB', () {
      final document = validThemeDocument();
      final palette =
          (document['profile'] as Map<String, dynamic>)['palette']
              as Map<String, dynamic>;
      palette['background'] = '#0b0c0e';

      final result = ThemeProfileCodec.decode(
        jsonEncode(document),
        mode: ThemeProfileDecodeMode.persisted,
      );
      final exported = jsonDecode(ThemeProfileCodec.encode(result.profile));
      expect(exported['profile']['palette']['background'], '#FF0B0C0E');
    });

    test(
      'import rewrites custom source to imported without auto-activation',
      () {
        final result = ThemeProfileCodec.decode(validThemeJson());
        expect(result.profile.source, ThemeProfileSource.imported);
        expect(result.profile.draft, isFalse);
      },
    );

    test('builtin source is accepted only for the internal adapter mode', () {
      final document = validThemeDocument(source: 'builtin');
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(document)),
        throwsA(_codecError('builtin_import_forbidden')),
      );
      final internal = ThemeProfileCodec.decode(
        jsonEncode(document),
        mode: ThemeProfileDecodeMode.builtin,
      );
      expect(internal.profile.source, ThemeProfileSource.builtin);
    });

    test('counts combining sequences as graphemes for the name limit', () {
      final accepted = validThemeDocument(
        name: List.filled(48, 'e\u0301').join(),
      );
      expect(
        ThemeProfileCodec.decode(
          jsonEncode(accepted),
          mode: ThemeProfileDecodeMode.persisted,
        ).profile.name,
        isNotEmpty,
      );

      final rejected = validThemeDocument(
        name: List.filled(49, 'e\u0301').join(),
      );
      expect(
        () => ThemeProfileCodec.decode(
          jsonEncode(rejected),
          mode: ThemeProfileDecodeMode.persisted,
        ),
        throwsA(_codecError('invalid_name')),
      );
    });
  });

  group('ThemeProfileCodec validation and limits', () {
    test('rejects malformed roots, format and schema types', () {
      expect(
        () => ThemeProfileCodec.decode('[]'),
        throwsA(_codecError('invalid_root')),
      );
      final badFormat = validThemeDocument()..['format'] = 'other';
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(badFormat)),
        throwsA(_codecError('invalid_format')),
      );
      final badSchema = validThemeDocument()..['schema_version'] = 1.0;
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(badSchema)),
        throwsA(_codecError('invalid_schema')),
      );
    });

    test('preserves future schema as a distinct, non-corrupt condition', () {
      final document = validThemeDocument()..['schema_version'] = 2;
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(document)),
        throwsA(
          isA<UnsupportedThemeSchemaException>().having(
            (error) => error.schemaVersion,
            'schemaVersion',
            2,
          ),
        ),
      );
    });

    test('rejects all non-canonical color forms and non-string colors', () {
      for (final bad in <Object>[
        'red',
        'rgb(1,2,3)',
        'var(--accent)',
        '#12345',
        '#123456789',
        '#GG0000',
        -1,
      ]) {
        final document = validThemeDocument();
        final palette =
            (document['profile'] as Map<String, dynamic>)['palette']
                as Map<String, dynamic>;
        palette['accent'] = bad;
        expect(
          () => ThemeProfileCodec.decode(jsonEncode(document)),
          throwsA(
            bad is String
                ? _codecError('invalid_color')
                : _codecError('invalid_type'),
          ),
          reason: '$bad',
        );
      }
    });

    test('rejects fully transparent essential colors', () {
      final document = validThemeDocument();
      final palette =
          (document['profile'] as Map<String, dynamic>)['palette']
              as Map<String, dynamic>;
      palette['text_primary'] = '#00112233';
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(document)),
        throwsA(_codecError('transparent_essential_color')),
      );
    });

    test('rejects invalid field types and typography ranges', () {
      final draft = validThemeDocument();
      (draft['profile'] as Map<String, dynamic>)['draft'] = 'false';
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(draft)),
        throwsA(_codecError('invalid_draft')),
      );

      final weight = validThemeDocument();
      final typography =
          (weight['profile'] as Map<String, dynamic>)['typography']
              as Map<String, dynamic>;
      typography['title_weight'] = 900;
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(weight)),
        throwsA(_codecError('invalid_title_weight')),
      );

      final spacing = validThemeDocument();
      final spacingTypography =
          (spacing['profile'] as Map<String, dynamic>)['typography']
              as Map<String, dynamic>;
      spacingTypography['title_spacing'] = 3.01;
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(spacing)),
        throwsA(_codecError('invalid_title_spacing')),
      );
    });

    test('enforces bytes, UTF-8, nesting, map, array and string limits', () {
      final oversized =
          '${validThemeJson()}${List.filled(ThemeProfileCodec.maxBytes, ' ').join()}';
      expect(
        () => ThemeProfileCodec.decode(oversized),
        throwsA(_codecError('payload_too_large')),
      );
      expect(
        () => ThemeProfileCodec.decodeBytes(Uint8List.fromList([0xC3, 0x28])),
        throwsA(_codecError('invalid_utf8')),
      );

      final nested = validThemeDocument();
      Object value = 'leaf';
      for (var index = 0; index < 9; index++) {
        value = {'level': value};
      }
      nested['extra'] = value;
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(nested)),
        throwsA(_codecError('max_depth')),
      );

      final wide = validThemeDocument();
      wide['extra'] = {
        for (
          var index = 0;
          index < ThemeProfileCodec.maxMapEntries + 1;
          index++
        )
          'k$index': index,
      };
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(wide)),
        throwsA(_codecError('max_map_entries')),
      );

      final array = validThemeDocument();
      array['extra'] = List.filled(ThemeProfileCodec.maxArrayEntries + 1, 0);
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(array)),
        throwsA(_codecError('max_array_entries')),
      );

      final longString = validThemeDocument();
      longString['extra'] = List.filled(
        ThemeProfileCodec.maxStringLength + 1,
        'x',
      ).join();
      expect(
        () => ThemeProfileCodec.decode(jsonEncode(longString)),
        throwsA(_codecError('max_string_length')),
      );
    });

    test('rejects operational or secret-bearing keys, not ordinary values', () {
      for (final key in [
        'api_key',
        'authorization',
        'css_url',
        'cwd',
        'path',
      ]) {
        final document = validThemeDocument()..[key] = 'secret';
        expect(
          () => ThemeProfileCodec.decode(jsonEncode(document)),
          throwsA(_codecError('forbidden_field')),
          reason: key,
        );
      }

      final ordinaryText = validThemeDocument();
      final metadata =
          (ordinaryText['profile'] as Map<String, dynamic>)['metadata']
              as Map<String, dynamic>;
      metadata['description'] = 'A theme for host operators and path lovers';
      expect(
        ThemeProfileCodec.decode(
          jsonEncode(ordinaryText),
          mode: ThemeProfileDecodeMode.persisted,
        ).profile.metadata.description,
        contains('host'),
      );
    });
  });

  group('ThemeProfileCodec fallbacks and allowlists', () {
    test('migrates retired theme fonts to the OFL catalog', () {
      const expected = {
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

      for (final entry in expected.entries) {
        final result = ThemeProfileCodec.decode(
          jsonEncode(validThemeDocument(fontFamily: entry.key)),
          mode: ThemeProfileDecodeMode.persisted,
        );

        expect(
          result.profile.typography.fontFamily,
          entry.value,
          reason: entry.key,
        );
        expect(
          result.warnings.map((warning) => warning.code),
          contains('font_migrated'),
          reason: entry.key,
        );
      }
    });

    test('keeps Montserrat and Nunito as packaged OFL families', () {
      for (final family in ['Montserrat', 'Nunito']) {
        final result = ThemeProfileCodec.decode(
          jsonEncode(validThemeDocument(fontFamily: family)),
          mode: ThemeProfileDecodeMode.persisted,
        );

        expect(result.profile.typography.fontFamily, family);
        expect(
          result.warnings.map((warning) => warning.code),
          isNot(contains('font_migrated')),
        );
      }
    });

    test(
      'falls back unknown packaged fonts and component profile with warnings',
      () {
        final document = validThemeDocument(
          fontFamily: 'FutureFont',
          codeFontFamily: 'FutureMono',
          componentProfileId: 'future-components',
        );
        final result = ThemeProfileCodec.decode(
          jsonEncode(document),
          mode: ThemeProfileDecodeMode.persisted,
        );

        expect(result.profile.typography.fontFamily, 'Inter');
        expect(result.profile.typography.codeFontFamily, 'monospace');
        expect(result.profile.componentProfileId, 'minimal');
        expect(
          result.warnings.map((warning) => warning.code),
          containsAll([
            'font_fallback',
            'code_font_fallback',
            'component_profile_fallback',
          ]),
        );
      },
    );

    test('ignores unknown safe metadata and never re-exports it', () {
      final document = validThemeDocument();
      final metadata =
          (document['profile'] as Map<String, dynamic>)['metadata']
              as Map<String, dynamic>;
      metadata['future_scalar'] = 'safe';
      final profile = ThemeProfileCodec.decode(
        jsonEncode(document),
        mode: ThemeProfileDecodeMode.persisted,
      ).profile;
      final exported = ThemeProfileCodec.encode(profile);
      expect(exported, isNot(contains('future_scalar')));
    });

    test('builtins require an explicit custom copy before normal export', () {
      final document = _copy(validThemeDocument(source: 'builtin'));
      final profile = ThemeProfileCodec.decode(
        jsonEncode(document),
        mode: ThemeProfileDecodeMode.builtin,
      ).profile;
      expect(
        () => ThemeProfileCodec.encode(profile),
        throwsA(_codecError('builtin_export_requires_copy')),
      );
      expect(
        ThemeProfileCodec.encode(profile, allowBuiltin: true),
        contains('"source":"builtin"'),
      );
    });
  });
}
