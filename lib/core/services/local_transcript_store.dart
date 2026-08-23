import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Persistencia LOCAL del transcript de chat para instancias localhost (bridge).
///
/// El agente local responde por el Mobile Bridge (`/bridge/chat` → `hermes -z`,
/// oneshot): cada turno es independiente y el agente NO conserva el historial de
/// la sesión server-side como el gateway remoto (`/api/sessions/{id}/messages`).
/// Por eso, al cerrar y reabrir el chat de una instancia local, `getMessages`
/// devolvería vacío (o fallaría) y la conversación se perdería.
///
/// Aquí guardamos los turnos conversacionales reales (user/assistant) por
/// conexión+sesión, en orden CRONOLÓGICO (más antiguo primero) — el mismo
/// contrato que devuelve la API remota — para poder reconstruir el chat sin
/// depender de un endpoint que no existe.
///
/// El transcript se cifra con EncryptedSharedPreferences (Jetpack Security) vía
/// flutter_secure_storage, de modo que `adb backup` o un dispositivo rooteado no
/// lo dejan legible en claro. Los transcripts escritos por versiones anteriores
/// en SharedPreferences se migran de forma transparente en el primer [load].
class LocalTranscriptStore {
  static const _storage = FlutterSecureStorage();

  static String _key(String connId, String sessionId) =>
      'local_transcript_${connId}_$sessionId';

  /// Guarda el transcript a partir de la lista viva del chat ([ActiveChat]
  /// usa index 0 = más nuevo). Filtra placeholders del pipeline, errores y
  /// turnos vacíos: solo user/assistant con contenido. Si no queda nada, borra
  /// la entrada en vez de dejar un `[]`.
  static Future<void> saveFromNewestFirst(
    String connId,
    String sessionId,
    List<Map<String, dynamic>> messagesNewestFirst,
  ) async {
    final clean = <Map<String, dynamic>>[];
    // Recorre de más antiguo a más nuevo para guardar en orden cronológico.
    for (var i = messagesNewestFirst.length - 1; i >= 0; i--) {
      final m = messagesNewestFirst[i];
      final role = (m['role'] ?? '').toString();
      if (role != 'user' && role != 'assistant') continue;
      if (m['_pipeline'] == true) continue;
      final content = (m['content'] as String?) ?? '';
      if (content.trim().isEmpty) continue;
      clean.add({'role': role, 'content': content});
    }
    final key = _key(connId, sessionId);
    if (clean.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: jsonEncode(clean));
  }

  /// Lee el transcript guardado en orden CRONOLÓGICO (más antiguo primero),
  /// igual que la API remota; el llamador lo invierte si necesita newest-first.
  ///
  /// Si la clave no está en el almacenamiento cifrado, intenta migrarla desde
  /// las SharedPreferences en claro de versiones anteriores: la reescribe
  /// cifrada y la borra del claro.
  static Future<List<Map<String, dynamic>>> load(
    String connId,
    String sessionId,
  ) async {
    final key = _key(connId, sessionId);
    var raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy == null || legacy.isEmpty) return const [];
      await _storage.write(key: key, value: legacy);
      await prefs.remove(key);
      raw = legacy;
    }
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint(
        '[transcript-store] transcript local corrupto, se descarta: $e',
      );
      return const [];
    }
  }

  static Future<void> clear(String connId, String sessionId) async {
    await _storage.delete(key: _key(connId, sessionId));
  }

  /// Elimina todos los transcripts cifrados (y restos legacy en claro) de una
  /// conexión sin tocar ninguna otra instancia.
  static Future<int> deleteForConnection(String connId) async {
    final prefix = 'local_transcript_${connId}_';
    var removed = 0;
    final all = await _storage.readAll();
    for (final key in all.keys.where((key) => key.startsWith(prefix))) {
      await _storage.delete(key: key);
      removed++;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
      removed++;
    }
    return removed;
  }

  /// Devuelve una [Session] mínima por cada transcript guardado para [connId],
  /// ordenadas de más reciente a más antigua. Permite mostrar el historial de
  /// chats locales en la home sin depender de `/api/sessions` (que el bridge
  /// no expone).
  static Future<List<Session>> listForConnection(String connId) async {
    final prefix = 'local_transcript_${connId}_';
    final all = await _storage.readAll();
    final sessions = <Session>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final sessionId = entry.key.substring(prefix.length);
      final raw = entry.value;
      if (raw.isEmpty) continue;
      List<Map<String, dynamic>> msgs;
      try {
        msgs = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint(
          '[transcript-store] transcript de sesión corrupto, se omite: $e',
        );
        continue;
      }
      if (msgs.isEmpty) continue;
      final lastAssistant = msgs.lastWhere(
        (m) => m['role'] == 'assistant',
        orElse: () => <String, dynamic>{},
      );
      final preview = ((lastAssistant['content'] as String?) ?? '').trim();
      // Extrae timestamp del ID mob-<ms>-<uuid> si está disponible.
      double startedAt = 0;
      final mobMatch = RegExp(r'mob-(\d+)').firstMatch(sessionId);
      if (mobMatch != null) {
        final ms = int.tryParse(mobMatch.group(1) ?? '') ?? 0;
        startedAt = ms / 1000.0;
      }
      sessions.add(
        Session(
          id: sessionId,
          title: 'Chat local',
          model: 'hermes-agent',
          source: 'mobile-local',
          messageCount: msgs.length,
          isActive: false,
          preview: preview.length > 120
              ? '${preview.substring(0, 120)}…'
              : preview,
          startedAt: startedAt,
          updatedAt: startedAt,
        ),
      );
    }
    sessions.sort(
      (a, b) =>
          (b.updatedAt ?? b.startedAt).compareTo(a.updatedAt ?? a.startedAt),
    );
    return sessions;
  }
}
