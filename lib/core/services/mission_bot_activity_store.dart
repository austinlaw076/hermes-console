import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mission_store_mutation_queue.dart';

/// Local read watermarks for Bot Chat rows.
///
/// Only a timestamp per connection/profile is stored. Message content,
/// previews and session identifiers remain owned by Hermes.
final class MissionBotActivityStore {
  static const _keyPrefix = 'mission_control.bot_activity.v1.';
  static const _maxProfiles = 256;
  static final RegExp _profile = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  final SharedPreferences _prefs;

  MissionBotActivityStore(this._prefs);

  static String _scope(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  String _key(String connectionId) => '$_keyPrefix${_scope(connectionId)}';

  Map<String, int> watermarks(String connectionId) {
    if (!_validConnection(connectionId)) return const {};
    final raw = _prefs.getString(_key(connectionId));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final profile = entry.key.toString();
        final value = entry.value;
        if (!_profile.hasMatch(profile) ||
            value is! num ||
            !value.isFinite ||
            value < 0 ||
            value != value.truncate()) {
          continue;
        }
        result[profile] = value.toInt();
        if (result.length >= _maxProfiles) break;
      }
      return Map.unmodifiable(result);
    } catch (_) {
      return const {};
    }
  }

  int watermark(String connectionId, String profile) =>
      watermarks(connectionId)[profile.trim()] ?? 0;

  bool isUnread(String connectionId, String profile, int activityAtMs) =>
      activityAtMs > watermark(connectionId, profile);

  Future<void> markRead({
    required String connectionId,
    required String profile,
    required int activityAtMs,
  }) => MissionStoreMutationQueue.run(() async {
    final owner = profile.trim();
    if (!_validConnection(connectionId) ||
        !_profile.hasMatch(owner) ||
        activityAtMs < 0) {
      throw const FormatException('Invalid Bot activity watermark');
    }
    final current = watermarks(connectionId);
    if ((current[owner] ?? 0) >= activityAtMs) return;
    final next = <String, int>{...current, owner: activityAtMs};
    await _write(connectionId, next);
  });

  Future<void> prune(String connectionId, Set<String> profiles) =>
      MissionStoreMutationQueue.run(() async {
        if (!_validConnection(connectionId)) return;
        final allowed = profiles
            .map((value) => value.trim())
            .where(_profile.hasMatch)
            .take(_maxProfiles)
            .toSet();
        final current = watermarks(connectionId);
        final next = <String, int>{
          for (final entry in current.entries)
            if (allowed.contains(entry.key)) entry.key: entry.value,
        };
        if (next.length == current.length) return;
        await _write(connectionId, next);
      });

  Future<void> _write(String connectionId, Map<String, int> values) async {
    final key = _key(connectionId);
    if (values.isEmpty) {
      final removed = await _prefs.remove(key);
      if (!removed && _prefs.containsKey(key)) {
        throw StateError('Bot activity cleanup was not persisted');
      }
      return;
    }
    final saved = await _prefs.setString(key, jsonEncode(values));
    if (!saved) throw StateError('Bot activity watermark was not persisted');
  }

  static bool _validConnection(String value) {
    final connection = value.trim();
    return connection.isNotEmpty &&
        connection.length <= 512 &&
        !connection.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
  }
}
