import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_manifest_parser.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';

const _validJson = '''
{
  "slug": "boba",
  "name": "Boba",
  "author": "team",
  "license": "CC-BY-4.0",
  "spritesheet": "spritesheet.webp",
  "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
  "fps": 6,
  "states": {
    "idle":    { "row": 0, "frameCount": 8, "loop": true },
    "run":     { "row": 1, "frameCount": 8, "loop": true },
    "waiting": { "row": 2, "frameCount": 8, "loop": true },
    "wave":    { "row": 3, "frameCount": 8, "loop": false },
    "failed":  { "row": 4, "frameCount": 8, "loop": false }
  }
}
''';

void main() {
  group('CompanionManifestParser', () {
    test('parsea un pet.json válido', () {
      final c = CompanionManifestParser.parse(
        _validJson,
        assetDir: 'assets/companions/boba',
        slug: 'boba',
      );
      expect(c.slug, 'boba');
      expect(c.name, 'Boba');
      expect(c.fps, 6);
      expect(c.spritesheetAsset, 'assets/companions/boba/spritesheet.webp');
      expect(c.states.containsKey(CompanionAnimationState.idle), isTrue);
      expect(c.states[CompanionAnimationState.wave]!.loop, isFalse);
      expect(c.isValid, isTrue);
    });

    test('parsea filas EXTRA con nombre (name/label) y sin nombre', () {
      const json = '''
      {
        "slug": "boba", "spritesheet": "s.webp",
        "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
        "fps": 6,
        "states": { "idle": { "row": 0, "frameCount": 8 } },
        "extraRows": [
          { "row": 5, "frameCount": 6, "name": "Bailar" },
          { "row": 6, "frameCount": 8 },
          { "row": 7, "frameCount": 4, "label": "Dormir" }
        ]
      }
      ''';
      final c = CompanionManifestParser.parse(
        json,
        assetDir: 'assets/companions/boba',
        slug: 'boba',
      );
      expect(c.extraRows.length, 3);
      expect(c.extraRows[0].label, 'Bailar');
      expect(c.extraRows[0].frameCount, 6);
      expect(c.extraRows[1].label, isNull); // sin metadata → null → "Extra N"
      expect(c.extraRows[2].label, 'Dormir');
    });

    test('ignora estados desconocidos de forma tolerante', () {
      const json = '''
      {
        "slug": "boba", "spritesheet": "s.webp",
        "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
        "fps": 6,
        "states": { "idle": { "row": 0, "frameCount": 8 }, "bogus": { "row": 1, "frameCount": 8 } }
      }
      ''';
      final c = CompanionManifestParser.parse(
        json,
        assetDir: 'assets/companions/boba',
        slug: 'boba',
      );
      expect(c.states.length, 1);
      expect(c.states.containsKey(CompanionAnimationState.idle), isTrue);
    });

    test('falla si falta el estado idle', () {
      const json = '''
      {
        "slug": "boba", "spritesheet": "s.webp",
        "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
        "fps": 6,
        "states": { "run": { "row": 1, "frameCount": 8 } }
      }
      ''';
      expect(
        () => CompanionManifestParser.parse(
          json,
          assetDir: 'assets/companions/boba',
          slug: 'boba',
        ),
        throwsA(isA<CompanionManifestException>()),
      );
    });

    test('falla si fps <= 0', () {
      const json = '''
      {
        "slug": "boba", "spritesheet": "s.webp",
        "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
        "fps": 0,
        "states": { "idle": { "row": 0, "frameCount": 8 } }
      }
      ''';
      expect(
        () => CompanionManifestParser.parse(
          json,
          assetDir: 'assets/companions/boba',
          slug: 'boba',
        ),
        throwsA(isA<CompanionManifestException>()),
      );
    });

    test('falla si row está fuera de rango', () {
      const json = '''
      {
        "slug": "boba", "spritesheet": "s.webp",
        "grid": { "frameWidth": 192, "frameHeight": 208, "cols": 8, "rows": 9 },
        "fps": 6,
        "states": { "idle": { "row": 99, "frameCount": 8 } }
      }
      ''';
      expect(
        () => CompanionManifestParser.parse(
          json,
          assetDir: 'assets/companions/boba',
          slug: 'boba',
        ),
        throwsA(isA<CompanionManifestException>()),
      );
    });

    test('falla si el slug no coincide con la carpeta', () {
      expect(
        () => CompanionManifestParser.parse(
          _validJson,
          assetDir: 'assets/companions/otro',
          slug: 'otro',
        ),
        throwsA(isA<CompanionManifestException>()),
      );
    });

    test('falla con JSON malformado', () {
      expect(
        () => CompanionManifestParser.parse(
          '{ no es json',
          assetDir: 'assets/companions/boba',
          slug: 'boba',
        ),
        throwsA(isA<CompanionManifestException>()),
      );
    });
  });
}
