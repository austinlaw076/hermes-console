/// Capa de presentación semántica para la respuesta del asistente.
///
/// Puramente de presentación: igual que [splitReasoning]/[tidyAssistantMarkdown],
/// NO muta el contenido real guardado por `ActiveChatService`. Su objetivo es que
/// la respuesta sea fácil de escanear AUNQUE el modelo emita Markdown mediocre o
/// prosa plana, sin depender de que el LLM escriba perfecto.
///
/// Tres transformaciones, todas conservadoras (ante la duda, no tocar):
///  1. [enhanceHeadings]  — promueve líneas-etiqueta (`Estado:`, `Conclusión:`…)
///     a encabezados Markdown reales (`## Estado`).
///  2. [splitContentBlocks] — extrae los hallazgos (`Problema:`, `Warning:`…) a
///     bloques de callout diferenciados, dejando el resto como Markdown normal.
///  3. [enhanceEvidence]  — realza evidencia técnica (rutas) como código inline.
///
/// Idempotentes: aplicarlas dos veces no cambia el resultado. Si no hay nada que
/// reconocer, devuelven el texto intacto (cero cambios en el caso normal).
library;

// ── 0. Comandos de terminal sin Markdown ────────────────────────────────────

/// Convierte líneas que son inequívocamente comandos de terminal en vallas de
/// código copiables. Algunos modelos locales responden `dir` o
/// `Get-ChildItem` como prosa plana; CommonMark no puede distinguirlo y la UI
/// pierde el botón de copiar. Esta capa solo actúa sobre líneas completas y
/// reconoce formas conservadoras de CMD, PowerShell y shell.
String enhanceCommandBlocks(String text) {
  if (text.isEmpty) return text;
  final src = text.split('\n');
  final out = <String>[];
  var inFence = false;
  var changed = false;
  var i = 0;
  while (i < src.length) {
    final line = src[i];
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      i++;
      continue;
    }
    final lang = inFence ? null : _commandLanguage(line);
    if (lang == null) {
      out.add(line);
      i++;
      continue;
    }

    if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
    out.add('```$lang');
    while (i < src.length && _commandLanguage(src[i]) == lang) {
      out.add(src[i].trim());
      i++;
    }
    out.add('```');
    if (i < src.length && src[i].trim().isNotEmpty) out.add('');
    changed = true;
  }
  return changed ? out.join('\n') : text;
}

final RegExp _powerShellCommand = RegExp(
  r'^(?:(?:PS\s+[^>]+>\s*)|(?:&\s+))?(?:Get|Set|New|Remove|Copy|Move|Rename|Test|Select|Where|ForEach|Start|Stop|Restart|Enable|Disable|Invoke|Export|Import|ConvertTo|ConvertFrom|Measure|Format|Write|Read|Clear|Resolve|Join|Split|Add|Update)-[A-Za-z][\w-]*(?:\s+.*)?$',
  caseSensitive: false,
);
final RegExp _cmdCommand = RegExp(
  r'^(?:dir|tree|cls|ipconfig|netstat|tasklist|systeminfo|hostname|whoami)(?:\s+.*)?$',
  caseSensitive: false,
);
final RegExp _cmdCommandWithArgs = RegExp(
  r'^(?:cd|chdir|type|copy|xcopy|robocopy|move|del|erase|ren|rename|mkdir|md|rmdir|rd|where|findstr|taskkill|winget|choco|sfc|dism|reg|sc|net|set|echo|attrib|fc|comp|schtasks|wmic)\s+\S.*$',
  caseSensitive: false,
);
final RegExp _shellCommand = RegExp(
  r'^(?:(?:\$|#)\s+)?(?:sudo\s+)?(?:ls|pwd|cd|find|grep|cat|head|tail|cp|mv|rm|mkdir|rmdir|chmod|chown|curl|wget|ssh|scp|rsync|git|docker|kubectl|flutter|dart|npm|pnpm|yarn|python3?|pip3?|systemctl|journalctl)(?:\s+.*)?$',
  caseSensitive: false,
);

String? _commandLanguage(String raw) {
  // Solo líneas completas sin sangría/lista/Markdown. Ante cualquier duda,
  // conserva exactamente la respuesta original.
  if (raw.isEmpty || raw.length > 240 || raw.trim() != raw) return null;
  if (RegExp(r'^(?:[-*+]|\d+[.)]|>|#{1,6}\s|```|~~~)').hasMatch(raw)) {
    return null;
  }
  if (raw.contains('`') || RegExp(r'[.!?]$').hasMatch(raw)) return null;
  if (_powerShellCommand.hasMatch(raw) ||
      RegExp(
        r'^(?:\$env:|\$[A-Za-z_]\w*\s*=|\.\\\S+\.ps1(?:\s|$))',
      ).hasMatch(raw)) {
    return 'powershell';
  }
  if (RegExp(r'^[A-Za-z]:\\[^>]*>\s*\S').hasMatch(raw) ||
      _cmdCommand.hasMatch(raw) ||
      _cmdCommandWithArgs.hasMatch(raw)) {
    return 'bat';
  }
  if (_shellCommand.hasMatch(raw) || RegExp(r'^\./\S+').hasMatch(raw)) {
    return 'bash';
  }
  return null;
}

// ── 1. Encabezados semánticos ────────────────────────────────────────────────

/// Etiquetas de sección reconocidas (ES + EN). Una línea formada SOLO por una de
/// estas etiquetas seguida de `:` se convierte en encabezado `##`.
///
/// Importante: `Problemas` (plural, una sección que enumera) es encabezado; el
/// singular `Problema` (un hallazgo concreto) NO está aquí: lo captura el callout.
const Set<String> _headingLabels = {
  // Español
  'estado', 'resultado', 'resultados', 'problemas', 'observaciones',
  'conclusión', 'conclusion', 'conclusiones', 'recomendación', 'recomendacion',
  'recomendaciones', 'siguientes pasos', 'próximos pasos', 'proximos pasos',
  'resumen', 'resumen ejecutivo', 'contexto', 'análisis', 'analisis',
  'solución', 'solucion', 'causa', 'pasos', 'detalles', 'notas',
  'verificación', 'verificacion', 'hallazgos', 'objetivo', 'objetivos',
  // Inglés
  'status', 'result', 'results', 'summary', 'overview', 'observations',
  'recommendation', 'recommendations', 'next steps', 'context',
  'analysis', 'solution', 'cause', 'steps', 'details', 'notes',
  'verification', 'findings', 'goal', 'goals',
};

final RegExp _fenceLine = RegExp(r'^\s*(```|~~~)');
// Envoltura de énfasis al principio/fin (negrita/cursiva) para desnudar la
// etiqueta: `**Conclusión:**` / `__Estado:__` → `Conclusión:` / `Estado:`.
final RegExp _emphLead = RegExp(r'^[\*_\s]+');
final RegExp _emphTrail = RegExp(r'[\*_\s]+$');

/// Promueve líneas-etiqueta conocidas (`Estado:`) a encabezados `## Estado`.
/// Respeta los bloques de código y no toca líneas que ya son encabezados.
///
/// Conservador: la etiqueta debe vivir sola en su línea (sin contenido tras los
/// dos puntos), así `Estado: todo bien` se queda como prosa intacta.
String enhanceHeadings(String text) {
  if (text.isEmpty) return text;
  final lines = text.split('\n');
  final hasContentFrom = List<bool>.filled(lines.length + 1, false);
  for (var i = lines.length - 1; i >= 0; i--) {
    hasContentFrom[i] = hasContentFrom[i + 1] || lines[i].trim().isNotEmpty;
  }
  var inFence = false;
  var changed = false;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (_fenceLine.hasMatch(raw)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    // Sangría de 4+ espacios = bloque de código indentado: no tocar.
    if (RegExp(r'^\s{4,}\S').hasMatch(raw)) continue;
    var s = raw.trim();
    if (s.isEmpty || s.startsWith('#')) continue; // ya es encabezado
    // Desnuda la negrita/cursiva envolvente.
    s = s.replaceFirst(_emphLead, '').replaceFirst(_emphTrail, '');
    if (s.endsWith(':')) {
      // Caso 1: línea-etiqueta `Label:`.
      final label = s.substring(0, s.length - 1).trim();
      final level = label.isEmpty ? 0 : _headingLevelFor(label);
      if (level != 0) {
        final display = '${label[0].toUpperCase()}${label.substring(1)}';
        lines[i] = level == 2 ? '## $display' : '### $display';
        changed = true;
      }
      continue;
    }
    // Caso 2: título aislado SIN dos puntos (p.ej. "Resumen honesto"). Red de
    // seguridad para cuando el modelo no marca la sección; muy acotado: línea
    // corta, sola por arriba, que introduce contenido más abajo.
    final prevBlank = i == 0 || lines[i - 1].trim().isEmpty;
    if (prevBlank && _looksLikeBareTitle(s) && hasContentFrom[i + 1]) {
      lines[i] = '### ${s[0].toUpperCase()}${s.substring(1)}';
      changed = true;
    }
  }
  return changed ? lines.join('\n') : text;
}

/// ¿Una línea parece un título "desnudo" (sin `:` ni `#`)? Conservador: corta,
/// empieza por mayúscula, sin números/rutas/código y sin terminar como frase.
bool _looksLikeBareTitle(String s) {
  if (s.length > 32) return false;
  if (s.contains('`') || s.contains('/') || s.contains(':')) return false;
  if (RegExp(r'[.,;!?]$').hasMatch(s)) return false;
  if (!RegExp(r'^[A-ZÁÉÍÓÚÜÑ]').hasMatch(s)) return false;
  if (RegExp(r'\d').hasMatch(s)) return false;
  return s.split(RegExp(r'\s+')).length <= 4;
}

/// Decide qué encabezado merece una línea-etiqueta `Etiqueta:` (ya sin el `:`):
///  - `2` → sección principal conocida (whitelist: Estado, Conclusión…).
///  - `3` → subsección genérica: una etiqueta corta tipo `Puerto/API`,
///    `Restart medido`, `Dice`… que el modelo inventa y que sin esto quedaría
///    como prosa indistinguible (la causa nº1 del "todo desordenado").
///  - `0` → no es encabezado (dejar como prosa).
///
/// La regla genérica mira la FORMA, no una lista fija: línea corta, sin pinta de
/// oración ni de URL/código. Conservadora para no promover prosa por error.
int _headingLevelFor(String label) {
  if (_headingLabels.contains(label.toLowerCase())) return 2;
  if (label.length > 40) return 0;
  // Descarta lo que parece código, URL o una etiqueta con `:` interno.
  if (label.contains(':') || label.contains('//') || label.contains('`')) {
    return 0;
  }
  // Debe empezar por letra (no viñeta, número ni símbolo).
  if (!RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(label)) return 0;
  // Si termina como una frase, es prosa, no una etiqueta.
  if (RegExp(r'[.,;!?]$').hasMatch(label)) return 0;
  // Una etiqueta es corta; una oración no.
  if (label.split(RegExp(r'\s+')).length > 5) return 0;
  return 3;
}

// ── 1b. Listas implícitas ────────────────────────────────────────────────────

/// Máximo de palabras para considerar una línea un "item" de lista (no prosa).
/// Hasta 10 cubre items algo más largos ("si vas a pedir algo caro, empieza
/// limpia"); la prosa se descarta aparte por terminar como oración.
const int _maxItemWords = 10;

/// Convierte "listas implícitas" en viñetas reales: una línea que termina en `:`
/// seguida de ≥2 líneas cortas (sin viñeta y sin pinta de oración) se interpreta
/// como una lista y cada línea pasa a `- item`. Es una causa principal del "muro
/// de texto": el modelo enumera con saltos de línea simples y sin marcador, y
/// CommonMark los funde en un único párrafo denso e ilegible.
///
/// Conservador: exige al menos DOS items consecutivos y cortos; respeta el código
/// y no toca lo que ya es lista/encabezado.
String enhanceImplicitLists(String text) {
  if (text.isEmpty || !text.contains(':')) return text;
  final src = text.split('\n');
  final out = <String>[];
  var inFence = false;
  var changed = false;
  var i = 0;
  while (i < src.length) {
    final line = src[i];
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      i++;
      continue;
    }
    final header = line.trimRight();
    if (!inFence &&
        header.endsWith(':') &&
        !header.trimLeft().startsWith('#')) {
      // Salta la(s) línea(s) en blanco entre el "header:" y los ítems: el modelo
      // casi siempre mete una línea vacía ahí ("Mejor:\n\nitem1\nitem2…"), y sin
      // esto la lista NO se detectaba → quedaba como líneas sueltas sin viñeta
      // (la causa principal del "se ve mal/desestructurado" en el chat).
      var start = i + 1;
      while (start < src.length && src[start].trim().isEmpty) {
        start++;
      }
      var j = start;
      while (j < src.length && _looksLikeItem(src[j])) {
        j++;
      }
      if (j - start >= 2) {
        out.add(line);
        out.add(''); // separa el "header:" de la lista para CommonMark
        for (var k = start; k < j; k++) {
          out.add('- ${src[k].trim()}');
        }
        changed = true;
        i = j;
        continue;
      }
    }
    out.add(line);
    i++;
  }
  return changed ? out.join('\n') : text;
}

bool _looksLikeItem(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  // Ya es viñeta/numerada/encabezado/cita/valla, o va indentado (código).
  if (RegExp(r'^([-*+]|\d+[.)]|#|>|```|~~~)').hasMatch(t)) return false;
  if (line.startsWith('    ') || line.startsWith('\t')) return false;
  if (t.endsWith(':')) return false; // probablemente otro header de sección
  // Una línea que termina como ORACIÓN (. ! ?) es prosa, no un item: así podemos
  // permitir items algo más largos sin tragarnos párrafos por error.
  if (RegExp(r'[.!?]$').hasMatch(t)) return false;
  // Una oración no es un item: limita por longitud.
  if (t.split(RegExp(r'\s+')).length > _maxItemWords) return false;
  return true;
}

// ── 1c. Listas de definición (clave: descripción) ────────────────────────────

// Línea con forma `clave: descripción`: clave de 1-3 palabras (admite rutas
// `~//.` en la clave), dos puntos, y una descripción no vacía en la misma línea.
final RegExp _defLine = RegExp(
  r'^([A-Za-zÁÉÍÓÚÜÑáéíóúüñ~/][\w./~+-]*(?: [A-Za-zÁÉÍÓÚÜÑáéíóúüñ][\w./~+-]*){0,2}):\s+(\S.*)$',
);

/// Agrupa ≥2 líneas consecutivas con forma `clave: descripción` en una lista de
/// viñetas `- **clave:** descripción`. Estos "diccionarios" en prosa (típicos de
/// LLM) son otra causa del muro de texto. NO toca las etiquetas de hallazgo
/// (`Problema:`/`Warning:`/`Error:`…), que deja para el callout.
String enhanceDefinitionLists(String text) {
  if (text.isEmpty || !text.contains(':')) return text;
  final src = text.split('\n');
  final out = <String>[];
  var inFence = false;
  var changed = false;
  var i = 0;
  while (i < src.length) {
    final line = src[i];
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      i++;
      continue;
    }
    final m = (!inFence && !line.startsWith(' ') && !line.startsWith('\t'))
        ? _defLine.firstMatch(line.trim())
        : null;
    if (m != null && !_isCalloutKey(m.group(1)!)) {
      final items = <List<String>>[];
      var j = i;
      while (j < src.length) {
        if (src[j].startsWith(' ') || src[j].startsWith('\t')) break;
        if (_fenceLine.hasMatch(src[j])) break;
        final mj = _defLine.firstMatch(src[j].trim());
        if (mj == null || _isCalloutKey(mj.group(1)!)) break;
        items.add([mj.group(1)!, mj.group(2)!]);
        j++;
      }
      if (items.length >= 2) {
        for (final it in items) {
          out.add('- **${it[0]}:** ${it[1]}');
        }
        changed = true;
        i = j;
        continue;
      }
    }
    out.add(line);
    i++;
  }
  return changed ? out.join('\n') : text;
}

bool _isCalloutKey(String key) =>
    _calloutLabels.containsKey(key.toLowerCase().trim());

// ── 2. Hallazgos → callouts ──────────────────────────────────────────────────

/// Tipo de hallazgo, que determina color e icono del callout.
enum CalloutKind { warning, error }

/// Etiquetas de hallazgo → tipo. El color final lo decide el tema (warning/error
/// ya existen en todas las paletas: no se introducen colores nuevos).
const Map<String, CalloutKind> _calloutLabels = {
  // Error (rojo del tema)
  'error': CalloutKind.error,
  'errores': CalloutKind.error,
  'fallo': CalloutKind.error,
  'fallos': CalloutKind.error,
  'crítico': CalloutKind.error,
  'critico': CalloutKind.error,
  'critical': CalloutKind.error,
  // Advertencia / problema (ámbar del tema)
  'warning': CalloutKind.warning,
  'warnings': CalloutKind.warning,
  'advertencia': CalloutKind.warning,
  'advertencias': CalloutKind.warning,
  'aviso': CalloutKind.warning,
  'avisos': CalloutKind.warning,
  'precaución': CalloutKind.warning,
  'precaucion': CalloutKind.warning,
  'caution': CalloutKind.warning,
  'problema': CalloutKind.warning,
  'issue': CalloutKind.warning,
  'issues': CalloutKind.warning,
  'conflicto': CalloutKind.warning,
  'conflictos': CalloutKind.warning,
  'inconsistencia': CalloutKind.warning,
  'inconsistencias': CalloutKind.warning,
  'bug': CalloutKind.warning,
  'bugs': CalloutKind.warning,
};

// Inicio de hallazgo: la etiqueta arranca la línea (sin sangría ni viñeta para
// no tragarse listas), opcional `**`, y un separador `:`/`-`/`–`.
final RegExp _calloutLine = RegExp(
  r'^(?:\*\*|__)?\s*([\wáéíóúüñÁÉÍÓÚÜÑ]+)\s*(?:\*\*|__)?\s*[:\-–]\s*(.*)$',
);

/// Un fragmento ordenado de la respuesta: Markdown normal o un callout.
sealed class ContentBlock {
  const ContentBlock();
}

/// Markdown corriente (párrafos, listas, código, tablas…). Se renderiza con el
/// mismo motor de siempre.
class MarkdownContentBlock extends ContentBlock {
  final String text;
  const MarkdownContentBlock(this.text);
}

/// Hallazgo destacado como tarjeta diferenciada.
class CalloutContentBlock extends ContentBlock {
  final CalloutKind kind;
  final String title;
  final String body;
  const CalloutContentBlock({
    required this.kind,
    required this.title,
    required this.body,
  });
}

/// Parte [text] en una secuencia ordenada de bloques Markdown y callouts.
///
/// Un hallazgo se reconoce cuando una línea (fuera de bloques de código, sin
/// sangría ni viñeta) empieza por una etiqueta conocida (`Problema:`, `Warning:`)
/// y su cuerpo se extiende hasta la siguiente línea en blanco. Si no hay ningún
/// hallazgo, devuelve un único [MarkdownContentBlock] con el texto intacto.
List<ContentBlock> splitContentBlocks(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final blocks = <ContentBlock>[];
  final buffer = <String>[];
  var inFence = false;

  void flushMarkdown() {
    if (buffer.isEmpty) return;
    final joined = buffer.join('\n').trim();
    if (joined.isNotEmpty) blocks.add(MarkdownContentBlock(joined));
    buffer.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      buffer.add(line);
      i++;
      continue;
    }
    final callout = inFence ? null : _matchCallout(line);
    if (callout == null) {
      buffer.add(line);
      i++;
      continue;
    }
    // Hallazgo: cierra el Markdown acumulado y absorbe el párrafo del hallazgo
    // (hasta línea en blanco o nueva valla de código).
    flushMarkdown();
    final bodyLines = <String>[callout.firstBodyLine];
    var j = i + 1;
    while (j < lines.length &&
        lines[j].trim().isNotEmpty &&
        !_fenceLine.hasMatch(lines[j]) &&
        _matchCallout(lines[j]) == null) {
      bodyLines.add(lines[j]);
      j++;
    }
    blocks.add(
      CalloutContentBlock(
        kind: callout.kind,
        title: callout.title,
        body: bodyLines.join('\n').trim(),
      ),
    );
    i = j;
  }
  flushMarkdown();
  return blocks;
}

class _CalloutMatch {
  final CalloutKind kind;
  final String title;
  final String firstBodyLine;
  _CalloutMatch(this.kind, this.title, this.firstBodyLine);
}

_CalloutMatch? _matchCallout(String line) {
  // No tratar encabezados, citas ni elementos de lista como hallazgos.
  final t = line.trimLeft();
  if (t.isEmpty || t.startsWith('#') || t.startsWith('>')) return null;
  if (RegExp(r'^[-*+]\s').hasMatch(t)) return null;
  if (line.startsWith(' ') || line.startsWith('\t')) return null; // sangría
  final m = _calloutLine.firstMatch(line);
  if (m == null) return null;
  final label = m.group(1)!.toLowerCase();
  final kind = _calloutLabels[label];
  if (kind == null) return null;
  // Un cuerpo es obligatorio: `Error:` sin nada detrás se deja como prosa para
  // no fabricar tarjetas vacías a mitad de streaming.
  final body = m.group(2)!.trim();
  if (body.isEmpty) return null;
  final title = label[0].toUpperCase() + label.substring(1);
  return _CalloutMatch(kind, title, body);
}

// ── 3. Evidencia técnica ─────────────────────────────────────────────────────

// Ruta absoluta (`/a/b`) o de home (`~/a/b`) con al menos dos segmentos, para no
// capturar un `/` suelto ni fracciones tipo `5/6`. El look-behind evita que un
// carácter de palabra anterior (p. ej. `http:/`) dispare el realce.
final RegExp _pathToken = RegExp(
  r'(?<![\w/~.])(~/[\w.+\-/]+|/[\w.+\-]+(?:/[\w.+\-]*)+/?)',
);

/// Realza evidencia técnica (rutas Linux/`~`) envolviéndola en código inline,
/// para que `/home/user/.hermes/memory/` no se confunda con prosa.
///
/// Conservador: solo rutas inequívocas; NO toca URLs (ya se ven como enlaces),
/// ni contenido dentro de código (vallas ``` o spans `…`).
String enhanceEvidence(String text) {
  if (text.isEmpty || !text.contains('/')) return text;
  final out = StringBuffer();
  var inFence = false;
  final lines = text.split('\n');
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      out.write(line);
      if (li < lines.length - 1) out.write('\n');
      continue;
    }
    if (inFence) {
      out.write(line);
      if (li < lines.length - 1) out.write('\n');
      continue;
    }
    // Procesa solo los segmentos fuera de código inline (índices pares); los
    // impares son `…` y se dejan intactos, reinsertando los backticks.
    final segments = line.split('`');
    for (var s = 0; s < segments.length; s++) {
      out.write(s.isEven ? _wrapPaths(segments[s]) : segments[s]);
      if (s < segments.length - 1) out.write('`');
    }
    if (li < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

// Puntuación que cierra una frase y NO forma parte de la ruta, para no meterla
// dentro del código inline (`…data.` → `` `…data`. ``). La `/` final sí es ruta.
final RegExp _trailingPunct = RegExp(r'[.,;:!?)\]]+$');

String _wrapPaths(String segment) {
  if (!segment.contains('/')) return segment;
  return segment.replaceAllMapped(_pathToken, (m) {
    var token = m.group(0)!;
    var trail = '';
    final tp = _trailingPunct.firstMatch(token);
    if (tp != null) {
      trail = token.substring(tp.start);
      token = token.substring(0, tp.start);
    }
    if (token.length < 3) return m.group(0)!; // demasiado corto: déjalo igual
    return '`$token`$trail';
  });
}
