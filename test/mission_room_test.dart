import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/mission_room.dart';
import 'package:hermes_android/core/services/mission_room_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

MissionRoom _room({
  Iterable<String> members = const ['manager', 'infra'],
  String purposeLabel = '',
}) => MissionRoom(
  id: 'room-1',
  connectionId: 'conn-a',
  name: 'Homelab',
  purposeLabel: purposeLabel,
  managerProfile: 'manager',
  memberProfiles: members,
  managerSessionId: '',
  createdAtMs: 10,
  updatedAtMs: 10,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manager is always a room member and malformed rows are rejected', () {
    final room = _room(members: const ['infra']);
    expect(room.memberProfiles, contains('manager'));
    expect(room.isValid, isTrue);

    expect(MissionRoom.tryParse(null), isNull);
    expect(MissionRoom.tryParse({'id': 'missing-fields'}), isNull);
    expect(
      MissionRoom.tryParse({...room.toJson(), 'manager_profile': '../unsafe'}),
      isNull,
    );
  });

  test(
    'purpose label is optional local metadata and malformed values are dropped',
    () {
      final legacy = MissionRoom.tryParse(_room().toJson());
      expect(legacy, isNotNull);
      expect(legacy!.purposeLabel, isEmpty);
      expect(legacy.toJson(), isNot(contains('purpose_label')));

      final labelled = _room(
        purposeLabel: '  Coordinar backups\ny despliegues  ',
      );
      expect(labelled.purposeLabel, 'Coordinar backups y despliegues');
      expect(
        labelled.toJson()['purpose_label'],
        'Coordinar backups y despliegues',
      );

      final overlong = MissionRoom.tryParse({
        ..._room().toJson(),
        'purpose_label': List.filled(161, '🛰️').join(),
      });
      expect(overlong, isNotNull);
      expect(overlong!.purposeLabel, isEmpty);

      final wrongType = MissionRoom.tryParse({
        ..._room().toJson(),
        'purpose_label': {'prompt': 'do work'},
      });
      expect(wrongType, isNotNull);
      expect(wrongType!.purposeLabel, isEmpty);
    },
  );

  test('purpose label remains outside prompts, RPC, Kanban and routing', () {
    const allowed = {
      'lib/core/models/mission_room.dart',
      'lib/core/services/mission_room_store.dart',
      'lib/core/screens/mission_control_screen.dart',
    };
    final leaks = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowed.contains(entity.path)) continue;
      final source = entity.readAsStringSync();
      if (source.contains('purposeLabel') || source.contains('purpose_label')) {
        leaks.add(entity.path);
      }
    }
    expect(
      leaks,
      isEmpty,
      reason:
          'El objetivo de Sala es presentación local y no puede alcanzar transporte, prompts, Kanban ni routing.',
    );
  });

  test(
    'store preserves null purpose, clears empty purpose, and omits empty JSON',
    () async {
      SharedPreferences.setMockInitialValues({});
      var clock = 5000;
      final prefs = await SharedPreferences.getInstance();
      final store = MissionRoomStore(prefs, nowMs: () => clock++);
      final created = await store.save(
        connectionId: 'conn-a',
        name: 'Homelab',
        purposeLabel: 'Operar servicios internos',
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra'],
      );
      expect(created.purposeLabel, 'Operar servicios internos');

      final preserved = await store.save(
        connectionId: 'conn-a',
        name: 'Homelab estable',
        purposeLabel: null,
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra'],
        existing: created,
      );
      expect(preserved.purposeLabel, 'Operar servicios internos');
      expect(store.load('conn-a').single.purposeLabel, preserved.purposeLabel);

      final cleared = await store.save(
        connectionId: 'conn-a',
        name: preserved.name,
        purposeLabel: '',
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra'],
        existing: preserved,
      );
      expect(cleared.purposeLabel, isEmpty);
      expect(store.load('conn-a').single.purposeLabel, isEmpty);

      final persisted =
          jsonDecode(prefs.getString('mission_control.rooms.v1.conn-a')!)
              as List<dynamic>;
      expect(persisted.single, isNot(contains('purpose_label')));
    },
  );

  test('store enforces the 160-rune purpose label boundary', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MissionRoomStore(
      await SharedPreferences.getInstance(),
      nowMs: () => 6000,
    );
    final boundary = List.filled(160, '🚀').join();
    final room = await store.save(
      connectionId: 'conn-a',
      name: 'Orbit',
      purposeLabel: boundary,
      managerProfile: 'manager',
      memberProfiles: const ['manager'],
    );
    expect(room.purposeLabel.runes.length, 160);

    await expectLater(
      store.save(
        connectionId: 'conn-a',
        name: 'Too long',
        purposeLabel: '$boundary🚀',
        managerProfile: 'manager',
        memberProfiles: const ['manager'],
      ),
      throwsArgumentError,
    );
  });

  test(
    'store isolates rooms by connection and ignores foreign persisted rows',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = MissionRoomStore(prefs, nowMs: () => 1000);

      final first = await store.save(
        connectionId: 'conn-a',
        name: 'Homelab',
        managerProfile: 'manager',
        memberProfiles: const ['infra'],
      );
      await store.save(
        connectionId: 'conn-b',
        name: 'Business',
        managerProfile: 'ceo',
        memberProfiles: const ['developer'],
      );

      expect(store.load('conn-a').map((room) => room.name), ['Homelab']);
      expect(store.load('conn-b').map((room) => room.name), ['Business']);
      expect(first.managerSessionId, isEmpty);
      expect(first.hasDurableManagerSession, isFalse);

      await prefs.setString(
        'mission_control.rooms.v1.conn-a',
        jsonEncode([
          first.toJson(),
          {...first.toJson(), 'id': 'foreign', 'connection_id': 'conn-b'},
          {'broken': true},
        ]),
      );
      expect(store.load('conn-a').map((room) => room.id), [first.id]);
    },
  );

  test('typed handle without roster selection never creates an intent', () {
    final parsed = MissionMentionParser.parse(
      room: _room(),
      text: '@infra revisa los backups',
      intentId: 'intent-1',
    );

    expect(parsed.intent, isNull);
    expect(parsed.canDispatch, isFalse);
    expect(parsed.unresolvedTypedHandles, {'infra'});
  });

  test('selected worker produces a stable idempotent intent', () {
    MissionMentionParseResult parse() => MissionMentionParser.parse(
      room: _room(),
      text: '@infra revisa los backups',
      selectedProfiles: const ['infra'],
      intentId: 'intent-1',
    );

    final first = parse();
    final second = parse();
    expect(first.canDispatch, isTrue);
    expect(first.intent!.workerProfile, 'infra');
    expect(first.intent!.taskTitle, 'revisa los backups');
    expect(first.intent!.idempotencyKey, second.intent!.idempotencyKey);
    expect(first.intent!.idempotencyKey, 'room:room-1:mention:intent-1:infra');
  });

  test('multiple selected workers are rejected instead of fan-out', () {
    final parsed = MissionMentionParser.parse(
      room: _room(members: const ['manager', 'infra', 'security']),
      text: '@infra y @security revisad el release',
      selectedProfiles: const ['infra', 'security'],
      intentId: 'intent-many',
    );

    expect(parsed.hasMultipleWorkers, isTrue);
    expect(parsed.intent, isNull);
    expect(parsed.canDispatch, isFalse);
  });

  test('manager mention is conversation-only', () {
    final parsed = MissionMentionParser.parse(
      room: _room(),
      text: '@manager prepara el plan',
      selectedProfiles: const ['manager'],
      intentId: 'intent-manager',
    );

    expect(parsed.managerMentioned, isTrue);
    expect(parsed.selectedWorkers, isEmpty);
    expect(parsed.intent, isNull);
  });

  test(
    'linked task refs retain board identity without copying tasks',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = MissionRoomStore(
        await SharedPreferences.getInstance(),
        nowMs: () => 2000,
      );
      final room = await store.save(
        connectionId: 'conn-a',
        name: 'Homelab',
        managerProfile: 'manager',
        memberProfiles: const ['infra'],
        managerSessionId: 'mob-room',
      );
      final linked = await store.linkTask(
        'conn-a',
        room.id,
        'task-real-1',
        boardId: 'homelab',
      );
      final duplicate = await store.linkTask(
        'conn-a',
        room.id,
        'task-real-1',
        boardId: 'homelab',
      );

      expect(linked.linkedTaskIds, ['task-real-1']);
      expect(linked.linkedTasks.single.boardId, 'homelab');
      expect(duplicate.linkedTaskIds, ['task-real-1']);
      expect(duplicate.toJson(), isNot(contains('task')));
    },
  );

  test(
    'authoritative manager session survives reload and rejects stale owner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = MissionRoomStore(
        await SharedPreferences.getInstance(),
        nowMs: () => 3000,
      );
      final draft = await store.save(
        connectionId: 'conn-a',
        name: 'Homelab',
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra'],
      );

      final bound = await store.bindManagerSession(
        connectionId: 'conn-a',
        roomId: draft.id,
        managerProfile: 'manager',
        managerSessionId: 'stored-manager-session',
      );

      expect(bound.managerSessionId, 'stored-manager-session');
      expect(
        store.load('conn-a').single.managerSessionId,
        'stored-manager-session',
      );
      await expectLater(
        store.bindManagerSession(
          connectionId: 'conn-a',
          roomId: draft.id,
          managerProfile: 'manager',
          managerSessionId: 'mob-provisional-client-id',
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.bindManagerSession(
          connectionId: 'conn-a',
          roomId: draft.id,
          managerProfile: 'infra',
          managerSessionId: 'wrong-owner-session',
        ),
        throwsStateError,
      );
      await expectLater(
        store.bindManagerSession(
          connectionId: 'conn-a',
          roomId: draft.id,
          managerProfile: 'manager',
          managerSessionId: 'stored\nsession',
        ),
        throwsArgumentError,
      );
    },
  );

  test('concurrent room links preserve both authoritative task refs', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MissionRoomStore(
      await SharedPreferences.getInstance(),
      nowMs: () => 3500,
    );
    final room = await store.save(
      connectionId: 'conn-a',
      name: 'Release',
      managerProfile: 'manager',
      memberProfiles: const ['manager', 'infra'],
    );

    await Future.wait([
      store.linkTask('conn-a', room.id, 'task-a', boardId: 'release'),
      store.linkTask('conn-a', room.id, 'task-b', boardId: 'release'),
    ]);

    expect(
      store.load('conn-a').single.linkedTaskIds,
      containsAll(['task-a', 'task-b']),
    );
  });

  test('linkTask fails when preferences do not confirm persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final durableStore = MissionRoomStore(prefs, nowMs: () => 3550);
    final room = await durableStore.save(
      connectionId: 'conn-a',
      name: 'Release',
      managerProfile: 'manager',
      memberProfiles: const ['manager', 'infra'],
    );
    final failingStore = MissionRoomStore(
      prefs,
      nowMs: () => 3600,
      setString: (_, _) async => false,
    );

    await expectLater(
      failingStore.linkTask(
        'conn-a',
        room.id,
        'task-not-persisted',
        boardId: 'release',
      ),
      throwsStateError,
    );
    expect(durableStore.load('conn-a').single.linkedTaskIds, isEmpty);
  });

  test('unlinkOrganization only detaches rooms in that workspace', () async {
    SharedPreferences.setMockInitialValues({});
    var clock = 4000;
    final store = MissionRoomStore(
      await SharedPreferences.getInstance(),
      nowMs: () => clock++,
    );
    final release = await store.save(
      connectionId: 'conn-a',
      name: 'Release',
      managerProfile: 'manager',
      memberProfiles: const ['manager'],
      organizationId: 'workspace-release',
    );
    final security = await store.save(
      connectionId: 'conn-a',
      name: 'Security',
      managerProfile: 'security',
      memberProfiles: const ['security'],
      organizationId: 'workspace-security',
    );

    await store.unlinkOrganization('conn-a', 'workspace-release');

    final byId = {for (final room in store.load('conn-a')) room.id: room};
    expect(byId[release.id]!.organizationId, isNull);
    expect(byId[security.id]!.organizationId, 'workspace-security');
  });

  test(
    'stale edits merge authoritative task links and manager binding',
    () async {
      SharedPreferences.setMockInitialValues({});
      var clock = 3600;
      final store = MissionRoomStore(
        await SharedPreferences.getInstance(),
        nowMs: () => clock++,
      );
      final stale = await store.save(
        connectionId: 'conn-a',
        name: 'Release',
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra'],
      );

      await store.linkTask(
        'conn-a',
        stale.id,
        'task-after-editor-opened',
        boardId: 'release',
      );
      await store.bindManagerSession(
        connectionId: 'conn-a',
        roomId: stale.id,
        managerProfile: 'manager',
        managerSessionId: 'stored-manager-after-editor-opened',
      );

      final edited = await store.save(
        connectionId: 'conn-a',
        name: 'Release final',
        managerProfile: 'manager',
        memberProfiles: const ['manager', 'infra', 'security'],
        existing: stale,
      );
      expect(edited.name, 'Release final');
      expect(edited.createdAtMs, stale.createdAtMs);
      expect(edited.managerSessionId, 'stored-manager-after-editor-opened');
      expect(edited.linkedTaskIds, ['task-after-editor-opened']);

      final reassigned = await store.save(
        connectionId: 'conn-a',
        name: edited.name,
        managerProfile: 'infra',
        memberProfiles: edited.memberProfiles,
        existing: stale,
      );
      expect(reassigned.managerSessionId, isEmpty);
      expect(reassigned.linkedTaskIds, ['task-after-editor-opened']);
    },
  );

  test('changing manager invalidates the durable manager binding', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MissionRoomStore(
      await SharedPreferences.getInstance(),
      nowMs: () => 4000,
    );
    final original = await store.save(
      connectionId: 'conn-a',
      name: 'Homelab',
      managerProfile: 'manager',
      memberProfiles: const ['manager', 'infra'],
      managerSessionId: 'stored-manager-session',
    );
    final reassigned = await store.save(
      connectionId: 'conn-a',
      name: original.name,
      managerProfile: 'infra',
      memberProfiles: const ['manager', 'infra'],
      existing: original,
    );

    expect(reassigned.managerSessionId, isEmpty);
    expect(reassigned.managerSessionId, isNot(original.managerSessionId));
  });

  test('legacy persisted mob manager ids migrate to an unbound room', () {
    final parsed = MissionRoom.tryParse({
      ..._room().toJson(),
      'manager_session_id': 'mob-old-client-draft',
    });

    expect(parsed, isNotNull);
    expect(parsed!.managerSessionId, isEmpty);
    expect(parsed.hasDurableManagerSession, isFalse);
  });

  test('persisted manager session ids with controls fail closed', () {
    expect(
      MissionRoom.tryParse({
        ..._room().toJson(),
        'manager_session_id': 'stored\u0000session',
      }),
      isNull,
    );
  });
}
