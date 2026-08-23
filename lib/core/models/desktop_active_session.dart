/// Bounded, privacy-aware projection of one `session.active_list` row.
///
/// The projection deliberately excludes unknown payload fields. In particular,
/// it never keeps a raw server envelope that could retain prompts or secrets.
final class DesktopActiveSession {
  static const int _maxLabelLength = 512;

  final String runtimeSessionId;
  final String? storedSessionId;
  final bool current;
  final String? status;
  final DateTime? lastActiveAt;
  final DateTime? startedAt;
  final int? messageCount;
  final String? model;
  final String? preview;
  final String? title;

  const DesktopActiveSession({
    required this.runtimeSessionId,
    this.storedSessionId,
    this.current = false,
    this.status,
    this.lastActiveAt,
    this.startedAt,
    this.messageCount,
    this.model,
    this.preview,
    this.title,
  });

  static DesktopActiveSession? tryParse(Object? value) {
    final json = _stringKeyedMap(value);
    if (json == null) return null;
    final runtimeSessionId = _opaqueId(json['id']);
    if (runtimeSessionId == null) return null;
    return DesktopActiveSession(
      runtimeSessionId: runtimeSessionId,
      storedSessionId: _opaqueId(json['session_key']),
      current: json['current'] == true,
      status: _nonEmptyBoundedString(json['status']),
      lastActiveAt: _epochSeconds(json['last_active']),
      startedAt: _epochSeconds(json['started_at']),
      messageCount: _nonNegativeInt(json['message_count']),
      model: _nonEmptyBoundedString(json['model']),
      preview: _boundedString(json['preview']),
      title: _boundedString(json['title']),
    );
  }

  static String? _boundedString(Object? value) {
    if (value is! String) return null;
    return value.length <= _maxLabelLength
        ? value
        : value.substring(0, _maxLabelLength);
  }

  static String? _nonEmptyBoundedString(Object? value) {
    final bounded = _boundedString(value)?.trim();
    return bounded == null || bounded.isEmpty ? null : bounded;
  }

  static String? _opaqueId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 1024) return null;
    return trimmed;
  }
}

final class DesktopActiveSessionList {
  final List<DesktopActiveSession> sessions;

  const DesktopActiveSessionList({this.sessions = const []});

  factory DesktopActiveSessionList.fromJson(Map<String, dynamic> json) {
    final rawSessions = json['sessions'];
    if (rawSessions is! List) {
      throw const FormatException(
        'session.active_list omitted the sessions array',
      );
    }
    final sessions = <DesktopActiveSession>[];
    for (final row in rawSessions) {
      final parsed = DesktopActiveSession.tryParse(row);
      if (parsed != null) sessions.add(parsed);
    }
    return DesktopActiveSessionList(sessions: List.unmodifiable(sessions));
  }
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is String) result[entry.key as String] = entry.value;
  }
  return result;
}

int? _nonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  final integer = value.toInt();
  return value == integer ? integer : null;
}

DateTime? _epochSeconds(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  try {
    return DateTime.fromMicrosecondsSinceEpoch(
      (value.toDouble() * Duration.microsecondsPerSecond).round(),
      isUtc: true,
    );
  } on RangeError {
    return null;
  }
}
