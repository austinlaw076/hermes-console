import '../models/capability_descriptor.dart';

/// Registro de capacidades aislado por conexión, identidad backend y epoch.
final class CapabilityRegistry {
  final String connectionId;
  final DateTime Function() _now;
  final Duration freshness;

  BackendIdentity _backendIdentity;
  int _connectionEpoch;
  int _revision = 0;
  final Map<String, CapabilityDescriptor> _descriptors = {};
  final Map<String, CapabilityDescriptor> _backendUnsupported = {};

  // El nombre público `backendIdentity` no expone el campo mutable privado.
  // ignore: prefer_initializing_formals
  CapabilityRegistry({
    required this.connectionId,
    required BackendIdentity backendIdentity,
    required int connectionEpoch,
    this.freshness = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : // El nombre público evita exponer el campo mutable privado.
       // ignore: prefer_initializing_formals
       _backendIdentity = backendIdentity,
       _connectionEpoch = connectionEpoch,
       _now = now ?? DateTime.now {
    if (connectionId.trim().isEmpty || connectionEpoch < 0) {
      throw const FormatException('invalid capability registry scope');
    }
  }

  BackendIdentity get backendIdentity => _backendIdentity;
  int get connectionEpoch => _connectionEpoch;
  int get revision => _revision;

  List<CapabilityDescriptor> get descriptors =>
      List<CapabilityDescriptor>.unmodifiable(_descriptors.values);

  CapabilityDescriptor? lookup(String key) {
    final normalized = _normalizeKey(key);
    final descriptor = _descriptors[normalized];
    if (descriptor == null) return null;
    if (!descriptor.isFresh(_now(), freshness) &&
        descriptor.state != CapabilityState.unsupported) {
      _descriptors.remove(normalized);
      _revision++;
      return null;
    }
    return descriptor;
  }

  CapabilityDescriptor stateFor(
    String key, {
    OperationScope scope = OperationScope.instance,
    OperationRisk risk = OperationRisk.medium,
  }) =>
      lookup(key) ??
      CapabilityDescriptor.unknown(
        key: key,
        checkedAt: _now(),
        connectionEpoch: _connectionEpoch,
        scope: scope,
        risk: risk,
      );

  /// Registra evidencia si pertenece al epoch actual y es más reciente/fuerte.
  /// Devuelve true solo cuando cambia el estado efectivo.
  bool record(CapabilityDescriptor incoming) {
    if (incoming.connectionEpoch != _connectionEpoch) return false;
    final existing = _descriptors[incoming.key];
    if (existing != null && !_shouldReplace(existing, incoming)) return false;

    _descriptors[incoming.key] = incoming;
    if (incoming.state == CapabilityState.unsupported) {
      _backendUnsupported[incoming.key] = incoming;
    } else if (incoming.state == CapabilityState.available ||
        incoming.state == CapabilityState.legacy) {
      _backendUnsupported.remove(incoming.key);
    }
    _revision++;
    return true;
  }

  bool recordEvidence({
    required String key,
    required CapabilityState state,
    required CapabilitySource source,
    required OperationScope scope,
    required OperationRisk risk,
    bool requiresRuntime = false,
    bool requiresLocalGateway = false,
    bool readOnlyAllowed = false,
    int? maxPayload,
    int? maxRows,
    CapabilityReason? reason,
    DateTime? checkedAt,
  }) => record(
    CapabilityDescriptor(
      key: key,
      state: state,
      source: source,
      scope: scope,
      risk: risk,
      requiresRuntime: requiresRuntime,
      requiresLocalGateway: requiresLocalGateway,
      readOnlyAllowed: readOnlyAllowed,
      maxPayload: maxPayload,
      maxRows: maxRows,
      reason: reason,
      checkedAt: checkedAt ?? _now(),
      connectionEpoch: _connectionEpoch,
    ),
  );

  /// Invalida evidencia ligada al socket. `unsupported` sobrevive únicamente
  /// cuando la identidad del contrato remoto sigue siendo la misma.
  void beginConnectionEpoch(
    int epoch, {
    required BackendIdentity backendIdentity,
  }) {
    if (epoch < 0) throw const FormatException('invalid connection epoch');
    final sameBackend = backendIdentity == _backendIdentity;
    _backendIdentity = backendIdentity;
    _connectionEpoch = epoch;
    _descriptors.clear();
    if (!sameBackend) _backendUnsupported.clear();

    if (sameBackend) {
      for (final cached in _backendUnsupported.values) {
        _descriptors[cached.key] = CapabilityDescriptor(
          key: cached.key,
          state: CapabilityState.unsupported,
          source: CapabilitySource.cache,
          scope: cached.scope,
          risk: cached.risk,
          requiresRuntime: cached.requiresRuntime,
          requiresLocalGateway: cached.requiresLocalGateway,
          readOnlyAllowed: cached.readOnlyAllowed,
          maxPayload: cached.maxPayload,
          maxRows: cached.maxRows,
          reason: cached.reason ?? CapabilityReason.methodNotFound,
          checkedAt: _now(),
          connectionEpoch: epoch,
        );
      }
    }
    _revision++;
  }

  void invalidate(String key) {
    final normalized = _normalizeKey(key);
    final changed = _descriptors.remove(normalized) != null;
    _backendUnsupported.remove(normalized);
    if (changed) _revision++;
  }

  void clear() {
    if (_descriptors.isEmpty && _backendUnsupported.isEmpty) return;
    _descriptors.clear();
    _backendUnsupported.clear();
    _revision++;
  }

  bool _shouldReplace(
    CapabilityDescriptor existing,
    CapabilityDescriptor incoming,
  ) {
    if (incoming.checkedAt.isBefore(existing.checkedAt)) return false;

    // Cache y versión nunca rebajan evidencia autenticada y fresca.
    if ({
          CapabilitySource.cache,
          CapabilitySource.version,
        }.contains(incoming.source) &&
        !{
          CapabilitySource.cache,
          CapabilitySource.version,
        }.contains(existing.source)) {
      return false;
    }

    // Un probe observa el método real y puede corregir un catálogo optimista.
    if (incoming.source == CapabilitySource.probe) return true;
    if (existing.source == CapabilitySource.probe &&
        incoming.source != CapabilitySource.probe) {
      return false;
    }
    return true;
  }
}

String _normalizeKey(String raw) {
  final value = raw.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_.-]{0,127}$').hasMatch(value)) {
    throw const FormatException('invalid capability key');
  }
  return value;
}
