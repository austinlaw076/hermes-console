import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mission_room.dart';
import 'mission_store_mutation_queue.dart';

abstract interface class MissionRoomStoreContract {
  List<MissionRoom> load(String connectionId);

  Future<MissionRoom> save({
    required String connectionId,
    required String name,
    String? purposeLabel,
    required String managerProfile,
    required Iterable<String> memberProfiles,
    String? organizationId,
    String? managerSessionId,
    MissionRoom? existing,
  });

  Future<MissionRoom> linkTask(
    String connectionId,
    String roomId,
    String taskId, {
    required String boardId,
  });

  Future<MissionRoom> bindManagerSession({
    required String connectionId,
    required String roomId,
    required String managerProfile,
    required String managerSessionId,
  });

  Future<void> unlinkOrganization(String connectionId, String organizationId);

  Future<void> delete(String connectionId, String roomId);
}

final class MissionRoomStore implements MissionRoomStoreContract {
  static const _keyPrefix = 'mission_control.rooms.v1.';
  static const _maxRooms = 50;

  final SharedPreferences _prefs;
  final Uuid uuid;
  final int Function() nowMs;
  final Future<bool> Function(String key, String value) _setString;

  MissionRoomStore(
    SharedPreferences prefs, {
    this.uuid = const Uuid(),
    int Function()? nowMs,
    Future<bool> Function(String key, String value)? setString,
  }) : _prefs = prefs,
       nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _setString = setString ?? prefs.setString;

  String _key(String connectionId) => '$_keyPrefix$connectionId';

  @override
  List<MissionRoom> load(String connectionId) {
    final raw = _prefs.getString(_key(connectionId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final byId = <String, MissionRoom>{};
      for (final value in decoded.take(_maxRooms)) {
        final room = MissionRoom.tryParse(value);
        if (room == null || room.connectionId != connectionId) continue;
        byId[room.id] = room;
      }
      final result = byId.values.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      return List.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<MissionRoom> save({
    required String connectionId,
    required String name,
    String? purposeLabel,
    required String managerProfile,
    required Iterable<String> memberProfiles,
    String? organizationId,
    String? managerSessionId,
    MissionRoom? existing,
  }) => MissionStoreMutationQueue.run(() async {
    final safeName = name
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
        .trim();
    if (safeName.isEmpty || safeName.runes.length > 64) {
      throw ArgumentError.value(
        name,
        'name',
        'must contain 1 to 64 characters',
      );
    }
    final safePurposeLabel = purposeLabel
        ?.replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
        .trim();
    if (safePurposeLabel != null &&
        safePurposeLabel.runes.length > MissionRoom.maxPurposeLabelRunes) {
      throw ArgumentError.value(
        purposeLabel,
        'purposeLabel',
        'must contain at most ${MissionRoom.maxPurposeLabelRunes} characters',
      );
    }
    if (existing != null && existing.connectionId != connectionId) {
      throw StateError('Room belongs to another instance');
    }
    final current = load(connectionId).toList();
    final roomId = existing?.id ?? uuid.v4();
    final index = current.indexWhere((item) => item.id == roomId);
    if (existing != null && index < 0) {
      // The editor may have kept a snapshot while another surface deleted the
      // Room. Recreating it from stale state would also resurrect obsolete
      // bindings and task references, so edits fail closed.
      throw StateError('Room not found');
    }
    final latestExisting = index >= 0 ? current[index] : null;
    final now = nowMs();
    final managerChanged =
        latestExisting != null &&
        latestExisting.managerProfile != managerProfile.trim();
    final room = MissionRoom(
      id: roomId,
      connectionId: connectionId,
      organizationId: organizationId,
      name: safeName,
      purposeLabel: safePurposeLabel ?? latestExisting?.purposeLabel ?? '',
      managerProfile: managerProfile,
      memberProfiles: memberProfiles,
      // A Room is persisted before its chat exists. Keep that state empty;
      // only `bindManagerSession` may install the opaque id returned by the
      // canonical Hermes session lifecycle. Persisting a generated `mob-*`
      // draft here made local/Bridge chats look durable when they are not.
      managerSessionId: managerChanged
          ? ''
          : managerSessionId ?? latestExisting?.managerSessionId ?? '',
      // linkTask/bindManagerSession may have advanced after the editor loaded
      // [existing]. Their latest queued values are authoritative metadata;
      // only the editable Room fields above come from the submitted form.
      linkedTasks: latestExisting?.linkedTasks ?? const [],
      createdAtMs: latestExisting?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    if (!room.isValid) {
      throw ArgumentError('Room requires a valid manager and member roster');
    }
    if (index >= 0) {
      current[index] = room;
    } else {
      if (current.length >= _maxRooms) throw StateError('Room limit reached');
      current.add(room);
    }
    await _write(connectionId, current);
    return room;
  });

  @override
  Future<MissionRoom> linkTask(
    String connectionId,
    String roomId,
    String taskId, {
    required String boardId,
  }) => MissionStoreMutationQueue.run(() async {
    final current = load(connectionId).toList();
    final index = current.indexWhere((room) => room.id == roomId);
    if (index < 0) throw StateError('Room not found');
    final updated = current[index].withLinkedTask(
      taskId,
      boardId: boardId,
      updatedAtMs: nowMs(),
    );
    current[index] = updated;
    await _write(connectionId, current);
    return updated;
  });

  @override
  Future<MissionRoom> bindManagerSession({
    required String connectionId,
    required String roomId,
    required String managerProfile,
    required String managerSessionId,
  }) => MissionStoreMutationQueue.run(() async {
    final profile = managerProfile.trim();
    final sessionId = managerSessionId.trim();
    if (!MissionRoom.isDurableManagerSessionId(sessionId)) {
      throw ArgumentError.value(
        managerSessionId,
        'managerSessionId',
        'must be the durable opaque id confirmed by Hermes',
      );
    }
    final current = load(connectionId).toList();
    final index = current.indexWhere((room) => room.id == roomId);
    if (index < 0) throw StateError('Room not found');
    final room = current[index];
    if (room.managerProfile != profile) {
      throw StateError('Room manager changed while binding the session');
    }
    if (room.managerSessionId == sessionId) return room;
    final updated = room.copyWith(
      managerSessionId: sessionId,
      updatedAtMs: nowMs(),
    );
    current[index] = updated;
    await _write(connectionId, current);
    return updated;
  });

  @override
  Future<void> unlinkOrganization(String connectionId, String organizationId) =>
      MissionStoreMutationQueue.run(() async {
        final organization = organizationId.trim();
        if (organization.isEmpty) return;
        final current = load(connectionId).toList();
        var changed = false;
        for (var index = 0; index < current.length; index++) {
          final room = current[index];
          if (room.organizationId != organization) continue;
          current[index] = room.copyWith(
            clearOrganization: true,
            updatedAtMs: nowMs(),
          );
          changed = true;
        }
        if (changed) await _write(connectionId, current);
      });

  @override
  Future<void> delete(String connectionId, String roomId) =>
      MissionStoreMutationQueue.run(() async {
        final current = load(
          connectionId,
        ).where((room) => room.id != roomId).toList();
        await _write(connectionId, current);
      });

  Future<void> _write(String connectionId, Iterable<MissionRoom> rooms) async {
    final persisted = await _setString(
      _key(connectionId),
      jsonEncode(rooms.map((room) => room.toJson()).toList()),
    );
    if (!persisted) {
      throw StateError('Room persistence was not confirmed');
    }
  }
}
