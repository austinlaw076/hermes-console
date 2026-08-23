import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/assistant_operational_artifacts.dart';

void main() {
  AssistantOperationalProjection project(String source) =>
      projectAssistantOperationalArtifacts(
        source,
        subagentLabel: (index) => 'Subagente $index',
        resultLabel: 'Resultado',
      );

  test('convierte un resumen real de delegación en etiquetas humanas', () {
    const source = '''
Resultados:

- Batch `deleg_339f13db`
  - 2 + 2 = 4
- Batch `deleg_4f2cd174`
  - `{"result": 4}`
  - `{"result": 6}`
''';

    final result = project(source);

    expect(result.visibleMarkdown, contains('Subagente 1'));
    expect(result.visibleMarkdown, contains('Subagente 2'));
    expect(result.visibleMarkdown, contains('Resultado: 4'));
    expect(result.visibleMarkdown, contains('Resultado: 6'));
    expect(result.visibleMarkdown, isNot(contains('deleg_')));
    expect(result.visibleMarkdown, isNot(contains('{"result"')));
    expect(result.technicalDetails, [
      'Subagente 1 · deleg_339f13db',
      'Subagente 2 · deleg_4f2cd174',
      '{"result": 4}',
      '{"result": 6}',
    ]);
  });

  test('no oculta una mención técnica aislada sin contexto de delegación', () {
    const source = 'El identificador `deleg_339f13db` se persiste como texto.';

    final result = project(source);

    expect(result.visibleMarkdown, source);
    expect(result.technicalDetails, isEmpty);
  });

  test('reconoce un único ID cuando el resumen habla de varios batches', () {
    const source =
        'También finalizó bien: `deleg_f62ec60d` → 4. '
        'Resumen total (3 batches).';

    final result = project(source);

    expect(result.visibleMarkdown, contains('Subagente 1 → 4'));
    expect(result.visibleMarkdown, isNot(contains('deleg_f62ec60d')));
    expect(result.technicalDetails, ['Subagente 1 · deleg_f62ec60d']);
  });

  test('nunca interpreta identificadores dentro de una valla de código', () {
    const source = '''
```dart
const id = 'deleg_339f13db';
const result = '{"result": 4}';
```
''';

    final result = project(source);

    expect(result.visibleMarkdown, source);
    expect(result.technicalDetails, isEmpty);
  });

  test('conserva resultados complejos solo en el detalle técnico', () {
    const source = '''
Subagente `deleg_339f13db`
- `{"result": {"items": [1, 2]}}`
''';

    final result = project(source);

    expect(result.visibleMarkdown, contains('Subagente 1'));
    expect(result.visibleMarkdown, contains('Resultado disponible'));
    expect(result.visibleMarkdown, isNot(contains('"items"')));
    expect(result.technicalDetails.last, '{"result": {"items": [1, 2]}}');
  });
}
