import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/mission_bot_chat_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStore = <String, String>{};
  var failSecureReads = false;
  var secureWrites = 0;
  var secureDeletes = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    failSecureReads = false;
    secureWrites = 0;
    secureDeletes = 0;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            switch (call.method) {
              case 'write':
                secureWrites++;
                secureStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                if (failSecureReads) {
                  throw PlatformException(code: 'secure_unavailable');
                }
                return secureStore[args['key'] as String];
              case 'readAll':
                return Map<String, String>.from(secureStore);
              case 'delete':
                secureDeletes++;
                secureStore.remove(args['key'] as String);
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  test(
    'provisional mobile ids are never accepted as durable Bot pins',
    () async {
      SharedPreferences.setMockInitialValues({
        'mission_control.bot_chat_pins.v1.conn-1': jsonEncode({
          'manager': 'mob-bot-manager',
        }),
      });
      final store = MissionBotChatStore(await SharedPreferences.getInstance());

      expect(await store.load('conn-1', 'manager'), isNull);
      await expectLater(
        store.save(
          connectionId: 'conn-1',
          profile: 'manager',
          sessionId: 'mob-bot-manager',
        ),
        throwsFormatException,
      );
    },
  );

  test('persiste Bot Chat cifrado por conexión y perfil', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = MissionBotChatStore(prefs);

    await store.save(
      connectionId: 'conn-a',
      profile: 'infra',
      sessionId: 'stored-bot-chat',
    );

    expect(await store.load('conn-a', 'infra'), 'stored-bot-chat');
    expect(await store.load('conn-b', 'infra'), isNull);
    expect(await store.load('conn-a', 'security'), isNull);
    expect(
      prefs.getKeys().where(
        (key) => key.startsWith('mission_control.bot_chat_pins'),
      ),
      isEmpty,
    );
    expect(secureStore.values, contains('stored-bot-chat'));
  });

  test('migra el fallback plaintext y elimina su copia antigua', () async {
    SharedPreferences.setMockInitialValues({
      'mission_control.bot_chat_pins.v1.conn-a': jsonEncode({
        'infra': 'stored-infra',
        'security': 'stored-security',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = MissionBotChatStore(prefs);

    expect(await store.load('conn-a', 'infra'), 'stored-infra');
    expect(secureStore.values, contains('stored-infra'));
    expect(
      jsonDecode(prefs.getString('mission_control.bot_chat_pins.v1.conn-a')!),
      {'security': 'stored-security'},
    );
  });

  test(
    'read-only lookup observes legacy pins without migrating them',
    () async {
      SharedPreferences.setMockInitialValues({
        'mission_control.bot_chat_pins.v1.conn-a': jsonEncode({
          'infra': 'stored-infra',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = MissionBotChatStore(prefs);

      final lookup = await store.lookup(
        'conn-a',
        'infra',
        migrateLegacy: false,
      );

      expect(lookup.state, MissionBotChatPinState.available);
      expect(lookup.sessionId, 'stored-infra');
      expect(secureStore, isEmpty);
      expect(secureWrites, 0);
      expect(secureDeletes, 0);
      expect(
        prefs.getString('mission_control.bot_chat_pins.v1.conn-a'),
        isNotNull,
      );
    },
  );

  test(
    'lookup distinguishes absent, corrupt and unavailable storage',
    () async {
      final store = MissionBotChatStore(await SharedPreferences.getInstance());

      expect(
        (await store.lookup('conn-a', 'infra')).state,
        MissionBotChatPinState.absent,
      );
      await store.save(
        connectionId: 'conn-a',
        profile: 'infra',
        sessionId: 'stored-infra',
      );
      secureStore[secureStore.keys.single] = 'bad\nsession';
      expect(
        (await store.lookup('conn-a', 'infra')).state,
        MissionBotChatPinState.corrupt,
      );

      failSecureReads = true;
      expect(
        (await store.lookup('conn-a', 'infra')).state,
        MissionBotChatPinState.unavailable,
      );
    },
  );

  test('falla cerrado con perfil o sesión malformados', () async {
    SharedPreferences.setMockInitialValues({
      'mission_control.bot_chat_pins.v1.conn-a':
          '{"infra":"bad\\nsession","Bad Profile":"stored"}',
    });
    final store = MissionBotChatStore(await SharedPreferences.getInstance());

    expect(await store.load('conn-a', 'infra'), isNull);
    expect(await store.load('conn-a', 'Bad Profile'), isNull);
    await expectLater(
      store.save(
        connectionId: 'conn-a',
        profile: 'Bad Profile',
        sessionId: 'stored',
      ),
      throwsFormatException,
    );
  });

  test('concurrent profile pins do not overwrite each other', () async {
    final store = MissionBotChatStore(await SharedPreferences.getInstance());

    await Future.wait([
      store.save(
        connectionId: 'conn-a',
        profile: 'infra',
        sessionId: 'stored-infra',
      ),
      store.save(
        connectionId: 'conn-a',
        profile: 'security',
        sessionId: 'stored-security',
      ),
    ]);

    expect(await store.load('conn-a', 'infra'), 'stored-infra');
    expect(await store.load('conn-a', 'security'), 'stored-security');
  });

  test('clear removes encrypted and legacy fallback pins', () async {
    SharedPreferences.setMockInitialValues({
      'mission_control.bot_chat_pins.v1.conn-a': jsonEncode({
        'infra': 'stored-old',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = MissionBotChatStore(prefs);
    await store.save(
      connectionId: 'conn-a',
      profile: 'infra',
      sessionId: 'stored-new',
    );

    await store.clear(connectionId: 'conn-a', profile: 'infra');

    expect(await store.load('conn-a', 'infra'), isNull);
    expect(secureStore, isEmpty);
    expect(prefs.getKeys(), isEmpty);
  });

  test('connection cleanup removes only its encrypted Bot pins', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = MissionBotChatStore(prefs);
    await store.save(
      connectionId: 'conn-a',
      profile: 'infra',
      sessionId: 'stored-a-infra',
    );
    await store.save(
      connectionId: 'conn-a',
      profile: 'security',
      sessionId: 'stored-a-security',
    );
    await store.save(
      connectionId: 'conn-b',
      profile: 'infra',
      sessionId: 'stored-b-infra',
    );

    expect(await store.deleteForConnection('conn-a'), 2);
    expect(await store.load('conn-a', 'infra'), isNull);
    expect(await store.load('conn-a', 'security'), isNull);
    expect(await store.load('conn-b', 'infra'), 'stored-b-infra');
  });
}
