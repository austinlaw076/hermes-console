import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/markdown_clipboard.dart';

void main() {
  group('userMessageClipboardText', () {
    test('conserva exactamente el Markdown original al copiar', () {
      const markdown =
          '# Título\n\n'
          '- **negrita** y *cursiva*\n'
          '- [enlace](https://example.com?q=uno&lang=es)\n\n'
          'Usa `valor > 2` y conserva dos espacios al final.\x20\x20\n\n'
          '```dart\n'
          'final text = "# literal";\n'
          '```\n';

      expect(userMessageClipboardText(markdown), markdown);
    });
  });

  group('markdownToClipboardText', () {
    test('elimina encabezados, citas y énfasis', () {
      const markdown = '''
# Resumen

> Esto es **importante** y *urgente*.
''';

      expect(
        markdownToClipboardText(markdown),
        'Resumen\n\nEsto es importante y urgente.',
      );
    });

    test('convierte listas en texto legible', () {
      const markdown = '''
- Primero
- Segundo
  1. Subpaso uno
  2. Subpaso dos
''';

      expect(
        markdownToClipboardText(markdown),
        '• Primero\n• Segundo\n  1. Subpaso uno\n  2. Subpaso dos',
      );
    });

    test('conserva la etiqueta visible de enlaces e imágenes', () {
      expect(
        markdownToClipboardText(
          'Consulta [la guía](https://example.com) y ![captura](image.png).',
        ),
        'Consulta la guía y captura.',
      );
    });

    test('quita backticks y vallas sin alterar el código', () {
      const markdown = '''
Ejecuta `a * b > c`:

```bash
echo "# no es un título"
value="*literal*"
```
''';

      expect(
        markdownToClipboardText(markdown),
        'Ejecuta a * b > c:\n\necho "# no es un título"\nvalue="*literal*"',
      );
    });

    test('no normaliza líneas vacías dentro de un bloque de código', () {
      const markdown = '```text\nuno\n\n\n\ntres\n```';
      expect(markdownToClipboardText(markdown), 'uno\n\n\n\ntres');
    });

    test('respeta caracteres escapados y texto sin formato', () {
      expect(
        markdownToClipboardText(r'Precio: \*5\* y operador 3 > 2.'),
        'Precio: *5* y operador 3 > 2.',
      );
      expect(markdownToClipboardText('Texto normal.'), 'Texto normal.');
    });

    test('mantiene párrafos y saltos de línea explícitos', () {
      const markdown = 'Primera línea.  \nSegunda línea.\n\nOtro párrafo.';
      expect(
        markdownToClipboardText(markdown),
        'Primera línea.\nSegunda línea.\n\nOtro párrafo.',
      );
    });
  });

  group('markdownToCompactText', () {
    test('deja una preview en una sola línea y sin Markdown visible', () {
      const markdown = '''
Para Play Store, **te lo montaría así**.

## 1) Sube el AAB.
''';

      expect(
        markdownToCompactText(markdown),
        'Para Play Store, te lo montaría así. 1) Sube el AAB.',
      );
    });

    test('limpia headings si el servidor ya aplanó los saltos', () {
      expect(
        markdownToCompactText('Modelo **recomendado**. ## 1) Simple y limpio.'),
        'Modelo recomendado. 1) Simple y limpio.',
      );
    });
  });
}
