import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/generated_artifact.dart';
import 'package:hermes_android/core/services/generated_artifact_registry.dart';

void main() {
  const html = GeneratedArtifactDetection(
    kind: GeneratedArtifactKind.html,
    language: 'html',
    title: 'Panel',
  );

  test('registra, deduplica y versiona por sesión + slug', () {
    var tick = 0;
    final registry = GeneratedArtifactRegistry(
      clock: () => DateTime.fromMillisecondsSinceEpoch(++tick),
    );

    final first = registry.upsert('session-1', html, '<html>v1</html>')!;
    final replay = registry.upsert('session-1', html, ' <html>v1</html> ')!;
    final second = registry.upsert('session-1', html, '<html>v2</html>')!;

    expect(first.versionAdded, isTrue);
    expect(replay.versionAdded, isFalse);
    expect(second.artifactId, first.artifactId);
    expect(second.record.versions, hasLength(2));
    expect(second.record.versions.last.content, '<html>v2</html>');
    expect(second.record.versions.first.sha256, hasLength(64));
    expect(registry.artifactsForSession('session-1'), hasLength(1));
    expect(registry.artifactsForSession('session-2'), isEmpty);
    expect(
      () => second.record.versions.add(second.record.versions.last),
      throwsUnsupportedError,
    );
  });

  test('rechaza sesión o contenido vacío sin mutar estado', () {
    final registry = GeneratedArtifactRegistry();

    expect(registry.upsert('', html, '<html>x</html>'), isNull);
    expect(registry.upsert('session', html, '   '), isNull);
    expect(registry.sessionCount, 0);
  });

  test('rechaza una versión sobredimensionada sin truncarla ni mutar', () {
    final registry = GeneratedArtifactRegistry(
      maxCharactersPerVersion: 20,
      maxRetainedCharacters: 60,
    );
    var notifications = 0;
    registry.addListener(() => notifications++);

    expect(registry.upsert('session', html, 'x'.padRight(21, 'x')), isNull);
    registry.replaceSession('session', [
      GeneratedArtifactInput(detection: html, content: 'y'.padRight(21, 'y')),
    ]);

    expect(registry.sessionCount, 0);
    expect(registry.retainedCharacterCount, 0);
    expect(notifications, 0);

    final exact = 'z'.padRight(20, 'z');
    final accepted = registry.upsert('session', html, exact)!;
    expect(accepted.record.versions.single.content, exact);
    expect(registry.retainedCharacterCount, 20);
  });

  test('presupuesto global poda historia y luego artifacts más antiguos', () {
    var tick = 0;
    final registry = GeneratedArtifactRegistry(
      clock: () => DateTime.fromMillisecondsSinceEpoch(++tick),
      maxCharactersPerVersion: 20,
      maxRetainedCharacters: 40,
    );
    GeneratedArtifactDetection detection(String title) =>
        GeneratedArtifactDetection(
          kind: GeneratedArtifactKind.code,
          language: 'dart',
          title: title,
        );
    String payload(String marker) => marker.padRight(20, marker);

    final first = registry.upsert(
      'session',
      detection('A.dart'),
      payload('a'),
    )!;
    registry.upsert('session', detection('A.dart'), payload('b'));
    final second = registry.upsert(
      'session',
      detection('B.dart'),
      payload('c'),
    )!;

    expect(registry.retainedCharacterCount, 40);
    expect(registry.getArtifact(first.artifactId)?.versions, hasLength(1));
    expect(
      registry.getArtifact(first.artifactId)?.versions.single.content,
      payload('b'),
    );
    final replay = registry.upsert(
      'session',
      detection('B.dart'),
      payload('c'),
    )!;
    expect(replay.versionAdded, isFalse);
    expect(registry.retainedCharacterCount, 40);

    final third = registry.upsert(
      'session',
      detection('C.dart'),
      payload('d'),
    )!;

    expect(registry.retainedCharacterCount, 40);
    expect(registry.getArtifact(first.artifactId), isNull);
    expect(registry.getArtifact(second.artifactId), isNotNull);
    expect(registry.getArtifact(third.artifactId), isNotNull);
    expect(
      registry.artifactsForSession('session').map((record) => record.title),
      ['B.dart', 'C.dart'],
    );
  });

  test('acota versiones, artifacts y sesiones como Desktop', () {
    var tick = 0;
    final registry = GeneratedArtifactRegistry(
      clock: () => DateTime.fromMillisecondsSinceEpoch(++tick),
    );

    for (var version = 0; version < 25; version++) {
      registry.upsert('session-main', html, '<html>v$version</html>');
    }
    expect(
      registry.artifactsForSession('session-main').single.versions,
      hasLength(20),
    );
    expect(
      registry
          .artifactsForSession('session-main')
          .single
          .versions
          .first
          .content,
      '<html>v5</html>',
    );

    for (var artifact = 0; artifact < 30; artifact++) {
      registry.upsert(
        'session-artifacts',
        GeneratedArtifactDetection(
          kind: GeneratedArtifactKind.code,
          language: 'dart',
          title: 'File $artifact',
        ),
        'void main$artifact() {}',
      );
    }
    expect(registry.artifactsForSession('session-artifacts'), hasLength(24));
    expect(
      registry.artifactsForSession('session-artifacts').first.title,
      'File 6',
    );

    for (var session = 0; session < 45; session++) {
      registry.upsert('session-$session', html, '<html>$session</html>');
    }
    expect(registry.sessionCount, 40);
    expect(registry.artifactsForSession('session-0'), isEmpty);
    expect(registry.artifactsForSession('session-44'), hasLength(1));
  });

  test('selección de versión se acota y latest no ocupa estado', () {
    final registry = GeneratedArtifactRegistry();
    final first = registry.upsert('session', html, '<html>v1</html>')!;
    registry.upsert('session', html, '<html>v2</html>');

    registry.selectVersion(first.artifactId, -10);
    expect(registry.selectedVersion(first.artifactId), 0);

    registry.selectVersion(first.artifactId, 99);
    expect(registry.selectedVersion(first.artifactId), 1);

    registry.clear();
    expect(registry.sessionCount, 0);
    expect(registry.getArtifact(first.artifactId), isNull);
  });

  test(
    'reconstrucción terminal corrige orden, deduplica y notifica una vez',
    () {
      var tick = 0;
      final registry = GeneratedArtifactRegistry(
        clock: () => DateTime.fromMillisecondsSinceEpoch(++tick),
      );
      registry.upsert('session', html, '<html>newest</html>');
      registry.upsert('session', html, '<html>oldest</html>');
      var notifications = 0;
      registry.addListener(() => notifications++);

      registry.replaceSession('session', const [
        GeneratedArtifactInput(detection: html, content: '<html>oldest</html>'),
        GeneratedArtifactInput(detection: html, content: '<html>newest</html>'),
        GeneratedArtifactInput(detection: html, content: '<html>newest</html>'),
      ]);

      final versions = registry.artifactsForSession('session').single.versions;
      expect(versions.map((version) => version.content), [
        '<html>oldest</html>',
        '<html>newest</html>',
      ]);
      expect(notifications, 1);

      registry.replaceSession('session', const [
        GeneratedArtifactInput(detection: html, content: '<html>oldest</html>'),
        GeneratedArtifactInput(detection: html, content: '<html>newest</html>'),
      ]);
      expect(notifications, 1, reason: 'same transcript is a no-op');
    },
  );

  test('reconstruir una sesión no altera ids con el mismo prefijo', () {
    final registry = GeneratedArtifactRegistry();
    final nested = registry.upsert('session:nested', html, '<html>v1</html>')!;
    registry.upsert('session:nested', html, '<html>v2</html>');
    registry.selectVersion(nested.artifactId, 0);
    registry.upsert('session', html, '<html>main</html>');

    registry.replaceSession('session', const []);

    expect(registry.selectedVersion(nested.artifactId), 0);
  });
}
