import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mission_control.dart';
import 'mission_store_mutation_queue.dart';

abstract interface class MissionOrganizationStoreContract {
  List<MissionOrganization> load(String connectionId);

  Future<MissionOrganization> save({
    required String connectionId,
    required String name,
    required Iterable<String> profileNames,
    MissionOrganization? existing,
    String? managerProfile,
  });

  Future<void> delete(String connectionId, String organizationId);
}

final class MissionOrganizationStore
    implements MissionOrganizationStoreContract {
  static const _keyPrefix = 'mission_control.organizations.v1.';
  static const _maxOrganizations = 50;

  final SharedPreferences _prefs;
  final Uuid uuid;
  final Future<bool> Function(String key, String value) _setString;

  MissionOrganizationStore(
    SharedPreferences prefs, {
    this.uuid = const Uuid(),
    Future<bool> Function(String key, String value)? setString,
  }) : _prefs = prefs,
       _setString = setString ?? prefs.setString;

  String _key(String connectionId) => '$_keyPrefix$connectionId';

  @override
  List<MissionOrganization> load(String connectionId) {
    final raw = _prefs.getString(_key(connectionId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final byId = <String, MissionOrganization>{};
      for (final value in decoded.take(_maxOrganizations)) {
        final organization = MissionOrganization.tryParse(value);
        if (organization == null || organization.connectionId != connectionId) {
          continue;
        }
        byId[organization.id] = organization;
      }
      final result = byId.values.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      return List.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<MissionOrganization> save({
    required String connectionId,
    required String name,
    required Iterable<String> profileNames,
    MissionOrganization? existing,
    String? managerProfile,
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
    if (existing != null && existing.connectionId != connectionId) {
      throw StateError('Organization belongs to another instance');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final organization = MissionOrganization(
      id: existing?.id ?? uuid.v4(),
      connectionId: connectionId,
      name: safeName,
      profileNames: profileNames,
      managerProfile: managerProfile,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    final current = load(connectionId).toList();
    final index = current.indexWhere((item) => item.id == organization.id);
    if (index >= 0) {
      current[index] = organization;
    } else {
      if (current.length >= _maxOrganizations) {
        throw StateError('Organization limit reached');
      }
      current.add(organization);
    }
    await _write(connectionId, current);
    return organization;
  });

  @override
  Future<void> delete(String connectionId, String organizationId) =>
      MissionStoreMutationQueue.run(() async {
        final current = load(
          connectionId,
        ).where((organization) => organization.id != organizationId).toList();
        await _write(connectionId, current);
      });

  Future<void> _write(
    String connectionId,
    Iterable<MissionOrganization> organizations,
  ) async {
    final persisted = await _setString(
      _key(connectionId),
      jsonEncode(organizations.map((value) => value.toJson()).toList()),
    );
    if (!persisted) {
      throw StateError('Organization persistence was not confirmed');
    }
  }
}
