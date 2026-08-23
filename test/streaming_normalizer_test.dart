import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/streaming_normalizer.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('normalizeStreamingMarkdown', () {
    test('una respuesta terminal se renderiza intacta, sin reparar', () {
      const input = 'Hola\n```bash\necho hi'; // valla abierta a propósito
      // El mensaje final se muestra tal cual llegó del servidor; la reparación
      // por bloque es exclusiva del texto vivo durante el streaming.
      expect(normalizeStreamingMarkdown(input, isStreaming: false), input);
      expect(
        normalizeStreamingMarkdown(input, isStreaming: true),
        '$input\n```',
      );
    });

    test('devuelve vacío intacto', () {
      expect(normalizeStreamingMarkdown('', isStreaming: true), '');
    });

    test('cierra una valla de código abierta durante streaming', () {
      const input = 'texto\n```bash\necho hola';
      final out = normalizeStreamingMarkdown(input, isStreaming: true);
      expect(out.endsWith('```'), isTrue);
      // El contenido original se conserva al inicio.
      expect(out.startsWith(input), isTrue);
    });

    test('no añade valla si las vallas ya están equilibradas', () {
      const input = '```dart\nvoid main() {}\n```';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), input);
    });

    test('cierra backtick inline impar en la última línea', () {
      const input = 'usa el comando `flutter run';
      final out = normalizeStreamingMarkdown(input, isStreaming: true);
      expect(out, 'usa el comando `flutter run`');
    });

    test('no cierra backticks pares inline', () {
      const input = 'usa `flutter run` ahora';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), input);
    });

    test('dentro de un bloque abierto no trata el backtick como inline', () {
      // Valla impar => bloque abierto; aunque haya un ` suelto dentro,
      // solo se cierra la valla, no se añade backtick inline extra.
      const input = '```\nlínea con un ` suelto';
      final out = normalizeStreamingMarkdown(input, isStreaming: true);
      expect(out, '```\nlínea con un ` suelto\n```');
    });

    test('texto plano sin marcadores se mantiene', () {
      const input = 'Una respuesta normal sin código ni nada.';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), input);
    });

    test('cierra énfasis fuerte incompleto durante streaming', () {
      const input = 'Una respuesta **importante';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), '$input**');
    });

    test('no cierra cursiva incompleta en una respuesta terminal', () {
      const input = 'Una respuesta *incompleta';
      expect(normalizeStreamingMarkdown(input, isStreaming: false), input);
    });

    test('un marcador `[` o un enlace a medias terminal quedan intactos', () {
      for (final input in [
        'Nota al margen [',
        'Abre [la guía](https://example.com/ru',
        'Abre [la guía]',
      ]) {
        expect(
          normalizeStreamingMarkdown(input, isStreaming: false),
          input,
          reason: input,
        );
      }
    });

    test('no toca énfasis válido, listas, palabras ni reglas', () {
      const input = '**fuerte** y _cursiva_ y snake_case\n\n* elemento\n\n***';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), input);
    });

    test('repara énfasis incompleto aunque el texto contenga una barra', () {
      const input = '6. **Salud/ciencia';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), '$input**');
    });

    test('ignora marcadores dentro de código y globs de rutas', () {
      const input = r'usa `a * b` y /home/demo/**/*.pdf';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), input);
    });

    test('repara también un bloque estable sin afectar el párrafo final', () {
      const input = '- item con **marcador huérfano\n\nPárrafo final limpio.';
      const expected =
          '- item con **marcador huérfano**\n\nPárrafo final limpio.';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), expected);
      // El mismo documento ya terminal NO se repara: se pinta tal cual.
      expect(normalizeStreamingMarkdown(input, isStreaming: false), input);
    });

    test(
      'oculta colas formadas únicamente por marcadores durante el stream',
      () {
        for (final input in [
          '*',
          '**',
          '`',
          '~',
          '[',
          'Respuesta **',
          'Respuesta [',
        ]) {
          final output = normalizeStreamingMarkdown(input, isStreaming: true);
          expect(
            output,
            isNot(anyOf(endsWith('*'), endsWith('`'), endsWith('['))),
            reason: input,
          );
        }
      },
    );

    test('muestra como texto limpio un enlace todavía incompleto', () {
      expect(
        normalizeStreamingMarkdown(
          'Abre [la guía](https://example.com/ru',
          isStreaming: true,
        ),
        'Abre la guía',
      );
      expect(
        normalizeStreamingMarkdown('Abre [la guía]', isStreaming: true),
        'Abre la guía',
      );
    });

    test('cierra tachado incompleto sin mostrar tildes', () {
      const input = 'Esto ~~ya no sirve';
      expect(normalizeStreamingMarkdown(input, isStreaming: true), '$input~~');
    });

    test(
      'todos los prefijos mixtos se pueden parsear sin sintaxis visible',
      () {
        const corpus =
            '**Negrita** y *cursiva*. Usa `flutter run`, '
            '[la guía](https://example.com) y ~~texto retirado~~.';
        for (var end = 1; end <= corpus.length; end++) {
          final repaired = normalizeStreamingMarkdown(
            escapePathGlobs(corpus.substring(0, end)),
            isStreaming: true,
          );
          final visible = md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          ).parse(repaired).map((node) => node.textContent).join();
          expect(visible, isNot(contains('*')), reason: 'prefijo $end');
          expect(visible, isNot(contains('`')), reason: 'prefijo $end');
          expect(visible, isNot(contains('[')), reason: 'prefijo $end');
          expect(visible, isNot(contains(']')), reason: 'prefijo $end');
          expect(visible, isNot(contains('~')), reason: 'prefijo $end');
        }
      },
    );

    test('el caso real Modelo recomendado no filtra asteriscos', () {
      const input = '**Modelo recomendado (simple y limpio)**';

      for (var end = 1; end <= input.length; end++) {
        final repaired = normalizeStreamingMarkdown(
          input.substring(0, end),
          isStreaming: end < input.length,
        );
        final visible = md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parse(repaired).map((node) => node.textContent).join();

        expect(visible, isNot(contains('*')), reason: 'prefijo $end');
        if (end == input.length) {
          expect(visible, 'Modelo recomendado (simple y limpio)');
        }
      }
    });
  });

  group('escapePathGlobs', () {
    test('escapa asteriscos en rutas/globs', () {
      const input = 'He buscado /home/demo/**/*.pdf en el disco';
      final out = escapePathGlobs(input);
      expect(out, contains(r'/home/demo/\*\*/\*.pdf'));
    });

    test('no toca énfasis real en prosa', () {
      const input = 'Esto es **importante** y *cursiva* de verdad';
      expect(escapePathGlobs(input), input);
    });

    test('no confunde un título enfatizado con barra con una ruta glob', () {
      const input = '6. **Salud/ciencia**';
      expect(escapePathGlobs(input), input);
    });

    test('preserva un opener enfatizado con barra durante streaming', () {
      const input = '6. **Salud/ciencia';
      expect(escapePathGlobs(input), input);
    });

    test('ningún prefijo del caso real filtra asteriscos al render', () {
      const input = '6. **Salud/ciencia**';
      for (var end = 1; end <= input.length; end++) {
        final visible =
            md.Document(
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  encodeHtml: false,
                )
                .parse(
                  normalizeStreamingMarkdown(
                    escapePathGlobs(input.substring(0, end)),
                    isStreaming: true,
                  ),
                )
                .map((node) => node.textContent)
                .join();
        expect(visible, isNot(contains('*')), reason: 'prefijo $end');
      }
    });

    test(
      'cualquier énfasis con barras conserva Markdown en todo el stream',
      () {
        const samples = [
          '**Economía/política**',
          '*entrada/salida*',
          '***A/B***',
          '**Ciencia/tecnología y salud pública**.',
          '**categoría/subcategoría (con detalle)**',
        ];

        for (final input in samples) {
          expect(escapePathGlobs(input), input, reason: input);
          for (var end = 1; end <= input.length; end++) {
            final visible =
                md.Document(
                      extensionSet: md.ExtensionSet.gitHubFlavored,
                      encodeHtml: false,
                    )
                    .parse(
                      normalizeStreamingMarkdown(
                        escapePathGlobs(input.substring(0, end)),
                        isStreaming: true,
                      ),
                    )
                    .map((node) => node.textContent)
                    .join();
            expect(
              visible,
              isNot(contains('*')),
              reason: '$input · prefijo $end',
            );
          }
        }
      },
    );

    test('preserva énfasis y escapa solo el glob de una ruta enfatizada', () {
      const input = '**/home/demo/**/*.pdf**';
      expect(escapePathGlobs(input), r'**/home/demo/\*\*/\*.pdf**');
    });

    test(
      'preserva cierre de énfasis multi-palabra cuando contiene una barra',
      () {
        const input =
            '- **App base:** **Gratuita**\n'
            '- **Pago opcional in-app:** **Pack de temas/personalización**';
        expect(escapePathGlobs(input), input);
      },
    );

    test('escapar globs es idempotente', () {
      const input = 'He buscado /home/demo/**/*.pdf en el disco';
      final once = escapePathGlobs(input);
      expect(escapePathGlobs(once), once);
    });

    test('no toca asteriscos dentro de código inline', () {
      const input = 'usa `/home/**/*.pdf` aquí';
      expect(escapePathGlobs(input), input);
    });

    test('no toca contenido dentro de vallas de código', () {
      const input = '```\nls /home/**/*.pdf\n```';
      expect(escapePathGlobs(input), input);
    });

    test('texto sin asteriscos intacto', () {
      const input = 'Una ruta normal /home/demo/archivo.pdf';
      expect(escapePathGlobs(input), input);
    });
  });
}
