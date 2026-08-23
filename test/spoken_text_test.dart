import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/spoken_text.dart';

void main() {
  group('SpokenText.fromMarkdown', () {
    test('quita las almohadillas de los encabezados', () {
      expect(
        SpokenText.fromMarkdown('## Tendencias de GitHub'),
        'Tendencias de GitHub',
      );
      expect(SpokenText.fromMarkdown('###Sin espacio'), 'Sin espacio');
    });

    test('quita negrita, cursiva y tachado conservando el texto', () {
      expect(
        SpokenText.fromMarkdown('Esto es **muy** importante'),
        'Esto es muy importante',
      );
      expect(
        SpokenText.fromMarkdown('palabra _en cursiva_ aquí'),
        'palabra en cursiva aquí',
      );
      expect(SpokenText.fromMarkdown('algo ~~tachado~~ va'), 'algo tachado va');
    });

    test(
      'viñetas y listas numeradas: quita el marcador, conserva el texto',
      () {
        expect(SpokenText.fromMarkdown('- primer punto'), 'primer punto');
        expect(SpokenText.fromMarkdown('1. uno\n2. dos'), 'uno\ndos');
        expect(SpokenText.fromMarkdown('* item'), 'item');
      },
    );

    test('enlaces: conserva el texto, descarta la URL', () {
      expect(
        SpokenText.fromMarkdown('mira [el repo](https://github.com/x)'),
        'mira el repo',
      );
    });

    test('URLs sueltas se descartan', () {
      expect(
        SpokenText.fromMarkdown('visita https://ejemplo.com ya').trim(),
        'visita ya',
      );
    });

    test('código en línea conserva el contenido sin las comillas', () {
      expect(
        SpokenText.fromMarkdown('usa `flutter test` ahora'),
        'usa flutter test ahora',
      );
    });

    test('bloque de código vallado se elimina', () {
      final r = SpokenText.fromMarkdown('antes\n```\ncodigo();\n```\ndespués');
      expect(r.contains('codigo'), isFalse);
      expect(r.contains('antes'), isTrue);
      expect(r.contains('después'), isTrue);
    });

    test('regla horizontal desaparece', () {
      expect(SpokenText.fromMarkdown('arriba\n---\nabajo'), 'arriba\nabajo');
    });

    test('tabla: separa celdas con comas y descarta la fila separadora', () {
      final r = SpokenText.fromMarkdown(
        '| Repo | Estrellas |\n| --- | --- |\n| foo | 100 |',
      );
      expect(r.contains('almohadilla'), isFalse);
      expect(r.contains('|'), isFalse);
      expect(r.contains('Repo, Estrellas'), isTrue);
      expect(r.contains('foo, 100'), isTrue);
    });

    test('citas: quita el ">" inicial', () {
      expect(SpokenText.fromMarkdown('> una cita'), 'una cita');
    });

    test('prosa normal pasa intacta', () {
      expect(
        SpokenText.fromMarkdown('Hola, ¿cómo estás? Todo bien.'),
        'Hola, ¿cómo estás? Todo bien.',
      );
    });

    test('contenido que queda vacío devuelve cadena vacía', () {
      expect(SpokenText.fromMarkdown('---'), '');
      expect(SpokenText.fromMarkdown('https://solo-una-url.com').trim(), '');
    });

    test('caso real: lista de trending con negritas y guiones', () {
      final r = SpokenText.fromMarkdown(
        '## Trending\n- **vercel/next.js** — el framework de React\n'
        '- **rust-lang/rust** — lenguaje de sistemas',
      );
      expect(r.contains('*'), isFalse);
      expect(r.contains('#'), isFalse);
      expect(r.contains('Trending'), isTrue);
      expect(r.contains('vercel/next.js'), isTrue);
      expect(r.contains('el framework de React'), isTrue);
    });
  });
}
