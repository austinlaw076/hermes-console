import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/chat_draft_store.dart';
import 'package:hermes_android/core/services/local_transcript_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStore = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            switch (call.method) {
              case 'write':
                secureStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return secureStore[args['key'] as String];
              case 'delete':
                secureStore.remove(args['key'] as String);
                return null;
              case 'readAll':
                return Map<String, String>.from(secureStore);
              case 'containsKey':
                return secureStore.containsKey(args['key'] as String);
            }
            return null;
          },
        );
  });

  test('guarda, restaura y limpia el borrador por sesión', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);
    final file = File(
      '${Directory.systemTemp.path}/hermes-draft-${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await file.writeAsString('fixture');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final attachment = AttachmentDraft(
      type: AttachmentType.document,
      name: 'fixture.txt',
      mimeType: 'text/plain',
      sizeBytes: 7,
      localPath: file.path,
    );

    await store.save('conn-a', 'session-a', 'mensaje a medias', [attachment]);
    final restored = await store.load('conn-a', 'session-a');

    expect(restored.text, 'mensaje a medias');
    expect(restored.attachments.single.name, 'fixture.txt');
    expect((await store.load('conn-a', 'session-b')).text, isEmpty);
    expect(
      prefs.getKeys().where((key) => key.startsWith('chat_draft_')),
      isEmpty,
    );
    expect(secureStore.keys.single, startsWith('chat_draft_v3.'));

    await store.clear('conn-a', 'session-a');
    expect((await store.load('conn-a', 'session-a')).text, isEmpty);
  });

  test('aísla drafts de profiles con el mismo session id', () async {
    final store = ChatDraftStore(await SharedPreferences.getInstance());
    await store.save(
      'conn-shared',
      'session-shared',
      'draft A',
      const [],
      profile: 'profile-a',
    );
    await store.save(
      'conn-shared',
      'session-shared',
      'draft B',
      const [],
      profile: 'profile-b',
    );

    expect(
      (await store.load(
        'conn-shared',
        'session-shared',
        profile: 'profile-a',
      )).text,
      'draft A',
    );
    expect(
      (await store.load(
        'conn-shared',
        'session-shared',
        profile: 'profile-b',
      )).text,
      'draft B',
    );
    await store.clear('conn-shared', 'session-shared', profile: 'profile-a');
    expect(
      (await store.load(
        'conn-shared',
        'session-shared',
        profile: 'profile-b',
      )).text,
      'draft B',
    );
  });

  test(
    'clear posterior gana aunque un autosave anterior siga escribiendo',
    () async {
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final args =
                  (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
              switch (call.method) {
                case 'write':
                  final value = args['value'] as String;
                  if (value.contains('autosave anterior')) {
                    if (!writeStarted.isCompleted) writeStarted.complete();
                    await releaseWrite.future;
                  }
                  secureStore[args['key'] as String] = value;
                  return null;
                case 'read':
                  return secureStore[args['key'] as String];
                case 'delete':
                  secureStore.remove(args['key'] as String);
                  return null;
                case 'readAll':
                  return Map<String, String>.from(secureStore);
                case 'containsKey':
                  return secureStore.containsKey(args['key'] as String);
              }
              return null;
            },
          );
      final store = ChatDraftStore(await SharedPreferences.getInstance());

      final staleSave = store.save(
        'conn-ordered',
        'session-ordered',
        'autosave anterior',
        const [],
      );
      await writeStarted.future;
      final acknowledgedClear = store.clear('conn-ordered', 'session-ordered');
      await Future<void>.delayed(Duration.zero);
      releaseWrite.complete();
      await staleSave;
      await acknowledgedClear;

      expect(
        (await store.load('conn-ordered', 'session-ordered')).text,
        isEmpty,
      );
      expect(
        secureStore.containsKey(
          ChatDraftStore.keyForTesting('conn-ordered', 'session-ordered'),
        ),
        isFalse,
      );
    },
  );

  test('clearForSession removes every owner but preserves neighbors', () async {
    final store = ChatDraftStore(await SharedPreferences.getInstance());
    await store.save(
      'conn-shared',
      'session-shared',
      'draft A',
      const [],
      profile: 'profile-a',
    );
    await store.save(
      'conn-shared',
      'session-shared',
      'draft B',
      const [],
      profile: 'profile-b',
    );
    await store.save(
      'conn-shared',
      'session-neighbor',
      'keep me',
      const [],
      profile: 'profile-a',
    );

    await store.clearForSession('conn-shared', 'session-shared');

    expect(
      (await store.load(
        'conn-shared',
        'session-shared',
        profile: 'profile-a',
      )).text,
      isEmpty,
    );
    expect(
      (await store.load(
        'conn-shared',
        'session-shared',
        profile: 'profile-b',
      )).text,
      isEmpty,
    );
    expect(
      (await store.load(
        'conn-shared',
        'session-neighbor',
        profile: 'profile-a',
      )).text,
      'keep me',
    );
  });

  test('roundtrip conserva identidad, FSM, error y owner remoto', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);
    final file = File(
      '${Directory.systemTemp.path}/hermes-draft-fsm-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final attachment = AttachmentDraft(
      localId: 'attachment-fsm',
      type: AttachmentType.document,
      name: 'fsm.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 3,
      localPath: file.path,
      uploadState: AttachmentUploadState.error,
      attempt: 2,
      errorKind: AttachmentErrorKind.transport,
      remoteRef: '@file:.hermes/fsm.pdf',
      remoteSessionId: 'runtime-a',
      remoteTransport: AttachmentRemoteTransport.desktop,
    );

    await store.save('conn-a', 'session-fsm', 'texto', [attachment]);
    final restored = (await store.load(
      'conn-a',
      'session-fsm',
    )).attachments.single;

    expect(restored.localId, 'attachment-fsm');
    expect(restored.uploadState, AttachmentUploadState.error);
    expect(restored.attempt, 2);
    expect(restored.errorKind, AttachmentErrorKind.transport);
    expect(restored.remoteRef, '@file:.hermes/fsm.pdf');
    expect(restored.remoteSessionId, 'runtime-a');
    expect(restored.remoteTransport, AttachmentRemoteTransport.desktop);
  });

  test(
    'Room draft preserves the retry identity without plaintext prefs',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ChatDraftStore(prefs);

      await store.save(
        'conn-room',
        'mob-room-room-1',
        '@infra revisa backups',
        const [],
        missionRoomIntentId: 'intent-stable-42',
        missionRoomWorkerProfile: 'infra',
        missionRoomBoardId: 'board-homelab',
        missionRoomBoardQuery: 'homelab',
        missionRoomTaskPhase: MissionRoomTaskPhase.submitting,
      );
      final restored = await store.load('conn-room', 'mob-room-room-1');

      expect(restored.missionRoomIntentId, 'intent-stable-42');
      expect(restored.missionRoomWorkerProfile, 'infra');
      expect(restored.missionRoomBoardId, 'board-homelab');
      expect(restored.missionRoomBoardQuery, 'homelab');
      expect(restored.missionRoomTaskPhase, MissionRoomTaskPhase.submitting);
      expect(restored.missionRoomOutcomeUnknown, isFalse);
      expect(
        prefs.getKeys().where((key) => key.contains('intent-stable-42')),
        isEmpty,
      );
      expect(
        secureStore[ChatDraftStore.keyForTesting(
          'conn-room',
          'mob-room-room-1',
        )],
        contains('intent-stable-42'),
      );
    },
  );

  test('unresolved Room writes do not expire before reconciliation', () async {
    final old = DateTime.now().subtract(const Duration(days: 31));
    secureStore['chat_draft_v2_conn-room_unknown'] = jsonEncode({
      'savedAt': old.millisecondsSinceEpoch,
      'text': '@infra verifica el resultado',
      'attachments': const <Object>[],
      'missionRoomIntentId': 'intent-unknown',
      'missionRoomWorkerProfile': 'infra',
      'missionRoomBoardId': 'homelab',
      'missionRoomTaskPhase': MissionRoomTaskPhase.outcomeUnknown.name,
    });
    secureStore['chat_draft_v2_conn-room_ordinary'] = jsonEncode({
      'savedAt': old.millisecondsSinceEpoch,
      'text': 'borrador ordinario antiguo',
      'attachments': const <Object>[],
    });
    final store = ChatDraftStore(await SharedPreferences.getInstance());

    final unknown = await store.load('conn-room', 'unknown');
    final ordinary = await store.load('conn-room', 'ordinary');

    expect(unknown.missionRoomTaskPhase, MissionRoomTaskPhase.outcomeUnknown);
    expect(unknown.missionRoomIntentId, 'intent-unknown');
    expect(ordinary.text, isEmpty);
    expect(
      secureStore.containsKey(
        ChatDraftStore.keyForTesting('conn-room', 'unknown'),
      ),
      isTrue,
    );
    expect(
      secureStore.containsKey('chat_draft_v2_conn-room_ordinary'),
      isFalse,
    );
  });

  test(
    'solo limpia la copia privada cuando desaparece el último owner',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final cleaned = <String>[];
      final store = ChatDraftStore(
        prefs,
        deletePrivateCopy: (attachment) async {
          cleaned.add(attachment.localId);
          return true;
        },
      );
      final file = File(
        '${Directory.systemTemp.path}/hermes-shared-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes([1]);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final shared = AttachmentDraft(
        localId: 'shared-owner',
        type: AttachmentType.document,
        name: 'shared.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 1,
        localPath: file.path,
      );
      await store.save('conn-a', 'session-a', 'a', [shared]);
      await store.save('conn-a', 'session-b', 'b', [shared]);

      await store.clear('conn-a', 'session-a');
      expect(cleaned, isEmpty);
      await store.clear('conn-a', 'session-b');
      expect(cleaned, ['shared-owner']);
    },
  );

  test('un tombstone de outbox no conserva la copia retirada', () async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = <String>[];
    final store = ChatDraftStore(
      prefs,
      deletePrivateCopy: (attachment) async {
        cleaned.add(attachment.localId);
        return true;
      },
    );
    const attachment = AttachmentDraft(
      localId: 'removed-cross-store',
      type: AttachmentType.document,
      name: 'removed.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1,
      localPath: '/private/removed-cross-store.pdf',
    );
    await store.save('conn-a', 'session-a', '', const [attachment]);
    secureStore['chat_turn_outbox_v1'] = jsonEncode({
      'turn': {
        'attachments': [
          attachment
              .copyWith(uploadState: AttachmentUploadState.removed)
              .toJson(),
        ],
      },
    });

    await store.clear('conn-a', 'session-a');

    expect(cleaned, ['removed-cross-store']);
  });

  test('indexa un chat nuevo para poder reabrirlo desde las listas', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);
    await store.save(
      'conn-new',
      'mobile-new-session',
      'Texto todavía sin enviar',
      const [],
    );

    final entries = await store.listForConnection('conn-new');

    expect(entries, hasLength(1));
    expect(entries.single.sessionId, 'mobile-new-session');
    expect(entries.single.draft.text, 'Texto todavía sin enviar');
    final session = entries.single.toSession(fallbackTitle: 'Nuevo chat');
    expect(session.source, 'mobile-draft');
    expect(session.isDraftOnly, isTrue);
    expect(session.hasLocalDraft, isTrue);
    expect(session.title, 'Texto todavía sin enviar');
    expect(session.preview, 'Texto todavía sin enviar');
  });

  test(
    'el índice genérico omite drafts V3 de Bot y Room sin borrarlos',
    () async {
      final store = ChatDraftStore(await SharedPreferences.getInstance());
      await store.save(
        'conn-owned',
        'mobile-normal',
        'borrador de conversación',
        const [],
        profile: 'default',
      );
      await store.save(
        'conn-owned',
        'mob-room-room-7',
        '@builder revisa el estado',
        const [],
        profile: 'manager',
      );
      await store.save(
        'conn-owned',
        'mob-bot-research',
        'continúa el análisis',
        const [],
        profile: 'research',
      );
      await store.save(
        'conn-owned',
        'session-owned-by-room',
        'owner de sala',
        const [],
        profile: 'mob-room-room-7',
      );
      await store.save(
        'conn-owned',
        'session-owned-by-bot',
        'owner de bot',
        const [],
        profile: 'mob-bot-research',
      );

      final entries = await store.listForConnection('conn-owned');

      expect(entries.map((entry) => entry.sessionId), ['mobile-normal']);
      final dedicatedDrafts = <(String, String, String)>[
        ('mob-room-room-7', 'manager', '@builder revisa el estado'),
        ('mob-bot-research', 'research', 'continúa el análisis'),
        ('session-owned-by-room', 'mob-room-room-7', 'owner de sala'),
        ('session-owned-by-bot', 'mob-bot-research', 'owner de bot'),
      ];
      for (final (sessionId, owner, text) in dedicatedDrafts) {
        final key = ChatDraftStore.keyForTesting(
          'conn-owned',
          sessionId,
          profile: owner,
        );
        expect(secureStore.containsKey(key), isTrue);
        expect(
          (await store.load('conn-owned', sessionId, profile: owner)).text,
          text,
        );
      }
    },
  );

  test('el listado migra borradores v2 genéricos al owner default', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    secureStore['chat_draft_v2_conn-legacy_mobile-legacy'] = jsonEncode({
      'savedAt': now,
      'text': 'Borrador anterior a perfiles',
      'attachments': const <Object>[],
    });
    final store = ChatDraftStore(await SharedPreferences.getInstance());

    final entries = await store.listForConnection('conn-legacy');

    expect(entries, hasLength(1));
    expect(entries.single.sessionId, 'mobile-legacy');
    expect(entries.single.profile, 'default');
    expect(
      secureStore[ChatDraftStore.keyForTesting('conn-legacy', 'mobile-legacy')],
      isNotNull,
    );
    expect(
      secureStore.containsKey('chat_draft_v2_conn-legacy_mobile-legacy'),
      isFalse,
    );
  });

  test(
    'el listado elimina claves v3 malformadas sin exponer su draft',
    () async {
      final malformedKey =
          '${ChatDraftStore.keyForTesting('conn-legacy', 'session-a')}.extra';
      secureStore[malformedKey] = jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'text': 'no debe reaparecer',
        'attachments': const <Object>[],
      });
      final store = ChatDraftStore(await SharedPreferences.getInstance());

      expect(await store.listForConnection('conn-legacy'), isEmpty);
      expect(secureStore.containsKey(malformedKey), isFalse);
    },
  );

  test('el listado deja que Rooms y Bots reclamen su owner real', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    secureStore['chat_draft_v2_conn-legacy_mob-room-room-1'] = jsonEncode({
      'savedAt': now,
      'text': '@infra revisa backups',
      'attachments': const <Object>[],
    });
    secureStore['chat_draft_v2_conn-legacy_mob-bot-research'] = jsonEncode({
      'savedAt': now,
      'text': 'continúa la investigación',
      'attachments': const <Object>[],
    });
    final store = ChatDraftStore(await SharedPreferences.getInstance());

    expect(await store.listForConnection('conn-legacy'), isEmpty);
    expect(
      secureStore.containsKey('chat_draft_v2_conn-legacy_mob-room-room-1'),
      isTrue,
    );
    expect(
      secureStore.containsKey('chat_draft_v2_conn-legacy_mob-bot-research'),
      isTrue,
    );

    final room = await store.load(
      'conn-legacy',
      'mob-room-room-1',
      profile: 'manager',
      claimUnscopedLegacy: true,
    );
    final bot = await store.load(
      'conn-legacy',
      'mob-bot-research',
      profile: 'research',
      claimUnscopedLegacy: true,
    );

    expect(room.text, '@infra revisa backups');
    expect(bot.text, 'continúa la investigación');
    expect(
      secureStore[ChatDraftStore.keyForTesting(
        'conn-legacy',
        'mob-room-room-1',
        profile: 'manager',
      )],
      isNotNull,
    );
    expect(
      secureStore[ChatDraftStore.keyForTesting(
        'conn-legacy',
        'mob-bot-research',
        profile: 'research',
      )],
      isNotNull,
    );
  });

  test('migra y elimina un borrador legacy guardado en claro', () async {
    SharedPreferences.setMockInitialValues({
      'chat_draft_v1_conn-a_session-a': jsonEncode({
        'text': 'legacy sensible',
        'attachments': const [],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);

    final restored = await store.load('conn-a', 'session-a');

    expect(restored.text, 'legacy sensible');
    expect(prefs.getString('chat_draft_v1_conn-a_session-a'), isNull);
    expect(
      secureStore[ChatDraftStore.keyForTesting('conn-a', 'session-a')],
      isNotNull,
    );
  });

  test('descarta rutas de adjunto que Android ya eliminó', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);
    await store.save('conn-a', 'session-a', 'texto', const [
      AttachmentDraft(
        type: AttachmentType.image,
        name: 'ausente.png',
        mimeType: 'image/png',
        sizeBytes: 12,
        localPath: '/ruta/que/no/existe.png',
      ),
    ]);

    final restored = await store.load('conn-a', 'session-a');
    expect(restored.text, 'texto');
    expect(restored.attachments, isEmpty);
  });

  test('borra solo los drafts cifrados de una conexión eliminada', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDraftStore(prefs);
    await store.save('conn-a', 'session-a', 'a1', const []);
    await store.save('conn-a', 'session-b', 'a2', const []);
    await store.save('conn-b', 'session-a', 'b1', const []);
    await prefs.setString('chat_draft_v1_conn-a_legacy', 'legacy');

    final removed = await store.deleteForConnection('conn-a');

    expect(removed, 3);
    expect(
      secureStore.keys.where(
        (key) =>
            key.startsWith('chat_draft_v3.') &&
            key != ChatDraftStore.keyForTesting('conn-b', 'session-a'),
      ),
      isEmpty,
    );
    expect(
      secureStore[ChatDraftStore.keyForTesting('conn-b', 'session-a')],
      isNotNull,
    );
    expect(prefs.getString('chat_draft_v1_conn-a_legacy'), isNull);
  });

  test('borra solo los transcripts locales de la conexión indicada', () async {
    final prefs = await SharedPreferences.getInstance();
    const transcript = [
      {'role': 'user', 'content': 'hola'},
      {'role': 'assistant', 'content': 'respuesta'},
    ];
    await LocalTranscriptStore.saveFromNewestFirst(
      'conn-a',
      'session-a',
      transcript.reversed.toList(),
    );
    await LocalTranscriptStore.saveFromNewestFirst(
      'conn-a',
      'session-b',
      transcript.reversed.toList(),
    );
    await LocalTranscriptStore.saveFromNewestFirst(
      'conn-b',
      'session-a',
      transcript.reversed.toList(),
    );
    await prefs.setString('local_transcript_conn-a_legacy', '[]');

    final removed = await LocalTranscriptStore.deleteForConnection('conn-a');

    expect(removed, 3);
    expect(
      secureStore.keys.where(
        (key) => key.startsWith('local_transcript_conn-a_'),
      ),
      isEmpty,
    );
    expect(secureStore['local_transcript_conn-b_session-a'], isNotNull);
    expect(prefs.getString('local_transcript_conn-a_legacy'), isNull);
  });
}
