import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/theme_profile.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';

import 'support/theme_profile_fixtures.dart';

void main() {
  group('ThemeProfile export contract', () {
    test('exports one canonical local document that round-trips exactly', () {
      final profile = validCustomTheme();

      final raw = ThemeProfileCodec.encode(profile);
      final decoded = ThemeProfileCodec.decode(
        raw,
        mode: ThemeProfileDecodeMode.persisted,
      );

      expect(decoded.profile, profile);
      expect(jsonDecode(raw), ThemeProfileCodec.toDocument(profile));
      expect(utf8.encode(raw).length, lessThanOrEqualTo(64 * 1024));
    });

    test('exports only the v1 key allowlist and no operational state', () {
      final profile = validCustomTheme().copyWith(
        metadata: const ThemeMetadata(
          description: 'For host operators, session themes and path lovers',
        ),
      );
      final document = jsonDecode(ThemeProfileCodec.encode(profile));
      final keys = <String>[];

      void collectKeys(Object? value) {
        if (value is Map) {
          for (final entry in value.entries) {
            keys.add(entry.key.toString().toLowerCase());
            collectKeys(entry.value);
          }
        } else if (value is List) {
          for (final item in value) {
            collectKeys(item);
          }
        }
      }

      collectKeys(document);
      expect(
        keys,
        isNot(
          containsAll(<String>[
            'token',
            'api_key',
            'authorization',
            'cookie',
            'connection',
            'session',
            'prompt',
            'transcript',
            'host',
            'cwd',
            'path',
          ]),
        ),
      );
      for (final forbidden in const {
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
      }) {
        expect(keys, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(
        (document['profile']
            as Map<String, dynamic>)['metadata']['description'],
        contains('host'),
      );
    });

    test('an imported secret-bearing key is rejected before re-export', () {
      final document = validThemeDocument();
      final profile = document['profile'] as Map<String, dynamic>;
      final metadata = profile['metadata'] as Map<String, dynamic>;
      metadata['api_key'] = 'must-not-survive';

      expect(
        () => ThemeProfileCodec.decode(jsonEncode(document)),
        throwsA(
          isA<ThemeProfileCodecException>().having(
            (error) => error.code,
            'code',
            'forbidden_field',
          ),
        ),
      );
    });
  });
}
