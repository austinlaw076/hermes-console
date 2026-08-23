/// Proyección conservadora de un cierre del asistente a sugerencias tocables.
///
/// Solo transforma un cierre accionable explícito con una oferta final o con
/// 1–3 opciones. Las listas normales, las respuestas técnicas y los errores se
/// conservan.
class AssistantSuggestionsProjection {
  const AssistantSuggestionsProjection({
    required this.body,
    this.suggestions = const [],
  });

  final String body;
  final List<String> suggestions;

  bool get hasSuggestions => suggestions.isNotEmpty;
}

final _suggestionIntro = RegExp(
  r'^\s*(?:#{1,4}\s*)?[¿?]?\s*(?:'
  r'si\s+quieres|si\s+te\s+sirve|quieres\s+que|también\s+puedo|'
  r'puedo\s+también|te\s+puedo|puedo\s+ayudarte|como\s+siguiente\s+paso|'
  r'te\s+propongo|puedes\s+elegir|elige\s+(?:una|uno)|'
  r'qué\s+prefieres|cuál\s+prefieres|dime\s+cuál|'
  r'if\s+you\s+want|if\s+useful|would\s+you\s+like|i\s+can\s+also|'
  r'as\s+a\s+next\s+step|you\s+can\s+choose|choose\s+one|'
  r'which\s+do\s+you\s+prefer|tell\s+me\s+which'
  r')\b.*(?:[:：]|[?¿])\s*$',
  caseSensitive: false,
);
final _suggestionBullet = RegExp(r'^\s*(?:[-*+•·–—]|\d+[.)])\s+(.+?)\s*$');
final _danglingConnector = RegExp(
  r'^\s*[.,;:]?\s*(?:o|u|or)\s*[.,;:]?\s*$',
  caseSensitive: false,
);

final _technicalResponse = RegExp(
  r'(?:^|\n)\s*(?:#{1,6}\s*)?'
  r'(?:error|exception|traceback|stack\s+trace|fatal(?:\s+error)?|'
  r'excepción|fallo(?:\s+técnico)?)\s*(?::|$)',
  caseSensitive: false,
);

final _unsafeSuggestion = RegExp(
  r'(?:https?://|www\.|```|~~~|'
  r'\b(?:error|exception|traceback|stack\s+trace|fatal)\b)',
  caseSensitive: false,
);

final _inlineOfferPrefix = RegExp(
  r'^(?:si\s+quieres|if\s+you\s+want)\s*[,;:]\s+(.+)$',
  caseSensitive: false,
);
final _inlineOfferLead = RegExp(
  r'^(?:en\s+el\s+siguiente\s+paso|a\s+continuaci[oó]n)\s*,?\s*',
  caseSensitive: false,
);
final _englishInlineOfferLead = RegExp(
  r'^(?:in\s+the\s+next\s+step|next)\s*,?\s*',
  caseSensitive: false,
);
final _terminalSeparator = RegExp(
  r'^\s*(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,}|[─—]{3,})\s*$',
);

const _spanishOfferVerbs = <String, String>{
  'preparo': 'Prepara',
  'hago': 'Haz',
  'dejo': 'Deja',
  'creo': 'Crea',
  'genero': 'Genera',
  'resumo': 'Resume',
  'reviso': 'Revisa',
  'explico': 'Explica',
  'convierto': 'Convierte',
  'añado': 'Añade',
  'implemento': 'Implementa',
  'preparar': 'Prepara',
  'hacer': 'Haz',
  'dejar': 'Deja',
  'crear': 'Crea',
  'generar': 'Genera',
  'resumir': 'Resume',
  'revisar': 'Revisa',
  'explicar': 'Explica',
  'convertir': 'Convierte',
  'añadir': 'Añade',
  'implementar': 'Implementa',
};

const _englishOfferVerbs = <String, String>{
  'prepare': 'Prepare',
  'make': 'Make',
  'create': 'Create',
  'generate': 'Generate',
  'summarize': 'Summarize',
  'review': 'Review',
  'explain': 'Explain',
  'convert': 'Convert',
  'add': 'Add',
  'implement': 'Implement',
};

AssistantSuggestionsProjection projectAssistantSuggestions(String markdown) {
  final trimmed = markdown.trimRight();
  if (trimmed.isEmpty) {
    return const AssistantSuggestionsProjection(body: '');
  }
  if (trimmed.contains('```') ||
      trimmed.contains('~~~') ||
      _technicalResponse.hasMatch(trimmed)) {
    return AssistantSuggestionsProjection(body: trimmed);
  }

  final lines = trimmed.split('\n');
  final inlineOffer = _projectTerminalInlineOffer(lines);
  if (inlineOffer != null) return inlineOffer;

  var introIndex = -1;
  for (var index = lines.length - 1; index >= 0; index--) {
    if (_suggestionIntro.hasMatch(lines[index])) {
      final tailLines = lines
          .skip(index)
          .where((line) => line.trim().isNotEmpty)
          .length;
      if (tailLines > 6) continue;
      introIndex = index;
      break;
    }
  }
  if (introIndex < 0) {
    return AssistantSuggestionsProjection(body: trimmed);
  }

  final suggestions = <String>[];
  StringBuffer? current;
  for (final line in lines.skip(introIndex + 1)) {
    if (line.trim().isEmpty) continue;
    // Algunos modelos dejan el conector final en una línea propia (".o").
    // No debe acabar como Markdown suelto ni contaminar el último chip.
    if (_danglingConnector.hasMatch(line)) continue;
    final bullet = _suggestionBullet.firstMatch(line);
    if (bullet != null) {
      if (current != null) {
        suggestions.add(_cleanSuggestion(current.toString()));
      }
      current = StringBuffer(bullet.group(1)!);
      continue;
    }
    // Texto libre tras una opción suele ser una conclusión normal, no parte
    // del botón. Fallamos cerrado para no ocultarlo dentro de un chip.
    return AssistantSuggestionsProjection(body: trimmed);
  }
  if (current != null) suggestions.add(_cleanSuggestion(current.toString()));

  suggestions.removeWhere((value) => value.isEmpty);
  if (suggestions.isEmpty ||
      suggestions.length > 3 ||
      suggestions.any(
        (value) => value.length > 180 || _unsafeSuggestion.hasMatch(value),
      )) {
    return AssistantSuggestionsProjection(body: trimmed);
  }

  return AssistantSuggestionsProjection(
    body: _bodyBeforeSuggestion(lines, introIndex),
    suggestions: List.unmodifiable(suggestions),
  );
}

AssistantSuggestionsProjection? _projectTerminalInlineOffer(
  List<String> lines,
) {
  var paragraphStart = lines.length - 1;
  while (paragraphStart > 0 && lines[paragraphStart - 1].trim().isNotEmpty) {
    paragraphStart--;
  }
  final paragraphLines = lines.skip(paragraphStart).toList(growable: false);
  if (paragraphLines.isEmpty ||
      paragraphLines.any(
        (line) => line.trimLeft().startsWith(RegExp(r'[-*+•·–—#>|`]')),
      )) {
    return null;
  }

  final paragraph = paragraphLines
      .map((line) => line.trim())
      .join(' ')
      .trim()
      .replaceFirst(RegExp(r'[.!?…]+\s*$'), '');
  if (paragraph.isEmpty ||
      paragraph.length > 520 ||
      _unsafeSuggestion.hasMatch(paragraph)) {
    return null;
  }
  final prefix = _inlineOfferPrefix.firstMatch(paragraph);
  if (prefix == null) return null;

  final suggestion = _normalizeInlineOffer(prefix.group(1)!);
  if (suggestion == null ||
      suggestion.length > 180 ||
      _unsafeSuggestion.hasMatch(suggestion)) {
    return null;
  }
  return AssistantSuggestionsProjection(
    body: _bodyBeforeSuggestion(lines, paragraphStart),
    suggestions: [suggestion],
  );
}

String? _normalizeInlineOffer(String value) {
  var clause = value.trim().replaceFirst(RegExp(r'[.!?…]+\s*$'), '');
  clause = clause.replaceFirst(_inlineOfferLead, '');
  final spanish = RegExp(
    r'^(?:(?:yo\s+)?te\s+|(?:yo\s+)?|puedo\s+)'
    r'(preparo|hago|dejo|creo|genero|resumo|reviso|explico|convierto|añado|implemento|'
    r'preparar(?:te)?|hacer(?:te)?|dejar(?:te)?|crear(?:te)?|generar(?:te)?|'
    r'resumir(?:te)?|revisar(?:te)?|explicar(?:te)?|convertir(?:te)?|añadir(?:te)?|'
    r'implementar)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(clause);
  if (spanish != null) {
    final rawVerb = spanish.group(1)!.toLowerCase();
    final verb = rawVerb.endsWith('te')
        ? rawVerb.substring(0, rawVerb.length - 2)
        : rawVerb;
    final imperative = _spanishOfferVerbs[verb];
    if (imperative == null) return null;
    final object = _compactOfferObject(spanish.group(2)!);
    return object.isEmpty ? null : '$imperative $object';
  }

  clause = clause.replaceFirst(_englishInlineOfferLead, '');
  final english = RegExp(
    r'^(?:i\s+can\s+)(prepare|make|create|generate|summarize|review|explain|convert|add|implement)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(clause);
  if (english == null) return null;
  final imperative = _englishOfferVerbs[english.group(1)!.toLowerCase()];
  final object = _compactOfferObject(english.group(2)!);
  return imperative == null || object.isEmpty ? null : '$imperative $object';
}

String _compactOfferObject(String value) {
  var clean = _cleanSuggestion(value);
  // Una oferta larga suele añadir variantes entre paréntesis y una segunda
  // acción. La pill debe expresar la acción principal, no copiar todo el
  // párrafo del asistente dentro de un botón enorme.
  clean = clean.replaceFirst(RegExp(r'\s+\([^\n()]{1,180}\).*$'), '');
  clean = clean.replaceFirst(
    RegExp(
      r'\s+(?:y|and)\s+(?:el|la|los|las|the|a|an)\s+.+$',
      caseSensitive: false,
    ),
    '',
  );
  return clean.trim();
}

String _bodyBeforeSuggestion(List<String> lines, int suggestionStart) {
  final body = lines.take(suggestionStart).toList(growable: true);
  while (body.isNotEmpty && body.last.trim().isEmpty) {
    body.removeLast();
  }
  if (body.isNotEmpty && _terminalSeparator.hasMatch(body.last)) {
    body.removeLast();
    while (body.isNotEmpty && body.last.trim().isEmpty) {
      body.removeLast();
    }
  }
  return body.join('\n').trimRight();
}

/// El último chunk de una respuesta virtualizada todavía contiene el cierre
/// original. Si ese mismo cierre se proyecta como pills, se retira únicamente
/// de ese chunk para no pintarlo dos veces.
String stripAssistantSuggestionsFromTerminalChunk(String markdown) {
  final projection = projectAssistantSuggestions(markdown);
  return projection.hasSuggestions ? projection.body : markdown;
}

String _cleanSuggestion(String value) {
  var clean = value.trim();
  clean = clean.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1)!,
  );
  clean = clean.replaceAll(RegExp(r'[*_~`]'), '');
  clean = clean.replaceFirst(
    RegExp(r'\s*[,;:]?\s+(?:o|u|or)\s*$', caseSensitive: false),
    '',
  );
  clean = clean.replaceFirst(RegExp(r'[\s,;:.]+$'), '');
  return clean.trim();
}
