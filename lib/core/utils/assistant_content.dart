/// Modelado del contenido del asistente para presentación.
///
/// Capa **puramente de presentación**: separa el razonamiento (`<think>…`) de la
/// respuesta final y aplica retoques conservadores al Markdown que algunos
/// modelos emiten mal formado (encabezados pegados al `#`). NO altera el
/// contenido guardado por `ActiveChatService`: se aplica solo al renderizar.
///
/// Reglas (conservadoras: ante la duda, no tocar). Si el texto no contiene
/// ninguna etiqueta de razonamiento, [splitReasoning] devuelve la respuesta
/// intacta, garantizando cero cambios de comportamiento en el caso normal.
library;

/// Resultado de separar el razonamiento de la respuesta visible.
class ReasoningSplit {
  /// Texto del razonamiento (sin etiquetas). Puede ser cadena vacía.
  final String reasoning;

  /// Respuesta final visible (Markdown), ya sin las etiquetas de razonamiento.
  final String answer;

  /// `true` cuando hay un `<think>` abierto sin cerrar todavía (el modelo sigue
  /// razonando durante el streaming). Útil para mostrar un estado "pensando…".
  final bool reasoningInProgress;

  const ReasoningSplit({
    required this.reasoning,
    required this.answer,
    this.reasoningInProgress = false,
  });

  /// `true` si hay algo de razonamiento que mostrar (cerrado o en curso).
  bool get hasReasoning => reasoning.isNotEmpty || reasoningInProgress;
}

// Bloque de razonamiento completo: <think>…</think> / <thinking>…</thinking>.
final RegExp _thinkBlock = RegExp(
  r'<(think|thinking)>([\s\S]*?)</\1>',
  caseSensitive: false,
);

// Apertura de razonamiento sin cierre (streaming a mitad de pensar).
final RegExp _thinkOpen = RegExp(
  r'<(think|thinking)>([\s\S]*)$',
  caseSensitive: false,
);

// Restos sueltos de etiquetas (cierres huérfanos por contenido malformado).
final RegExp _thinkTagResidue = RegExp(
  r'</?(think|thinking)>',
  caseSensitive: false,
);

// Delimitadores Harmony (gpt-oss): `<|start|>rol<|channel|>analysis<|message|>…`
// El canal `analysis` es razonamiento; `final`/`commentary` son respuesta.
final RegExp _harmonyAnalysisSegment = RegExp(
  r'<\|channel\|>analysis<\|message\|>([\s\S]*?)(<\|end\|>|<\|start\|>|$)',
  caseSensitive: false,
);

// Variante `<|think|>…` (cierre `<|/think|>`/`</think|>` opcional en streaming).
final RegExp _harmonyThinkBlock = RegExp(
  r'<\|think\|>([\s\S]*?)(<\|/think\|>|</think\|>|$)',
  caseSensitive: false,
);

// Cualquier resto del envelope Harmony: tokens de control, el rol que sigue a
// `<|start|>` y el nombre de canal que precede a `<|message|>`. Jamás debe
// pintarse crudo.
final RegExp _harmonyToken = RegExp(
  r'<\|start\|>[^<]*|<\|channel\|>[a-zA-Z_]+<\|message\|>|<\|[a-zA-Z_/]+\|>',
  caseSensitive: false,
);

/// Separa el razonamiento (`<think>…</think>`, `<thinking>…`) de la respuesta.
///
/// Soporta varios bloques (se concatenan), bloques vacíos y un bloque abierto
/// sin cerrar durante el streaming (todo lo que sigue a la apertura se trata
/// como razonamiento en curso). Si el texto no contiene la etiqueta, devuelve
/// la respuesta sin tocar.
///
/// También reconoce los delimitadores Harmony de gpt-oss: el canal
/// `<|channel|>analysis<|message|>…` y los bloques `<|think|>…` se tratan como
/// razonamiento, y el resto de tokens de control (`<|start|>`, `<|end|>`…) se
/// sanea para no pintarse crudo en la burbuja.
ReasoningSplit splitReasoning(String content) {
  // Atajo barato: sin ninguna etiqueta de razonamiento (apertura, cierre o
  // huérfana) ni token Harmony no hay nada que separar (caso del 99 %).
  if (!_thinkTagResidue.hasMatch(content) && !_harmonyToken.hasMatch(content)) {
    return ReasoningSplit(reasoning: '', answer: content);
  }

  final parts = <String>[];
  var inProgress = false;
  var answer = content;

  // Harmony (gpt-oss): el canal analysis y los bloques <|think|> son
  // razonamiento; si quedan abiertos al final del texto, el modelo sigue
  // pensando. Los demás tokens de control se eliminan de la respuesta.
  if (_harmonyToken.hasMatch(answer)) {
    answer = answer.replaceAllMapped(_harmonyAnalysisSegment, (m) {
      final inner = m.group(1)?.trim() ?? '';
      if (inner.isNotEmpty) parts.add(inner);
      if (m.group(2) == '') inProgress = true;
      return '';
    });
    answer = answer.replaceAllMapped(_harmonyThinkBlock, (m) {
      final inner = m.group(1)?.trim() ?? '';
      if (inner.isNotEmpty) parts.add(inner);
      if (m.group(2) == '') inProgress = true;
      return '';
    });
    answer = answer.replaceAll(_harmonyToken, '');
  }

  answer = answer.replaceAllMapped(_thinkBlock, (m) {
    final inner = m.group(2)?.trim() ?? '';
    if (inner.isNotEmpty) parts.add(inner);
    return '';
  });

  final open = _thinkOpen.firstMatch(answer);
  if (open != null) {
    final inner = open.group(2)?.trim() ?? '';
    if (inner.isNotEmpty) parts.add(inner);
    answer = answer.substring(0, open.start);
    inProgress = true;
  }

  // Limpia cualquier resto de etiqueta huérfana que jamás debe verse.
  answer = answer.replaceAll(_thinkTagResidue, '').trim();

  return ReasoningSplit(
    reasoning: parts.join('\n\n').trim(),
    answer: answer,
    reasoningInProgress: inProgress,
  );
}

/// Extrae el razonamiento ESTRUCTURADO que el backend entrega fuera del
/// `content` del mensaje (campos `reasoning_content`/`reasoning` al estilo
/// DeepSeek-reasoner, o la lista `reasoning_details` de OpenRouter). Es la
/// misma señal que el `<think>` inline, pero viajando por metadata: la UI lo
/// muestra como el bloque de razonamiento plegado habitual.
String structuredReasoningText(Map<String, dynamic> metadata) {
  final parts = <String>[];
  for (final key in const ['reasoning_content', 'reasoning']) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) parts.add(value.trim());
  }
  final details = metadata['reasoning_details'];
  if (details is List) {
    for (final item in details) {
      final text = item is Map ? (item['text'] ?? item['summary']) : item;
      if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
    }
  }
  return parts.join('\n\n');
}

/// Compone el razonamiento estructurado de la metadata del mensaje con el
/// `<think>` inline ya separado en [base]. Si no hay razonamiento estructurado
/// devuelve [base] intacta (cero cambios de comportamiento en el caso normal).
ReasoningSplit mergeStructuredReasoning(
  ReasoningSplit base,
  Map<String, dynamic> metadata,
) {
  final structured = structuredReasoningText(metadata);
  if (structured.isEmpty) return base;
  return ReasoningSplit(
    reasoning: base.reasoning.isEmpty
        ? structured
        : '$structured\n\n${base.reasoning}',
    answer: base.answer,
    reasoningInProgress: base.reasoningInProgress,
  );
}

// Encabezado ATX pegado al marcador: hasta 3 espacios de sangría, 1-6 '#' y a
// continuación una letra (no espacio, no otro '#', no dígito). Captura el caso
// `##Titulo` que CommonMark NO interpreta como encabezado, sin tocar `#1`,
// `#### ya correcto` ni hashtags numéricos.
final RegExp _gluedHeading = RegExp(
  r'^(\s{0,3})(#{1,6})([A-Za-zÁÉÍÓÚÜÑáéíóúüñ].*)$',
);
final RegExp _standaloneInlineCodeLine = RegExp(r'^`[^`\n]+`[.,:;]?\s*$');
final RegExp _numberedBoldHeadingWithTrailingCode = RegExp(
  r'^(\*\*\d+[.)]\s+.+?\*\*)\s+(`[^`\n]+`)\s*$',
);
final RegExp _atxHeadingWithTrailingCode = RegExp(
  r'^(\s{0,3}#{1,6}\s+.+?)\s+(`[^`\n]+`)\s*$',
);
final RegExp _approximationMarker = RegExp(r'(^|[^~])(?:~|≈)\s*(?=\d)');
final RegExp _adjacentInlineCodePunctuation = RegExp(r'`([,;])`');

String _polishInlineMarkdownLine(String line) {
  // Dos spans de código consecutivos necesitan aire tras la puntuación. Sin
  // él, flutter_markdown pinta fondos contiguos y parece que las rutas se han
  // fusionado (`keys`,`locks`).
  final spaced = line.replaceAllMapped(
    _adjacentInlineCodePunctuation,
    (match) => '`${match.group(1)} `',
  );

  // El modelo usa con frecuencia `~123` para "aproximadamente". En prosa se
  // presenta como una abreviatura legible; dentro de backticks se conserva el
  // byte exacto para no alterar rutas ni comandos que el usuario pueda copiar.
  final result = StringBuffer();
  int? codeDelimiterLength;
  var cursor = 0;
  while (cursor < spaced.length) {
    final tick = spaced.indexOf('`', cursor);
    if (tick < 0) {
      final tail = spaced.substring(cursor);
      result.write(
        codeDelimiterLength == null ? _polishProseSegment(tail) : tail,
      );
      break;
    }

    final segment = spaced.substring(cursor, tick);
    result.write(
      codeDelimiterLength == null ? _polishProseSegment(segment) : segment,
    );
    var runEnd = tick + 1;
    while (runEnd < spaced.length && spaced[runEnd] == '`') {
      runEnd++;
    }
    final runLength = runEnd - tick;
    result.write(spaced.substring(tick, runEnd));
    if (codeDelimiterLength == null) {
      codeDelimiterLength = runLength;
    } else if (codeDelimiterLength == runLength) {
      codeDelimiterLength = null;
    }
    cursor = runEnd;
  }
  return result.toString();
}

String _polishProseSegment(String value) => value.replaceAllMapped(
  _approximationMarker,
  (match) => '${match.group(1)}aprox. ',
);

/// Retoques conservadores del Markdown del asistente, fuera de bloques de
/// código. Inserta el espacio que falta tras los `#` de un encabezado pegado
/// (`##Titulo` → `## Titulo`) y conserva como bloque una línea formada solo
/// por código inline. Esto evita que CommonMark pegue una ruta como
/// `` `/home/backups` `` al encabezado anterior y la parta de forma arbitraria.
String tidyAssistantMarkdown(String text) {
  if (text.isEmpty) return text;
  final lines = text.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    // CommonMark también admite bloques de código sin valla mediante cuatro
    // espacios (o tab). No se debe tipografiar ni reescribir su contenido.
    if (lines[i].startsWith('    ') || lines[i].startsWith('\t')) continue;
    lines[i] = _polishInlineMarkdownLine(lines[i]);
    final m = _gluedHeading.firstMatch(lines[i]);
    if (m != null) {
      lines[i] = '${m.group(1)}${m.group(2)} ${m.group(3)}';
    }
    final trailingCode =
        _numberedBoldHeadingWithTrailingCode.firstMatch(lines[i]) ??
        _atxHeadingWithTrailingCode.firstMatch(lines[i]);
    if (trailingCode != null) {
      lines[i] = trailingCode.group(1)!;
      lines.insert(i + 1, trailingCode.group(2)!);
    }
  }

  final separated = <String>[];
  inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
    }
    final standaloneCode =
        !inFence && line == trimmed && _standaloneInlineCodeLine.hasMatch(line);
    if (standaloneCode &&
        separated.isNotEmpty &&
        separated.last.trim().isNotEmpty) {
      separated.add('');
    }
    separated.add(line);
    if (standaloneCode &&
        i + 1 < lines.length &&
        lines[i + 1].trim().isNotEmpty) {
      separated.add('');
    }
  }
  return separated.join('\n');
}

// HTML inline que algunos modelos insertan en la respuesta. El render Markdown
// no tiene builders HTML y lo descartaría en silencio, así que convertimos los
// tags comunes a su equivalente de texto plano antes de parsear.
final RegExp _inlineHtmlBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _inlineHtmlDetailsTag = RegExp(
  r'</?details(\s[^>]*)?>',
  caseSensitive: false,
);
final RegExp _inlineHtmlSummaryTag = RegExp(
  r'</?summary(\s[^>]*)?>',
  caseSensitive: false,
);

/// Fallback conservador para el HTML inline que `MarkdownBody` descarta sin
/// `extensionSet` ni builders. Convierte `<br>` en saltos de línea y desenvuelve
/// `<details>`/`<summary>` conservando su contenido como texto plano. NO es un
/// engine HTML: el resto de etiquetas se deja intacto (ante la duda, no tocar).
/// Respeta vallas ``` y spans de código inline, donde un tag es un literal.
String flattenInlineHtml(String text) {
  if (!text.contains('<')) return text;
  final lines = text.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    lines[i] = _flattenInlineHtmlLine(lines[i]);
  }
  return lines.join('\n');
}

String _flattenInlineHtmlLine(String line) {
  if (!line.contains('<')) return line;
  // Alterna segmentos fuera/dentro de código inline (separados por backtick):
  // solo se transforman los pares, como en escapePathGlobs.
  final segments = line.split('`');
  for (var i = 0; i < segments.length; i += 2) {
    var segment = segments[i];
    if (!segment.contains('<')) continue;
    segment = segment
        .replaceAll(_inlineHtmlBreak, '\n')
        .replaceAll(_inlineHtmlDetailsTag, '\n')
        .replaceAll(_inlineHtmlSummaryTag, '');
    segments[i] = segment;
  }
  final out = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    out.write(segments[i]);
    if (i < segments.length - 1) out.write('`');
  }
  return out.toString();
}
