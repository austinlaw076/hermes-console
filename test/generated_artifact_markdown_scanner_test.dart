import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/generated_artifact.dart';
import 'package:hermes_android/core/utils/generated_artifact_markdown_scanner.dart';

String _repeat(String value, int count) => List.filled(count, value).join();

void main() {
  test('extrae solo fenced blocks sustanciales de una respuesta terminada', () {
    final longCode = '// lib/panel.dart\n${_repeat('final value = 1;\n', 60)}';
    final markdown =
        '''
Explicación breve.

```dart
$longCode
```

```text
Esto no es un artifact.
```
''';

    final artifacts = GeneratedArtifactMarkdownScanner.scan(markdown);

    expect(artifacts, hasLength(1));
    expect(artifacts.single.detection.kind, GeneratedArtifactKind.code);
    expect(artifacts.single.detection.title, 'lib/panel.dart');
    expect(artifacts.single.content, longCode.trim());
  });

  test('tolera fences incompletos sin registrar borradores', () {
    final markdown = '```dart\n${_repeat('final value = 1;\n', 60)}';

    expect(GeneratedArtifactMarkdownScanner.scan(markdown), isEmpty);
  });

  test('conserva dos versiones detectables con el mismo slug', () {
    String block(int value) =>
        '```dart\n// lib/panel.dart\n${_repeat('final value = $value;\n', 60)}```';

    final first = GeneratedArtifactMarkdownScanner.scan(block(1)).single;
    final second = GeneratedArtifactMarkdownScanner.scan(block(2)).single;

    expect(first.detection.title, second.detection.title);
    expect(first.content, isNot(second.content));
  });
}
