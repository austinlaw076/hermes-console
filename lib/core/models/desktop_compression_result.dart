import 'desktop_session_snapshot.dart';

/// Resultado tipado de `session.compress` (Hermes Desktop 0.19).
///
/// Contiene el transcript reemplazado y por ello se mantiene solo en memoria;
/// ningún payload crudo se conserva ni debe llegar a logs diagnósticos.
final class DesktopCompressionResult {
  final String status;
  final int removed;
  final int beforeMessages;
  final int afterMessages;
  final int beforeTokens;
  final int afterTokens;
  final DesktopCompressionSummary summary;
  final DesktopUsageStats? usage;
  final DesktopSessionRuntimeInfo info;
  final List<DesktopSessionMessage> messages;

  const DesktopCompressionResult({
    required this.status,
    required this.removed,
    required this.beforeMessages,
    required this.afterMessages,
    required this.beforeTokens,
    required this.afterTokens,
    required this.summary,
    required this.info,
    required this.messages,
    this.usage,
  });

  factory DesktopCompressionResult.fromJson(Map<String, dynamic> json) {
    final status = _nonEmptyString(json['status']);
    final removed = _nonNegativeInt(json['removed']);
    final beforeMessages = _nonNegativeInt(json['before_messages']);
    final afterMessages = _nonNegativeInt(json['after_messages']);
    final beforeTokens = _nonNegativeInt(json['before_tokens']);
    final afterTokens = _nonNegativeInt(json['after_tokens']);
    final rawSummary = _stringKeyedMap(json['summary']);
    final rawInfo = _stringKeyedMap(json['info']);
    final rawMessages = json['messages'];
    if (status == null ||
        status != 'compressed' ||
        removed == null ||
        beforeMessages == null ||
        afterMessages == null ||
        beforeTokens == null ||
        afterTokens == null ||
        rawSummary == null ||
        rawInfo == null ||
        rawMessages is! List) {
      throw const FormatException('invalid session.compress response');
    }

    final messages = <DesktopSessionMessage>[];
    for (var index = 0; index < rawMessages.length; index++) {
      final message = DesktopSessionMessage.tryParse(
        rawMessages[index],
        serverOrdinal: index,
      );
      if (message == null) {
        throw const FormatException('invalid compressed transcript');
      }
      messages.add(message);
    }
    if (afterMessages != rawMessages.length || removed > beforeMessages) {
      throw const FormatException('inconsistent session.compress counts');
    }

    return DesktopCompressionResult(
      status: status,
      removed: removed,
      beforeMessages: beforeMessages,
      afterMessages: afterMessages,
      beforeTokens: beforeTokens,
      afterTokens: afterTokens,
      summary: DesktopCompressionSummary.fromJson(rawSummary),
      usage: json['usage'] is Map
          ? DesktopUsageStats.fromJson(json['usage'])
          : null,
      info: DesktopSessionRuntimeInfo.fromJson(rawInfo),
      messages: List.unmodifiable(messages),
    );
  }
}

final class DesktopCompressionSummary {
  final bool noop;
  final bool? aborted;
  final bool? fallbackUsed;
  final String? headline;
  final String? tokenLine;
  final String? note;

  const DesktopCompressionSummary({
    required this.noop,
    this.aborted,
    this.fallbackUsed,
    this.headline,
    this.tokenLine,
    this.note,
  });

  factory DesktopCompressionSummary.fromJson(Map<String, dynamic> json) {
    final noop = json['noop'];
    if (noop is! bool) {
      throw const FormatException('invalid session.compress summary');
    }
    return DesktopCompressionSummary(
      noop: noop,
      aborted: json['aborted'] is bool ? json['aborted'] as bool : null,
      fallbackUsed: json['fallback_used'] is bool
          ? json['fallback_used'] as bool
          : null,
      headline: _stringValue(json['headline']),
      tokenLine: _stringValue(json['token_line']),
      note: _stringValue(json['note']),
    );
  }
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

String? _stringValue(Object? value) => value is String ? value : null;

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _nonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  final integer = value.toInt();
  return value == integer ? integer : null;
}
