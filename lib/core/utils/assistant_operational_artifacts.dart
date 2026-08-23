import 'dart:convert';

/// Presentación segura de artefactos operativos que algunos agentes incluyen
/// en su respuesta final después de delegar trabajo.
///
/// La proyección solo se activa cuando encuentra un identificador nativo
/// `deleg_*` fuera de una valla de código y el texto parece realmente un
/// resumen de delegación. El contenido persistido no se modifica.
final class AssistantOperationalProjection {
  final String visibleMarkdown;
  final List<String> technicalDetails;

  const AssistantOperationalProjection({
    required this.visibleMarkdown,
    this.technicalDetails = const [],
  });

  bool get hasTechnicalDetails => technicalDetails.isNotEmpty;
}

final RegExp _delegationIdPattern = RegExp(r'\bdeleg_[A-Za-z0-9]{6,}\b');
final RegExp _inlineJsonPattern = RegExp(r'`(\{[^`\n]{1,512}\})`');
final RegExp _delegationContextPattern = RegExp(
  r'\b(batches?|lotes?|delegations?|delegaciones?|subagents?|subagentes?)\b',
  caseSensitive: false,
);

AssistantOperationalProjection projectAssistantOperationalArtifacts(
  String markdown, {
  required String Function(int index) subagentLabel,
  required String resultLabel,
}) {
  if (markdown.trim().isEmpty) {
    return AssistantOperationalProjection(visibleMarkdown: markdown);
  }

  // Atajo: sin identificadores `deleg_*` la proyección es siempre identidad.
  // Evita barrer vallas y regex del contenido COMPLETO en cada frame del
  // streaming (el asistente vivo la invoca a 30 Hz).
  if (!markdown.contains('deleg_')) {
    return AssistantOperationalProjection(visibleMarkdown: markdown);
  }

  final outsideFences = _mapOutsideCodeFences(
    markdown,
    (segment) => segment,
    preserveFenced: false,
  );
  final ids = <String>[];
  for (final match in _delegationIdPattern.allMatches(outsideFences)) {
    final id = match.group(0)!;
    if (!ids.contains(id)) ids.add(id);
  }
  if (ids.isEmpty) {
    return AssistantOperationalProjection(visibleMarkdown: markdown);
  }

  final envelopes = <String, Object?>{};
  for (final match in _inlineJsonPattern.allMatches(outsideFences)) {
    final raw = match.group(1)!;
    final value = _operationalResultValue(raw);
    if (value != null) envelopes[raw] = value;
  }

  // Una mención aislada puede formar parte de una explicación técnica válida.
  // Exigimos señales adicionales de que el modelo está resumiendo una
  // delegación, en vez de borrar identificadores de forma global.
  final looksLikeDelegationSummary =
      ids.length > 1 ||
      envelopes.isNotEmpty ||
      _delegationContextPattern.hasMatch(outsideFences);
  if (!looksLikeDelegationSummary) {
    return AssistantOperationalProjection(visibleMarkdown: markdown);
  }

  final labels = <String, String>{
    for (var index = 0; index < ids.length; index++)
      ids[index]: subagentLabel(index + 1),
  };
  final technicalDetails = <String>[
    for (final id in ids) '${labels[id]} · $id',
    ...envelopes.keys,
  ];

  final visible = _mapOutsideCodeFences(markdown, (segment) {
    var projected = segment;
    for (final entry in labels.entries) {
      final escapedId = RegExp.escape(entry.key);
      projected = projected.replaceAll(
        RegExp(
          '\\b(?:batch|delegation|delegación)\\s+`?$escapedId`?',
          caseSensitive: false,
        ),
        entry.value,
      );
      projected = projected.replaceAll(RegExp('`$escapedId`'), entry.value);
      projected = projected.replaceAll(RegExp('\\b$escapedId\\b'), entry.value);
    }
    projected = projected.replaceAllMapped(_inlineJsonPattern, (match) {
      final raw = match.group(1)!;
      final value = envelopes[raw];
      if (value == null) return match.group(0)!;
      final readable = _readableScalar(value);
      return readable == null
          ? '$resultLabel disponible'
          : '$resultLabel: $readable';
    });
    return projected;
  });

  return AssistantOperationalProjection(
    visibleMarkdown: visible,
    technicalDetails: List.unmodifiable(technicalDetails),
  );
}

Object? _operationalResultValue(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('result')) {
      return null;
    }
    const allowedKeys = {'result', 'status', 'error'};
    if (decoded.keys.any((key) => !allowedKeys.contains(key))) return null;
    return decoded['result'] ?? const _NullOperationalResult();
  } on FormatException {
    return null;
  }
}

String? _readableScalar(Object? value) {
  if (value is _NullOperationalResult) return 'null';
  if (value is num || value is bool) return value.toString();
  if (value is String) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > 120) return null;
    return normalized
        .replaceAll(r'\', r'\\')
        .replaceAll('*', r'\*')
        .replaceAll('_', r'\_')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]');
  }
  return null;
}

String _mapOutsideCodeFences(
  String source,
  String Function(String segment) transform, {
  bool preserveFenced = true,
}) {
  final output = StringBuffer();
  var cursor = 0;
  var insideFence = false;
  String? fenceMarker;
  final lines = RegExp(r'.*(?:\n|$)').allMatches(source);
  for (final lineMatch in lines) {
    final line = lineMatch.group(0)!;
    if (line.isEmpty && lineMatch.start == source.length) continue;
    final trimmed = line.trimLeft();
    final marker = trimmed.startsWith('```')
        ? '```'
        : trimmed.startsWith('~~~')
        ? '~~~'
        : null;
    if (marker != null && (!insideFence || marker == fenceMarker)) {
      insideFence = !insideFence;
      fenceMarker = insideFence ? marker : null;
      output.write(line);
    } else {
      output.write(
        insideFence
            ? preserveFenced
                  ? line
                  : '\n'
            : transform(line),
      );
    }
    cursor = lineMatch.end;
  }
  if (cursor < source.length) {
    final tail = source.substring(cursor);
    output.write(
      insideFence
          ? preserveFenced
                ? tail
                : ''
          : transform(tail),
    );
  }
  return output.toString();
}

final class _NullOperationalResult {
  const _NullOperationalResult();
}
