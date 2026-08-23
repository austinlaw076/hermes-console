import 'dart:async';

import '../models/agent_profile.dart';
import '../models/kanban.dart';
import '../models/mission_control.dart';
import 'connection_manager.dart';
import 'kanban_client.dart';
import 'tui_gateway_client.dart';

typedef MissionProfilesLoader = Future<List<AgentProfile>> Function();
typedef MissionSessionsLoader = Future<List<Session>> Function();
typedef MissionBoardLoader = Future<KanbanBoard> Function();
typedef MissionKanbanEventsLoader = Stream<KanbanEvent> Function(int since);
typedef MissionDashboardGet =
    Future<Map<String, dynamic>> Function(String endpoint);
typedef MissionProfileAvatarLoader =
    Future<AgentProfileAvatar?> Function(String profileName);

Future<List<AgentProfile>> loadMissionControlProfiles({
  required MissionProfilesLoader desktopLoader,
  required MissionProfilesLoader legacyDashboardLoader,
}) async {
  try {
    return await desktopLoader();
  } on TuiGatewayRpcError catch (error) {
    if (error.code != -32601 && error.code != 404 && error.code != 405) {
      rethrow;
    }
    return legacyDashboardLoader();
  }
}

/// Loads the same aggregate, profile-owned session surface used by Hermes
/// Desktop. Legacy Gateways are consulted only when the aggregate route is
/// structurally unsupported; auth, network and malformed responses fail
/// closed so a partial default-profile list cannot masquerade as complete.
Future<List<Session>> loadMissionControlSessions({
  required MissionDashboardGet dashboardGet,
  required MissionSessionsLoader legacyGatewayLoader,
}) async {
  final query = Uri(
    queryParameters: const {
      'profile': 'all',
      'limit': '200',
      'offset': '0',
      'min_messages': '0',
      'archived': 'exclude',
      'order': 'recent',
      'full': '1',
      'include_children': 'true',
    },
  ).query;
  late final Map<String, dynamic> data;
  try {
    data = await dashboardGet('profiles/sessions?$query');
  } on DashboardHttpException catch (error) {
    if (error.statusCode != 404 && error.statusCode != 405) rethrow;
    return legacyGatewayLoader();
  }
  final errors = data['errors'];
  final hasPartialErrors = switch (errors) {
    null => false,
    List value => value.isNotEmpty,
    Map value => value.isNotEmpty,
    String value => value.trim().isNotEmpty,
    _ => true,
  };
  if (hasPartialErrors) {
    throw const FormatException('Partial aggregate session response');
  }
  final raw = data['sessions'] ?? data['data'];
  if (raw is! List) {
    throw const FormatException('Malformed aggregate session response');
  }
  final sessions = <Session>[];
  for (final value in raw) {
    final session = Session.tryParse(value);
    if (session == null) {
      throw const FormatException('Malformed aggregate session row');
    }
    if ((session.profile ?? '').trim().isEmpty) {
      throw const FormatException('Aggregate session owner is missing');
    }
    if (!session.id.startsWith('mob-aux-')) sessions.add(session);
  }
  return List<Session>.unmodifiable(sessions);
}

abstract interface class MissionControlDataSource {
  Future<MissionBackendSnapshot> load();
  Stream<KanbanEvent>? watchKanban({required int since});
  void close();
}

/// Extensión opcional para identidades visuales de Bot Mode/Hermes Desktop.
/// Los fakes y Gateways antiguos pueden implementar sólo el snapshot base.
abstract interface class MissionProfileAvatarDataSource {
  Future<AgentProfileAvatar?> loadProfileAvatar(String profileName);
}

final class MissionControlRepository
    implements MissionControlDataSource, MissionProfileAvatarDataSource {
  final MissionProfilesLoader profilesLoader;
  final MissionSessionsLoader sessionsLoader;
  final MissionBoardLoader boardLoader;
  final MissionKanbanEventsLoader? kanbanEventsLoader;
  final MissionProfileAvatarLoader? profileAvatarLoader;
  final void Function()? onClose;
  bool _closed = false;

  MissionControlRepository({
    required this.profilesLoader,
    required this.sessionsLoader,
    required this.boardLoader,
    this.kanbanEventsLoader,
    this.profileAvatarLoader,
    this.onClose,
  });

  factory MissionControlRepository.forConnection(SavedConnection connection) {
    final dashboard = DashboardClient.lazy(connection);
    final gateway = ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: connection.apiKey,
      connectionId: connection.id,
    );
    final kanban = KanbanClient(connection, dashboardClient: dashboard);
    final desktop = TuiGatewayClient(connection, dashboard: dashboard);
    return MissionControlRepository(
      profilesLoader: () => loadMissionControlProfiles(
        // One profiles.list snapshot now carries Desktop's last/preferred
        // session projections and hidden worker liveness. Older Gateways omit
        // those optional fields and keep returning the same profile roster.
        desktopLoader: () => desktop.listProfiles(includeSessions: true),
        legacyDashboardLoader: dashboard.getProfiles,
      ),
      sessionsLoader: () => loadMissionControlSessions(
        dashboardGet: dashboard.apiGet,
        legacyGatewayLoader: () => gateway.getSessions(includeChildren: true),
      ),
      boardLoader: kanban.getCurrentBoard,
      kanbanEventsLoader: (since) => kanban.events(since: since),
      profileAvatarLoader: desktop.profileAvatar,
      onClose: () {
        unawaited(desktop.close());
        kanban.close();
        gateway.close();
      },
    );
  }

  @override
  Stream<KanbanEvent>? watchKanban({required int since}) {
    if (_closed) throw StateError('MissionControlRepository is closed');
    return kanbanEventsLoader?.call(since);
  }

  @override
  Future<AgentProfileAvatar?> loadProfileAvatar(String profileName) {
    if (_closed) throw StateError('MissionControlRepository is closed');
    final loader = profileAvatarLoader;
    if (loader == null) return Future.value();
    return loader(profileName);
  }

  @override
  Future<MissionBackendSnapshot> load() async {
    if (_closed) throw StateError('MissionControlRepository is closed');
    final results = await Future.wait<Object>([
      _capture(profilesLoader),
      _capture(sessionsLoader),
      _capture(boardLoader),
    ]);
    final profilesResult = results[0] as _MissionLoadResult<List<AgentProfile>>;
    final sessionsResult = results[1] as _MissionLoadResult<List<Session>>;
    final boardResult = results[2] as _MissionLoadResult<KanbanBoard>;
    final failures = <String, Object>{
      'profiles': ?profilesResult.error,
      'sessions': ?sessionsResult.error,
      'kanban': ?boardResult.error,
    };
    return MissionBackendSnapshot(
      profiles: profilesResult.value ?? const [],
      sessions: sessionsResult.value ?? const [],
      board: boardResult.value,
      profilesCapability: _capability(profilesResult),
      sessionsCapability: _capability(sessionsResult),
      kanbanCapability: _capability(boardResult),
      failures: failures,
      loadedAt: DateTime.now(),
    );
  }

  static Future<_MissionLoadResult<T>> _capture<T>(
    Future<T> Function() action,
  ) async {
    try {
      return _MissionLoadResult<T>(value: await action());
    } catch (error) {
      return _MissionLoadResult<T>(error: error);
    }
  }

  static MissionCapabilityState _capability<T>(_MissionLoadResult<T> result) {
    if (result.value != null) return MissionCapabilityState.available;
    return _isUnsupported(result.error)
        ? MissionCapabilityState.unsupported
        : MissionCapabilityState.unavailable;
  }

  static bool _isUnsupported(Object? error) {
    if (error is DashboardHttpException) {
      return error.statusCode == 404 || error.statusCode == 405;
    }
    final text = error.toString().toLowerCase();
    return text.contains('http 404') || text.contains('http 405');
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    onClose?.call();
  }
}

final class _MissionLoadResult<T> {
  final T? value;
  final Object? error;

  const _MissionLoadResult({this.value, this.error});
}
