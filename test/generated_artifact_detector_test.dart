import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/generated_artifact.dart';
import 'package:hermes_android/core/utils/generated_artifact_detector.dart';

String _repeat(String value, int count) => List.filled(count, value).join();

void main() {
  test('detecta documentos HTML sustanciales con título', () {
    final content =
        '''
<!doctype html>
<html><head><title>Panel Hermes</title></head>
<body><main>${_repeat('contenido ', 20)}</main></body></html>
''';

    final detection = GeneratedArtifactDetector.detect('html', content);

    expect(detection?.kind, GeneratedArtifactKind.html);
    expect(detection?.language, 'html');
    expect(detection?.title, 'Panel Hermes');
  });

  test('rechaza HTML corto, texto, logs y bloques de prosa', () {
    expect(
      GeneratedArtifactDetector.detect('html', '<html><body>x</body></html>'),
      isNull,
    );
    expect(
      GeneratedArtifactDetector.detect('text', _repeat('línea\n', 80)),
      isNull,
    );
    expect(
      GeneratedArtifactDetector.detect('log', _repeat('INFO ready\n', 80)),
      isNull,
    );
    expect(
      GeneratedArtifactDetector.detect(
        'custom',
        _repeat('- Esta es una explicación larga.\n', 60),
      ),
      isNull,
    );
  });

  test('detecta SVG grande y código largo con identidad estable', () {
    final svg =
        '<svg><title>Mapa</title>${_repeat('<path d="M0 0" />', 150)}</svg>';
    final code = '// lib/example.dart\n${_repeat('final value = 1;\n', 60)}';

    final svgDetection = GeneratedArtifactDetector.detect('svg', svg)!;
    final codeDetection = GeneratedArtifactDetector.detect('dart', code)!;

    expect(svgDetection.kind, GeneratedArtifactKind.svg);
    expect(svgDetection.title, 'Mapa');
    expect(codeDetection.kind, GeneratedArtifactKind.code);
    expect(codeDetection.title, 'lib/example.dart');
    expect(
      GeneratedArtifactDetector.slug(codeDetection),
      'code:dart:lib-example-dart',
    );
    expect(
      GeneratedArtifactDetector.downloadName(codeDetection),
      'libexample.dart',
    );
  });

  test('sanitiza language tags y nombres de descarga', () {
    expect(
      GeneratedArtifactDetector.sanitizeLanguage('Python extra'),
      'python',
    );
    expect(GeneratedArtifactDetector.sanitizeLanguage('../html'), '');
    expect(GeneratedArtifactDetector.sanitizeLanguage(_repeat('x', 17)), '');

    const detection = GeneratedArtifactDetection(
      kind: GeneratedArtifactKind.code,
      language: 'python',
      title: 'Mi script',
    );
    expect(GeneratedArtifactDetector.downloadName(detection), 'Mi-script.py');
  });
}
