// Parser de tablas GFM (splitAnswerTables) + saneado de celdas: separar tablas
// COMPLETAS del resto del Markdown para pintarlas con un render propio, sin
// tocar tablas a medias (streaming) ni contenido sin tablas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/markdown_table.dart';

void main() {
  group('splitAnswerTables', () {
    test('texto sin tabla queda como un único segmento Markdown', () {
      final segs = splitAnswerTables('Hola **mundo**\n\nsegunda línea.');
      expect(segs, hasLength(1));
      expect(segs.first, isA<MarkdownSegment>());
      expect((segs.first as MarkdownSegment).text, contains('mundo'));
    });

    test('tabla completa se separa en un TableSegment con filas parseadas', () {
      const md = '''
| Clave | Valor |
| ----- | ----- |
| host  | local |
| port  | 9119  |''';
      final segs = splitAnswerTables(md);
      expect(segs, hasLength(1));
      final table = segs.single as TableSegment;
      expect(table.rows, hasLength(3)); // cabecera + 2 filas (sin separadora)
      expect(table.rows[0], ['Clave', 'Valor']);
      expect(table.rows[1], ['host', 'local']);
      expect(table.rows[2], ['port', '9119']);
    });

    test('texto + tabla + texto → Markdown, tabla, Markdown', () {
      const md = '''
Antes de la tabla.

| A | B |
|---|---|
| 1 | 2 |

Después de la tabla.''';
      final segs = splitAnswerTables(md);
      expect(segs, hasLength(3));
      expect(segs[0], isA<MarkdownSegment>());
      expect(segs[1], isA<TableSegment>());
      expect(segs[2], isA<MarkdownSegment>());
      expect((segs[0] as MarkdownSegment).text, contains('Antes'));
      expect((segs[2] as MarkdownSegment).text, contains('Después'));
    });

    test('tabla a medias (sin fila separadora) NO se trocea', () {
      // En streaming llega la cabecera pero aún no la separadora: debe quedar
      // como Markdown para no parpadear.
      const md = '| Clave | Valor |\n| host | local |';
      final segs = splitAnswerTables(md);
      expect(segs, hasLength(1));
      expect(segs.single, isA<MarkdownSegment>());
    });

    test('cabecera descuadrada (celda "-" de más) se realinea a los datos', () {
      // Artefacto típico del modelo: la cabecera trae una celda inicial "-" que
      // no está en los datos, desplazando "Hora"/"Fuente"/"Título".
      const md = '''
| - | Hora | Fuente | Título |
|---|------|--------|--------|
| 23:12 | TechCrunch | Databricks hits \$188B |
| 23:09 | The Verge | Taylor Farms retira lechuga |''';
      final segs = splitAnswerTables(md);
      final table = segs.single as TableSegment;
      // Todas las filas quedan a 3 columnas (el ancho de los datos).
      expect(table.rows.every((r) => r.length == 3), isTrue);
      // La cabecera pierde el "-" inicial y queda alineada con los datos.
      expect(table.rows[0], ['Hora', 'Fuente', 'Título']);
      expect(table.rows[1], ['23:12', 'TechCrunch', 'Databricks hits \$188B']);
    });

    test('tabla bien formada no se altera', () {
      const md = '''
| A | B |
|---|---|
| 1 | 2 |
| 3 | 4 |''';
      final table = splitAnswerTables(md).single as TableSegment;
      expect(table.rows, [
        ['A', 'B'],
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('celdas con pipes exteriores y pipe escapado se parsean bien', () {
      const md = '''
| Comando | Efecto |
|---|---|
| `a \\| b` | pipe literal |''';
      final segs = splitAnswerTables(md);
      final table = segs.single as TableSegment;
      expect(table.rows[1][0], '`a | b`'); // el \| no separa celda
      expect(table.rows[1][1], 'pipe literal');
    });
  });

  group('stripInlineMarkdown', () {
    test('convierte enlaces a su texto y quita énfasis', () {
      expect(stripInlineMarkdown('[Ver aquí](https://x.y/z)'), 'Ver aquí');
      expect(stripInlineMarkdown('**negrita**'), 'negrita');
      expect(stripInlineMarkdown('`código`'), 'código');
      expect(stripInlineMarkdown('texto normal'), 'texto normal');
    });
  });

  testWidgets('la cabecera usa una superficie neutra, no el acento', (
    tester,
  ) async {
    late HermesThemeColors palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              palette = Theme.of(context).hermes;
              return const MarkdownTable(
                rows: [
                  ['Fuente', 'Titular'],
                  ['El Mundo', 'Noticia'],
                ],
              );
            },
          ),
        ),
      ),
    );

    final table = tester.widget<Table>(find.byType(Table));
    final headerDecoration = table.children.first.decoration as BoxDecoration;
    expect(
      headerDecoration.color,
      palette.surfaceVariant.withValues(alpha: 0.65),
    );
    expect(
      headerDecoration.color,
      isNot(palette.accent.withValues(alpha: 0.10)),
    );
  });
}
