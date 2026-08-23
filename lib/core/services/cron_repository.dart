import '../models/cron_job.dart';
import 'connection_manager.dart';

enum CronProfileScope { active, all }

const _cronCleanupPageSize = 100;
const _cronCleanupBatchSize = 500;

/// Snapshot que el usuario confirma antes de borrar conversaciones de Cron.
///
/// Conserva las sesiones, y no solo el contador, para que la acción destructiva
/// borre exactamente la selección que se mostró en el diálogo. Una ejecución
/// nueva creada después de la confirmación queda fuera.
class CronConversationCleanupPreview {
  final List<Session> sessions;

  CronConversationCleanupPreview(Iterable<Session> sessions)
    : sessions = List<Session>.unmodifiable(sessions);

  int get count => sessions.length;
  bool get isEmpty => sessions.isEmpty;
}

class CronConversationCleanupResult {
  final int requested;
  final int deleted;

  const CronConversationCleanupResult({
    required this.requested,
    required this.deleted,
  });

  int get preserved => requested - deleted;
}

/// Defensa local adicional al filtro `source=cron` del Dashboard.
///
/// Deduplica por ID y nunca permite que una respuesta defectuosa mezcle una
/// conversación normal en la selección destructiva. `isActive` es la señal
/// autoritativa del Dashboard: las versiones actuales la apagan cuando una
/// fila sin `ended_at` lleva más de cinco minutos sin actividad. Así se pueden
/// limpiar huérfanas antiguas sin tratar como borrable una ejecución viva. En
/// servidores legacy que no publican `is_active`, [Session.fromJson] sigue
/// fallando cerrado y deriva `true` de la ausencia de `ended_at`.
List<Session> cronSessionsSafeForCleanup(Iterable<Session> sessions) {
  final byId = <String, Session>{};
  for (final session in sessions) {
    if (!session.isJob ||
        session.id.trim().isEmpty ||
        session.isActive ||
        session.pinned == true) {
      continue;
    }
    byId.putIfAbsent(session.id, () => session);
  }
  return List<Session>.unmodifiable(byId.values);
}

class CronJobListing {
  final List<CronJob> jobs;
  final CronProfileScope requestedScope;
  final bool usedLegacyActiveFallback;

  const CronJobListing({
    required this.jobs,
    required this.requestedScope,
    this.usedLegacyActiveFallback = false,
  });
}

/// Contrato móvil de Cron, construido sobre los mismos endpoints que Desktop.
class CronRepository {
  final DashboardClient client;
  final String profile;

  const CronRepository(this.client, {this.profile = ''});

  String get _cleanupProfile {
    final selected = profile.trim();
    return selected.isEmpty ? 'default' : selected;
  }

  String _query({bool hasQuery = false}) {
    if (profile.isEmpty) return '';
    return '${hasQuery ? '&' : '?'}profile=${Uri.encodeQueryComponent(profile)}';
  }

  Future<List<CronJob>> listJobs() async =>
      (await listJobsForScope(CronProfileScope.active)).jobs;

  /// Amplía la consulta a todos los perfiles sin cambiar [profile], que sigue
  /// siendo el perfil operativo usado por CRUD. Dashboards anteriores a
  /// `profile=all` degradan a la lectura del perfil activo.
  Future<CronJobListing> listJobsForScope(CronProfileScope scope) async {
    if (scope == CronProfileScope.active) {
      return CronJobListing(
        jobs: await _listJobsWithProfile(profile),
        requestedScope: scope,
      );
    }
    try {
      return CronJobListing(
        jobs: await _listJobsWithProfile('all'),
        requestedScope: scope,
      );
    } on DashboardHttpException catch (error) {
      if (!_isUnsupportedAllProfiles(error.statusCode)) rethrow;
      return CronJobListing(
        jobs: await _listJobsWithProfile(profile),
        requestedScope: scope,
        usedLegacyActiveFallback: true,
      );
    }
  }

  Future<List<CronJob>> _listJobsWithProfile(String selectedProfile) async {
    final suffix = selectedProfile.isEmpty
        ? ''
        : '?profile=${Uri.encodeQueryComponent(selectedProfile)}';
    final data = await client.apiGetList('cron/jobs$suffix');
    return data
        .whereType<Map>()
        .map((value) => CronJob.fromJson(value.cast<String, dynamic>()))
        .where((job) => job.id.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isUnsupportedAllProfiles(int statusCode) =>
      statusCode == 400 ||
      statusCode == 404 ||
      statusCode == 405 ||
      statusCode == 422 ||
      statusCode == 501;

  Future<CronJob?> getJob(String id) async {
    try {
      final job = CronJob.fromJson(
        await client.apiGet('cron/jobs/${Uri.encodeComponent(id)}${_query()}'),
      );
      return job.id.isEmpty ? null : job;
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<CronRuns> listRuns(String id, {int limit = 20}) async {
    try {
      final data = await client.apiGet(
        'cron/jobs/${Uri.encodeComponent(id)}/runs?limit=$limit${_query(hasQuery: true)}',
      );
      final raw = data['runs'] ?? data['data'];
      final sessions = (raw as List? ?? const [])
          .map(Session.tryParse)
          .whereType<Session>()
          .toList(growable: false);
      return CronRuns(sessions);
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const CronRuns([], available: false);
      }
      rethrow;
    }
  }

  /// Carga todas las conversaciones Cron del perfil activo, incluidas las
  /// archivadas, sin tocar programaciones. El endpoint y la paginación son los
  /// mismos del Dashboard oficial de Hermes Agent 0.20.
  Future<List<Session>> _listCronConversationSessions() async {
    final sessionsById = <String, Session>{};
    var offset = 0;
    int? expectedTotal;

    while (true) {
      final params = <String, String>{
        'source': 'cron',
        'archived': 'include',
        'order': 'recent',
        'limit': '$_cronCleanupPageSize',
        'offset': '$offset',
        'min_messages': '0',
        'full': '0',
        'profile': _cleanupProfile,
      };
      final data = await client.apiGet(
        'sessions?${Uri(queryParameters: params).query}',
      );
      final rawRows = data['sessions'];
      if (rawRows is! List) {
        throw const FormatException('Invalid Cron session listing');
      }

      final previousCount = sessionsById.length;
      for (final rawRow in rawRows) {
        final session = Session.tryParse(rawRow);
        if (session == null ||
            !session.isJob ||
            session.id.trim().isEmpty ||
            sessionsById.containsKey(session.id)) {
          throw const FormatException('Ambiguous Cron session listing');
        }
        sessionsById[session.id] = session;
      }

      final rawTotal = data['total'];
      if (rawTotal != null) {
        if (rawTotal is! num ||
            !rawTotal.isFinite ||
            rawTotal < 0 ||
            rawTotal.toInt() != rawTotal) {
          throw const FormatException('Invalid Cron session total');
        }
        final pageTotal = rawTotal.toInt();
        if (expectedTotal != null && expectedTotal != pageTotal) {
          throw const FormatException('Cron session total changed');
        }
        expectedTotal = pageTotal;
      }

      if (rawRows.isEmpty) {
        if (expectedTotal != null && offset < expectedTotal) {
          throw const FormatException('Incomplete Cron session listing');
        }
        break;
      }

      offset += _cronCleanupPageSize;
      if (expectedTotal != null) {
        if (offset >= expectedTotal) break;
        if (sessionsById.length == previousCount) {
          throw const FormatException(
            'Cron session pagination did not advance',
          );
        }
      } else if (rawRows.length < _cronCleanupPageSize) {
        break;
      } else if (sessionsById.length == previousCount) {
        throw const FormatException('Cron session pagination did not advance');
      }
    }

    if (expectedTotal != null && sessionsById.length != expectedTotal) {
      throw const FormatException('Cron session total does not match rows');
    }
    return List<Session>.unmodifiable(sessionsById.values);
  }

  Future<CronConversationCleanupPreview> previewConversationCleanup() async {
    final sessions = await _listCronConversationSessions();
    return CronConversationCleanupPreview(cronSessionsSafeForCleanup(sessions));
  }

  /// Borra exclusivamente el snapshot de conversaciones Cron confirmado por
  /// el usuario. `POST /api/sessions/bulk-delete` limita cada transacción a
  /// 500 IDs; servidores antiguos degradan al DELETE individual que usa
  /// Hermes Desktop. Ningún camino llama a `/api/cron/jobs`.
  Future<CronConversationCleanupResult> deleteCronConversations(
    CronConversationCleanupPreview preview,
  ) async {
    final safeSessions = cronSessionsSafeForCleanup(preview.sessions);
    final previewIds = preview.sessions.map((session) => session.id).toSet();
    if (safeSessions.length != previewIds.length) {
      throw StateError('Cron cleanup selection contains a non-Cron session');
    }
    if (safeSessions.isEmpty) {
      return const CronConversationCleanupResult(requested: 0, deleted: 0);
    }

    final confirmedLogicalIds = safeSessions
        .map((session) => session.logicalId)
        .toSet();
    // Revalida el snapshot antes del primer DELETE. Una conversación que pasó
    // a activa/fijada o un listado cuyo total ya no es coherente falla cerrado
    // o queda preservado sin alcanzar el endpoint destructivo.
    var inventory = await _listCronConversationSessions();
    var pending = cronSessionsSafeForCleanup(
      inventory.where(
        (session) => confirmedLogicalIds.contains(session.logicalId),
      ),
    );
    var lineagePasses = 0;

    while (pending.isNotEmpty && lineagePasses < 64) {
      lineagePasses++;
      final attemptedIds = pending.map((session) => session.id).toSet();
      await _deleteCronSessionIds(pending);

      // El listado proyecta una cadena compactada a su punta. Al borrar esa
      // punta, la raíz o una continuación anterior puede volver a aflorar. Se
      // elimina únicamente si conserva el logicalId que el usuario confirmó;
      // una ejecución nueva de la misma tarea tiene otro logicalId y queda fuera.
      inventory = await _listCronConversationSessions();
      final matching = inventory.where(
        (session) => confirmedLogicalIds.contains(session.logicalId),
      );
      final nextPending = cronSessionsSafeForCleanup(matching);
      final nextIds = nextPending.map((session) => session.id).toSet();
      if (nextIds.isEmpty || nextIds.difference(attemptedIds).isEmpty) break;
      pending = nextPending;
    }

    final remainingLogicalIds = inventory
        .where((session) => confirmedLogicalIds.contains(session.logicalId))
        .map((session) => session.logicalId)
        .toSet();
    return CronConversationCleanupResult(
      requested: confirmedLogicalIds.length,
      deleted: confirmedLogicalIds.length - remainingLogicalIds.length,
    );
  }

  Future<void> _deleteCronSessionIds(List<Session> safeSessions) async {
    var bulkDeleteSupported = true;
    for (
      var start = 0;
      start < safeSessions.length;
      start += _cronCleanupBatchSize
    ) {
      final end = (start + _cronCleanupBatchSize).clamp(0, safeSessions.length);
      final batch = safeSessions.sublist(start, end);
      final ids = batch.map((session) => session.id).toList(growable: false);

      if (bulkDeleteSupported) {
        try {
          final response = await client.apiPost(
            'sessions/bulk-delete',
            body: {'ids': ids, 'profile': _cleanupProfile},
          );
          final rawDeleted = response['deleted'];
          if (response['ok'] != true ||
              rawDeleted is! num ||
              !rawDeleted.isFinite ||
              rawDeleted < 0 ||
              rawDeleted > ids.length) {
            throw const FormatException('Invalid Cron bulk-delete response');
          }
          continue;
        } on DashboardHttpException catch (error) {
          if (!_isUnsupportedBulkDelete(error.statusCode)) rethrow;
          bulkDeleteSupported = false;
        }
      }

      for (final id in ids) {
        try {
          await client.apiDelete(
            'sessions/${Uri.encodeComponent(id)}?profile='
            '${Uri.encodeQueryComponent(_cleanupProfile)}',
          );
        } on DashboardHttpException catch (error) {
          // Carrera idempotente: otra pestaña pudo borrar la fila tras el
          // preview. Cualquier otro estado se propaga y no se disfraza.
          if (error.statusCode != 404) rethrow;
        }
      }
    }
  }

  static bool _isUnsupportedBulkDelete(int statusCode) =>
      statusCode == 404 || statusCode == 405 || statusCode == 501;

  Future<List<CronDeliveryTarget>> deliveryTargets() async {
    try {
      final data = await client.apiGet('cron/delivery-targets');
      final targets = (data['targets'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                CronDeliveryTarget.fromJson(value.cast<String, dynamic>()),
          )
          .where((value) => value.id.isNotEmpty)
          .toList(growable: false);
      return targets.isEmpty ? const [CronDeliveryTarget.local] : targets;
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const [CronDeliveryTarget.local];
      }
      rethrow;
    }
  }

  Future<List<AutomationBlueprint>> blueprints() async {
    try {
      final data = await client.apiGet('cron/blueprints');
      return (data['blueprints'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                AutomationBlueprint.fromJson(value.cast<String, dynamic>()),
          )
          .where((value) => value.key.isNotEmpty)
          .toList(growable: false);
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) return const [];
      rethrow;
    }
  }

  Future<List<ModelProvider>> modelOptions() async {
    try {
      return await client.getModelOptions(
        profile: profile.isEmpty ? null : profile,
        explicitOnly: true,
      );
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) return const [];
      rethrow;
    }
  }

  Future<CronEditorResources> editorResources() async {
    Future<List<CronDeliveryTarget>> safeTargets() async {
      try {
        return await deliveryTargets();
      } catch (_) {
        return const [CronDeliveryTarget.local];
      }
    }

    Future<List<ModelProvider>> safeModels() async {
      try {
        return await modelOptions();
      } catch (_) {
        return const [];
      }
    }

    Future<List<AutomationBlueprint>> safeBlueprints() async {
      try {
        return await blueprints();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait<Object>([
      safeTargets(),
      safeModels(),
      safeBlueprints(),
    ]);
    return CronEditorResources(
      deliveryTargets: results[0] as List<CronDeliveryTarget>,
      modelProviders: results[1] as List<ModelProvider>,
      blueprints: results[2] as List<AutomationBlueprint>,
    );
  }

  Future<CronJob> create({
    required String name,
    required String prompt,
    required String schedule,
    required String deliver,
    required String model,
    required String provider,
  }) async {
    final data = await client.apiPost(
      'cron/jobs${_query()}',
      body: {
        'prompt': prompt,
        'schedule': schedule,
        if (name.isNotEmpty) 'name': name,
        'deliver': deliver.isEmpty ? 'local' : deliver,
        if (model.isNotEmpty) 'model': model,
        if (model.isNotEmpty && provider.isNotEmpty) 'provider': provider,
      },
    );
    return CronJob.fromJson(data);
  }

  Future<CronJob> update(
    CronJob job, {
    required String name,
    required String prompt,
    required String schedule,
    required String deliver,
    required String model,
    required String provider,
  }) async {
    final updates = <String, dynamic>{
      'name': name,
      'schedule': schedule,
      'deliver': deliver,
      if (!job.isScriptOnly || prompt.isNotEmpty) 'prompt': prompt,
      if (!job.isScriptOnly) 'model': model.isEmpty ? null : model,
      if (!job.isScriptOnly) 'provider': provider.isEmpty ? null : provider,
    };
    final data = await client.apiPut(
      'cron/jobs/${Uri.encodeComponent(job.id)}${_query()}',
      body: {'updates': updates},
    );
    return CronJob.fromJson(data);
  }

  Future<CronJob> pauseOrResume(CronJob job) async {
    final action = job.isPaused ? 'resume' : 'pause';
    final data = await client.apiPost(
      'cron/jobs/${Uri.encodeComponent(job.id)}/$action${_query()}',
    );
    return CronJob.fromJson(data);
  }

  Future<CronJob> trigger(CronJob job) async {
    final data = await client.apiPost(
      'cron/jobs/${Uri.encodeComponent(job.id)}/trigger${_query()}',
    );
    return CronJob.fromJson(data);
  }

  Future<CronJob> instantiateBlueprint(
    AutomationBlueprint blueprint,
    Map<String, String> values,
  ) async {
    final targetProfile = profile.isEmpty ? 'default' : profile;
    final data = await client.apiPost(
      'cron/blueprints/instantiate?profile=${Uri.encodeQueryComponent(targetProfile)}',
      body: {'blueprint': blueprint.key, 'values': values},
    );
    return CronJob.fromJson(data);
  }
}
