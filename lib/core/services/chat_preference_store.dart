import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_preferences.dart';

/// Persistencia local no sensible, aislada por instancia y lineage.
class ChatPreferenceStore {
  static const _prefix = 'chat_preferences_v1_';
  static const _maxPayloadBytes = 2048;

  final SharedPreferences _prefs;

  const ChatPreferenceStore(this._prefs);

  Future<ChatPreferences> load({
    required String connectionId,
    required String logicalSessionId,
    Iterable<String> legacySessionIds = const [],
  }) async {
    final primary = _key(connectionId, logicalSessionId);
    final direct = _decode(_prefs.getString(primary));
    if (direct != null) return direct;

    for (final legacyId in legacySessionIds) {
      if (legacyId.trim().isEmpty || legacyId == logicalSessionId) continue;
      final legacyKey = _key(connectionId, legacyId);
      final migrated = _decode(_prefs.getString(legacyKey));
      if (migrated == null) continue;
      await _write(primary, migrated);
      await _prefs.remove(legacyKey);
      return migrated;
    }
    return const ChatPreferences();
  }

  Future<void> save({
    required String connectionId,
    required String logicalSessionId,
    required ChatPreferences value,
  }) async {
    final key = _key(connectionId, logicalSessionId);
    if (value.isDefault) {
      await _prefs.remove(key);
      return;
    }
    await _write(key, value);
  }

  Future<void> clear({
    required String connectionId,
    required String logicalSessionId,
  }) => _prefs.remove(_key(connectionId, logicalSessionId));

  Future<void> _write(String key, ChatPreferences value) async {
    final encoded = jsonEncode(value.toJson());
    if (utf8.encode(encoded).length > _maxPayloadBytes) {
      throw const FormatException('Chat preferences exceed their size limit');
    }
    final written = await _prefs.setString(key, encoded);
    if (!written) {
      throw StateError('Chat preferences could not be persisted');
    }
  }

  static ChatPreferences? _decode(String? raw) {
    if (raw == null ||
        raw.isEmpty ||
        utf8.encode(raw).length > _maxPayloadBytes) {
      return null;
    }
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final json = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is String) json[entry.key as String] = entry.value;
      }
      return ChatPreferences.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  static String _key(String connectionId, String logicalSessionId) {
    final connection = base64Url.encode(utf8.encode(connectionId.trim()));
    final session = base64Url.encode(utf8.encode(logicalSessionId.trim()));
    return '$_prefix${connection}_$session';
  }
}
