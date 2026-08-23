import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/speech_renderer.dart';

/// Spec 048 — regresiones de calidad de lectura encontradas escuchando la QA
/// en el Pixel (2026-07-24). Cada caso fue basura audible real.
void main() {
  String es(String raw) => const SpeechRenderer(
    language: 'es',
  ).render(raw).map((s) => s.text).join(' ');

  String en(String raw) => const SpeechRenderer(
    language: 'en',
  ).render(raw).map((s) => s.text).join(' ');

  test('nunca aparece el marcador de grupo "\$1" en el habla', () {
    // Al quitar un emoji quedaba " ." y una regla mal escrita insertaba el
    // texto literal "$1" → el motor decía "dólar uno".
    final spoken = es('Vale, hecho ✅. Listo 🚀.');
    expect(spoken, isNot(contains(r'$1')));
    expect(spoken, isNot(contains(r'$')));
    expect(spoken, contains('Vale, hecho.'));
  });

  test('las barras de rutas y endpoints no se leen como "o"', () {
    expect(es('Falló en /api/audio/speak.'), isNot(contains(' o ')));
    expect(es('Falló en /api/audio/speak.'), contains('api audio speak'));
    expect(es('Abre src/lib/main.dart ahí.'), isNot(contains(' o ')));
    // Una ruta relativa se reduce a su archivo (ver test de abajo).
    expect(es('Abre src/lib/main.dart ahí.'), contains('main'));
  });

  test('un repo se dice por su nombre, no por el dueño y la barra', () {
    // Feedback del owner: preguntó qué es "omniroute" y la voz le leía el
    // repo entero en vez del nombre.
    expect(
      es('El repo rusty4444/omniroute sirve para eso.'),
      contains('omniroute sirve'),
    );
    expect(
      es('El repo rusty4444/omniroute sirve para eso.'),
      isNot(contains('rusty4444')),
    );
  });

  test('una ruta de archivo se dice por el archivo', () {
    expect(es('Está en src/lib/main.dart ahí.'), contains('main'));
    expect(es('Está en src/lib/main.dart ahí.'), isNot(contains('src')));
    expect(es('Está en src/lib/main.dart ahí.'), isNot(contains('lib')));
  });

  test('"y/o" sí conserva el sentido de disyuntiva', () {
    expect(es('Puedes usar café y/o té.'), contains(' o '));
  });

  test('las horas se hablan y los emojis no llegan al motor', () {
    final spoken = es('Reunión a las 14:30 👋.');
    expect(spoken, contains('14 y 30'));
    expect(
      spoken,
      isNot(matches(RegExp(r'[\u{1F000}-\u{1FAFF}]', unicode: true))),
    );
  });

  test('omite líneas de fuente y enlaces aislados sin cortar la noticia', () {
    final spoken = es('''
En España hay nuevas medidas.

Fuente: https://example.com/noticia
[Leer la noticia](https://example.com/noticia)
[ref]: https://example.com/origen

La explicación continúa.
''');

    expect(spoken, contains('En España hay nuevas medidas.'));
    expect(spoken, contains('La explicación continúa.'));
    expect(spoken.toLowerCase(), isNot(contains('fuente')));
    expect(spoken.toLowerCase(), isNot(contains('leer la noticia')));
    expect(spoken, isNot(contains('example')));
  });

  test('source aislado se omite, pero una mención normal se conserva', () {
    expect(
      en('The source confirmed the report.'),
      contains('The source confirmed the report.'),
    );
    expect(en('Source: [BBC](https://bbc.example/news)'), isEmpty);
  });

  test('omite encabezados de fuentes decorados con Markdown', () {
    final spoken = es('''
La noticia principal sigue confirmada.

**Fuentes:**
https://efe.com/portada-espana/

### Fuentes
- https://www.rtve.es/noticias/

La recomendación final sigue siendo válida.
''');

    expect(spoken, contains('La noticia principal sigue confirmada.'));
    expect(spoken, contains('La recomendación final sigue siendo válida.'));
    expect(spoken.toLowerCase(), isNot(contains('fuente')));
    expect(spoken, isNot(contains('efe')));
    expect(spoken, isNot(contains('rtve')));
  });

  test('omite Sources decorado sin perder la prosa inglesa', () {
    final spoken = en('''
The explanation remains useful.

### Sources
- https://example.com/report

The final recommendation remains useful.
''');

    expect(spoken, contains('The explanation remains useful.'));
    expect(spoken, contains('The final recommendation remains useful.'));
    expect(spoken.toLowerCase(), isNot(contains('source')));
    expect(spoken, isNot(contains('example')));
  });

  test('omite entradas bibliográficas con una etiqueta y una URL', () {
    final spoken = es('''
Resumen de las noticias.

- RTVE: https://www.rtve.es/noticias/
EFE: [Portada](https://efe.com/portada-espana/)

Fin del resumen.
''');

    expect(spoken, contains('Resumen de las noticias.'));
    expect(spoken, contains('Fin del resumen.'));
    expect(spoken, isNot(contains('RTVE')));
    expect(spoken, isNot(contains('EFE')));
    expect(spoken.toLowerCase(), isNot(contains('portada')));
  });
}
