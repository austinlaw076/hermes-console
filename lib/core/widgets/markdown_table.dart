import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_theme.dart';

/// Un segmento de una respuesta del asistente: o Markdown suelto, o una tabla
/// GFM ya parseada para pintarla con [MarkdownTable].
sealed class AnswerSegment {
  const AnswerSegment();
}

/// Trozo de Markdown normal (se pinta con el `MarkdownBody` de siempre).
class MarkdownSegment extends AnswerSegment {
  final String text;
  const MarkdownSegment(this.text);
}

/// Tabla GFM completa. `rows[0]` es la cabecera; el resto, el cuerpo.
class TableSegment extends AnswerSegment {
  final List<List<String>> rows;
  const TableSegment(this.rows);
}

final RegExp _separatorRow = RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$');

bool _looksLikeRow(String line) => line.contains('|');

/// Parte las celdas de una fila GFM respetando los `|` exteriores opcionales y
/// las barras escapadas (`\|`), que NO separan celda.
List<String> _splitRow(String line) {
  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == r'\' && i + 1 < line.length && line[i + 1] == '|') {
      buf.write('|');
      i++;
      continue;
    }
    if (ch == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString().trim());
  // Los `|` exteriores producen una celda vacía al principio/final: se quitan.
  if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
  if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
  return cells;
}

/// Detecta tablas GFM **completas** (una fila de cabecera seguida de una fila
/// separadora `|---|---|`) dentro de [text] y las separa en [TableSegment]; el
/// resto queda como [MarkdownSegment]. Las tablas aún incompletas (en streaming,
/// sin separadora todavía) NO se tocan: caen al render Markdown normal para no
/// parpadear mientras llegan las filas.
List<AnswerSegment> splitAnswerTables(String text) {
  final lines = text.split('\n');
  final segments = <AnswerSegment>[];
  final pending = <String>[]; // Markdown acumulado antes de la tabla en curso.

  void flushPending() {
    if (pending.isEmpty) return;
    final md = pending.join('\n');
    if (md.trim().isNotEmpty) segments.add(MarkdownSegment(md));
    pending.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final isHeader = _looksLikeRow(line) && line.trim().isNotEmpty;
    final hasSeparator =
        i + 1 < lines.length &&
        _separatorRow.hasMatch(lines[i + 1]) &&
        lines[i + 1].contains('-');
    if (isHeader && hasSeparator) {
      // Arranca una tabla: cabecera (i), separadora (i+1), cuerpo (i+2…).
      final header = _splitRow(line);
      final rows = <List<String>>[header];
      var j = i + 2;
      while (j < lines.length &&
          _looksLikeRow(lines[j]) &&
          lines[j].trim().isNotEmpty) {
        rows.add(_splitRow(lines[j]));
        j++;
      }
      // Solo la tratamos como tabla si tiene al menos una fila de datos; si no,
      // es más seguro dejarla como Markdown.
      if (rows.length >= 2) {
        flushPending();
        segments.add(TableSegment(_normalizeTable(rows)));
        i = j;
        continue;
      }
    }
    pending.add(line);
    i++;
  }
  flushPending();
  return segments;
}

/// Corrige el desajuste de columnas más común de las tablas mal formadas por el
/// modelo: una cabecera con celdas de más (una `-` o vacía inicial, un artefacto
/// típico) que desplaza las etiquetas respecto a los datos. Toma como fuente de
/// verdad el nº de columnas MÁS COMÚN de las filas de datos, quita las celdas
/// basura del inicio de la cabecera y cuadra todas las filas a ese ancho. Las
/// tablas bien formadas (todas las filas con el mismo nº de celdas) no cambian.
List<List<String>> _normalizeTable(List<List<String>> rows) {
  if (rows.length < 2) return rows;
  final counts = <int, int>{};
  for (var i = 1; i < rows.length; i++) {
    counts[rows[i].length] = (counts[rows[i].length] ?? 0) + 1;
  }
  var modal = rows[1].length;
  var best = 0;
  counts.forEach((len, n) {
    if (n > best) {
      best = n;
      modal = len;
    }
  });

  final fixed = <List<String>>[];
  for (var i = 0; i < rows.length; i++) {
    var cells = List<String>.from(rows[i]);
    if (i == 0) {
      // Cabecera con celdas de más: quita las vacías o `-` del inicio (el
      // artefacto que descuadra) y, si aún sobra, recorta por el final.
      while (cells.length > modal &&
          (cells.first.isEmpty || cells.first == '-')) {
        cells.removeAt(0);
      }
    }
    if (cells.length < modal) {
      cells = [...cells, ...List<String>.filled(modal - cells.length, '')];
    } else if (cells.length > modal) {
      cells = cells.sublist(0, modal);
    }
    fixed.add(cells);
  }
  return fixed;
}

/// Quita el marcado inline de una celda para pintarla como texto plano legible:
/// `[texto](url)` → `texto`, y elimina `**`, `__`, `` ` `` y `~~`. Es
/// deliberadamente conservador (las celdas casi siempre son texto o enlaces).
String stripInlineMarkdown(String s) {
  var t = s.trim();
  t = t.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  t = t.replaceAll(RegExp(r'\*\*|__|~~|`'), '');
  return t.trim();
}

/// Tabla GFM con estética limpia (borde redondeado, cabecera destacada, filas
/// con separadores finos). Cada columna toma su **ancho propio** según el
/// contenido (acotado a [_maxColumn], por encima la celda envuelve) y la tabla
/// se **desplaza en horizontal** si no cabe, en vez de apretar y partir la
/// cabecera. Las celdas se pintan con Markdown real (enlaces PULSABLES, negrita,
/// código) reusando el manejador de enlaces del chat vía [onLinkTap].
class MarkdownTable extends StatelessWidget {
  final List<List<String>> rows;

  /// Manejador de tap en enlaces de celda (mismo que el chat: apertura segura).
  final void Function(String? href)? onLinkTap;

  const MarkdownTable({required this.rows, this.onLinkTap, super.key});

  // Relleno horizontal de cada celda (izq + der). Debe cuadrar con el Padding.
  static const double _cellPadding = 24;
  // Margen de seguridad para negrita/código/subrayado (la medición usa el texto
  // plano; el render puede ser algo más ancho).
  static const double _safety = 12;
  // Ancho mínimo legible y tope por columna (por encima, la celda envuelve).
  static const double _minColumn = 44;
  static const double _maxColumn = 300;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.fold<int>(0, (m, r) => math.max(m, r.length));
    if (colCount == 0) return const SizedBox.shrink();

    final textScaler = MediaQuery.textScalerOf(context);
    // CLAVE: medir con la MISMA fuente con la que se pinta la celda. El tema usa
    // una fuente propia (más ancha que la de sistema); si midiéramos con la de
    // sistema, la columna quedaría corta y partiría palabras ("TechCrunc h").
    final themeBase =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final headerStyle = themeBase.copyWith(
      fontSize: 12.5,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    );
    final bodyStyle = themeBase.copyWith(
      fontSize: 12.5,
      height: 1.35,
      fontWeight: FontWeight.w400,
      color: colors.textSecondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final widths = _columnWidths(
          colCount,
          textScaler,
          headerStyle,
          bodyStyle,
        );
        final total = widths.fold<double>(0, (a, b) => a + b);

        final table = Table(
          columnWidths: {
            for (var c = 0; c < colCount; c++) c: FixedColumnWidth(widths[c]),
          },
          border: TableBorder(
            horizontalInside: BorderSide(
              color: colors.divider.withValues(alpha: 0.32),
            ),
            verticalInside: BorderSide(
              color: colors.divider.withValues(alpha: 0.32),
            ),
          ),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r == 0
                      ? colors.surfaceVariant.withValues(alpha: 0.65)
                      : null,
                ),
                children: [
                  for (var c = 0; c < colCount; c++)
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: _cell(
                          context,
                          colors,
                          c < rows[r].length ? rows[r][c] : '',
                          r == 0 ? headerStyle : bodyStyle,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );

        // Ancho propio por columna; si excede la pantalla se desplaza en
        // horizontal (mejor que apretar y partir la cabecera). Si cabe, la
        // tabla ocupa solo su ancho (alineada a la izquierda).
        final Widget content = total > maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: total, child: table),
              )
            : SizedBox(width: total, child: table);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: colors.divider.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      },
    );
  }

  /// Celda pintada como Markdown real: enlaces pulsables (vía [onLinkTap]),
  /// negrita, código en línea, etc. Reusa el color de acento para los enlaces.
  /// [base] es el estilo (con la fuente del tema) con el que también se midió la
  /// columna, para que medida y render coincidan.
  Widget _cell(
    BuildContext context,
    HermesThemeColors colors,
    String data,
    TextStyle base,
  ) {
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      a: base.copyWith(
        color: colors.accent,
        decoration: TextDecoration.underline,
        decorationColor: colors.accent.withValues(alpha: 0.5),
      ),
      code: base.copyWith(
        fontFamily: 'JetBrainsMono',
        color: colors.textPrimary,
        backgroundColor: colors.surface,
      ),
      blockSpacing: 0,
      pPadding: EdgeInsets.zero,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: sheet,
      onTapLink: (text, href, title) => onLinkTap?.call(href),
    );
  }

  /// Ancho de cada columna = ancho natural del texto en una línea (acotado entre
  /// [_minColumn] y [_maxColumn]). Se mide con [headerStyle]/[bodyStyle], que
  /// llevan la fuente REAL del tema, para que la columna no parta palabras. Sin
  /// repartos ni encogimientos; si la suma no cabe, el `build` la desplaza.
  List<double> _columnWidths(
    int colCount,
    TextScaler textScaler,
    TextStyle headerStyle,
    TextStyle bodyStyle,
  ) {
    final widths = List<double>.filled(colCount, 0);
    for (var r = 0; r < rows.length; r++) {
      final style = r == 0 ? headerStyle : bodyStyle;
      for (var c = 0; c < rows[r].length && c < colCount; c++) {
        final tp = TextPainter(
          text: TextSpan(text: stripInlineMarkdown(rows[r][c]), style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textScaler: textScaler,
        )..layout();
        widths[c] = math.max(widths[c], tp.width + _cellPadding + _safety);
      }
    }
    for (var c = 0; c < colCount; c++) {
      widths[c] = widths[c].clamp(_minColumn, _maxColumn);
    }
    return widths;
  }
}
