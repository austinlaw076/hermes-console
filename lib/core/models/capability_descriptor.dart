/// Estado efectivo de una capacidad para una conexión concreta.
enum CapabilityState {
  available,
  unsupported,
  unavailable,
  forbidden,
  legacy,
  unknown,
}

/// Evidencia usada para resolver una capacidad.
enum CapabilitySource { handshake, probe, catalog, version, cache }

/// Ámbito real de una operación.
enum OperationScope { local, chat, session, instance, host }

/// Riesgo declarado de una operación.
enum OperationRisk { read, low, medium, high, destructive }

OperationScope operationScopeFromWire(
  Object? value, {
  OperationScope fallback = OperationScope.session,
}) {
  final wire = value?.toString().trim().toLowerCase();
  for (final scope in OperationScope.values) {
    if (scope.name == wire) return scope;
  }
  return fallback;
}

OperationRisk operationRiskFromWire(
  Object? value, {
  OperationRisk fallback = OperationRisk.medium,
}) {
  final wire = value?.toString().trim().toLowerCase();
  for (final risk in OperationRisk.values) {
    if (risk.name == wire) return risk;
  }
  return fallback;
}

/// Identidad no secreta del contrato remoto.
///
/// No contiene host, URL ni credenciales. Cambiar cualquiera de sus partes
/// invalida los caches que dependan del contrato del backend.
final class BackendIdentity {
  final String family;
  final String? version;
  final String? contractRevision;

  factory BackendIdentity({
    required String family,
    String? version,
    String? contractRevision,
  }) {
    final safeFamily = _boundedIdentifier(family, 96);
    if (safeFamily == null) {
      throw const FormatException('invalid backend family');
    }
    return BackendIdentity._(
      family: safeFamily,
      version: _boundedIdentifier(version, 64),
      contractRevision: _boundedIdentifier(contractRevision, 64),
    );
  }

  const BackendIdentity._({
    required this.family,
    this.version,
    this.contractRevision,
  });

  String get cacheKey =>
      [family, version ?? '', contractRevision ?? ''].join('|');

  @override
  bool operator ==(Object other) =>
      other is BackendIdentity &&
      other.family == family &&
      other.version == version &&
      other.contractRevision == contractRevision;

  @override
  int get hashCode => Object.hash(family, version, contractRevision);
}

/// Razón segura y estructurada para explicar un estado no disponible.
///
/// [code] es un identificador local, nunca el mensaje remoto crudo.
final class CapabilityReason {
  final String code;

  factory CapabilityReason(String code) {
    final safe = _boundedIdentifier(code, 64);
    if (safe == null) throw const FormatException('invalid capability reason');
    return CapabilityReason._(safe);
  }

  const CapabilityReason._(this.code);

  static final methodNotFound = CapabilityReason('method_not_found');
  static final permissionDenied = CapabilityReason('permission_denied');
  static final serviceUnavailable = CapabilityReason('service_unavailable');
  static final legacyAdapter = CapabilityReason('legacy_adapter');
  static final versionHint = CapabilityReason('version_hint_only');
  static final malformedResponse = CapabilityReason('malformed_response');
  static final stale = CapabilityReason('stale');
}

/// Descriptor inmutable de una capacidad negociada con Hermes.
final class CapabilityDescriptor {
  static final RegExp _keyPattern = RegExp(r'^[a-z][a-z0-9_.-]{0,127}$');

  final String key;
  final CapabilityState state;
  final CapabilitySource source;
  final OperationScope scope;
  final OperationRisk risk;
  final bool requiresRuntime;
  final bool requiresLocalGateway;
  final bool readOnlyAllowed;
  final int? maxPayload;
  final int? maxRows;
  final CapabilityReason? reason;
  final DateTime checkedAt;
  final int connectionEpoch;

  factory CapabilityDescriptor({
    required String key,
    required CapabilityState state,
    required CapabilitySource source,
    required OperationScope scope,
    required OperationRisk risk,
    required DateTime checkedAt,
    required int connectionEpoch,
    bool requiresRuntime = false,
    bool requiresLocalGateway = false,
    bool readOnlyAllowed = false,
    int? maxPayload,
    int? maxRows,
    CapabilityReason? reason,
  }) {
    final normalizedKey = key.trim().toLowerCase();
    if (!_keyPattern.hasMatch(normalizedKey)) {
      throw const FormatException('invalid capability key');
    }
    if (connectionEpoch < 0) {
      throw const FormatException('invalid connection epoch');
    }
    if (maxPayload != null && (maxPayload <= 0 || maxPayload > 16 << 20)) {
      throw const FormatException('invalid capability payload limit');
    }
    if (maxRows != null && (maxRows <= 0 || maxRows > 100000)) {
      throw const FormatException('invalid capability row limit');
    }

    // Una versión solo es una pista. Nunca concede disponibilidad por sí sola.
    final effectiveState =
        source == CapabilitySource.version && state == CapabilityState.available
        ? CapabilityState.unknown
        : state;
    final effectiveReason =
        source == CapabilitySource.version && state == CapabilityState.available
        ? CapabilityReason.versionHint
        : reason;

    return CapabilityDescriptor._(
      key: normalizedKey,
      state: effectiveState,
      source: source,
      scope: scope,
      risk: risk,
      requiresRuntime: requiresRuntime,
      requiresLocalGateway: requiresLocalGateway,
      readOnlyAllowed: readOnlyAllowed,
      maxPayload: maxPayload,
      maxRows: maxRows,
      reason: effectiveReason,
      checkedAt: checkedAt.toUtc(),
      connectionEpoch: connectionEpoch,
    );
  }

  const CapabilityDescriptor._({
    required this.key,
    required this.state,
    required this.source,
    required this.scope,
    required this.risk,
    required this.requiresRuntime,
    required this.requiresLocalGateway,
    required this.readOnlyAllowed,
    required this.checkedAt,
    required this.connectionEpoch,
    this.maxPayload,
    this.maxRows,
    this.reason,
  });

  factory CapabilityDescriptor.unknown({
    required String key,
    required DateTime checkedAt,
    required int connectionEpoch,
    OperationScope scope = OperationScope.instance,
    OperationRisk risk = OperationRisk.medium,
    CapabilitySource source = CapabilitySource.cache,
    CapabilityReason? reason,
  }) => CapabilityDescriptor(
    key: key,
    state: CapabilityState.unknown,
    source: source,
    scope: scope,
    risk: risk,
    checkedAt: checkedAt,
    connectionEpoch: connectionEpoch,
    reason: reason,
  );

  bool isFresh(DateTime now, Duration maxAge) {
    final age = now.toUtc().difference(checkedAt);
    return age <= maxAge && age >= -const Duration(minutes: 1);
  }

  bool get isUsable =>
      state == CapabilityState.available || state == CapabilityState.legacy;

  bool get allowsMutation => isUsable && risk != OperationRisk.read;

  bool get allowsReadOnly =>
      readOnlyAllowed &&
      (state == CapabilityState.available || state == CapabilityState.legacy);
}

String? _boundedIdentifier(Object? value, int maxLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxLength) return null;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}
