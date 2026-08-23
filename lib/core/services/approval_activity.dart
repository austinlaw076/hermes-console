import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registro local (append-only) de eventos de permisos/aprobaciones.
///
/// El Gateway no persiste estos eventos, así que se guardan en el móvil de
/// forma honesta (no se finge sincronización). Nunca se guardan secretos: solo
/// tipo de evento, una descripción corta y el comando si aplica (truncado).
/// Clave: `approval_activity_<connectionId>`.
class ApprovalActivityEntry {
  final double ts; // epoch seconds
  final String kind; // requested|allowed_once|allowed_session|allowed_always|denied|yolo_enabled|yolo_disabled|auto_approved|blocked|high_risk_confirm
  final String summary;
  final String? command;
  final String? sessionId;

  const ApprovalActivityEntry({
    required this.ts,
    required this.kind,
    required this.summary,
    this.command,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'ts': ts,
    'kind': kind,
    'summary': summary,
    if (command != null) 'command': command,
    if (sessionId != null) 'session_id': sessionId,
  };

  factory ApprovalActivityEntry.fromJson(Map<String, dynamic> j) =>
      ApprovalActivityEntry(
        ts: (j['ts'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] ?? '',
        summary: j['summary'] ?? '',
        command: j['command'] as String?,
        sessionId: j['session_id'] as String?,
      );
}

class ApprovalActivityLog {
  static const _prefix = 'approval_activity_';
  static const _max = 100;

  final SharedPreferences _prefs;
  ApprovalActivityLog(this._prefs);

  String _key(String connectionId) => '$_prefix$connectionId';

  List<ApprovalActivityEntry> entries(String connectionId) {
    final raw = _prefs.getString(_key(connectionId));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(ApprovalActivityEntry.fromJson)
          .toList()
        ..sort((a, b) => b.ts.compareTo(a.ts));
    } catch (e) {
      debugPrint('[approval] excepción silenciada (se devuelve lista vacía): $e');
      return const [];
    }
  }

  Future<void> add(
    String connectionId, {
    required String kind,
    required String summary,
    String? command,
    String? sessionId,
  }) async {
    final list = [
      ApprovalActivityEntry(
        ts: DateTime.now().millisecondsSinceEpoch / 1000,
        kind: kind,
        summary: summary,
        // Recortar el comando para no guardar payloads enormes.
        command: command == null
            ? null
            : (command.length > 200 ? '${command.substring(0, 200)}…' : command),
        sessionId: sessionId,
      ),
      ...entries(connectionId),
    ];
    if (list.length > _max) list.removeRange(_max, list.length);
    await _prefs.setString(
      _key(connectionId),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear(String connectionId) =>
      _prefs.remove(_key(connectionId));
}
