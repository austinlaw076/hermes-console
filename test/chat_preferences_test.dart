import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_preferences.dart';
import 'package:hermes_android/core/services/chat_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('codec v1 round-trips the three local preferences', () {
    const value = ChatPreferences(
      density: TranscriptDensity.compact,
      autoRead: ChatPreferenceToggle.on,
      notifications: ChatPreferenceToggle.off,
    );

    expect(ChatPreferences.fromJson(value.toJson()), value);
  });

  test('unknown schema fails closed to inherited defaults', () {
    final value = ChatPreferences.fromJson({
      'schema_version': 99,
      'density': 'compact',
      'auto_read': 'on',
      'notifications': 'off',
    });

    expect(value, const ChatPreferences());
  });

  test('store isolates connections and logical conversations', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatPreferenceStore(prefs);
    const value = ChatPreferences(density: TranscriptDensity.compact);

    await store.save(
      connectionId: 'connection-a',
      logicalSessionId: 'lineage-a',
      value: value,
    );

    expect(
      await store.load(
        connectionId: 'connection-a',
        logicalSessionId: 'lineage-a',
      ),
      value,
    );
    expect(
      await store.load(
        connectionId: 'connection-b',
        logicalSessionId: 'lineage-a',
      ),
      const ChatPreferences(),
    );
    expect(
      await store.load(
        connectionId: 'connection-a',
        logicalSessionId: 'lineage-b',
      ),
      const ChatPreferences(),
    );
  });

  test('provisional session preference migrates to lineage key once', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatPreferenceStore(prefs);
    const value = ChatPreferences(notifications: ChatPreferenceToggle.off);

    await store.save(
      connectionId: 'connection-a',
      logicalSessionId: 'provisional-session',
      value: value,
    );

    expect(
      await store.load(
        connectionId: 'connection-a',
        logicalSessionId: 'lineage-root',
        legacySessionIds: const ['provisional-session'],
      ),
      value,
    );
    expect(
      await store.load(
        connectionId: 'connection-a',
        logicalSessionId: 'provisional-session',
      ),
      const ChatPreferences(),
    );
  });

  test('oversized or malformed persisted payload is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'chat_preferences_v1_${base64Url.encode(utf8.encode('connection'))}_'
              '${base64Url.encode(utf8.encode('lineage'))}':
          'x' * 4096,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = ChatPreferenceStore(prefs);

    expect(
      await store.load(connectionId: 'connection', logicalSessionId: 'lineage'),
      const ChatPreferences(),
    );
  });
}
