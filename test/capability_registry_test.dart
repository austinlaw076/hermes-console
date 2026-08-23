import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/capability_descriptor.dart';
import 'package:hermes_android/core/services/capability_registry.dart';

void main() {
  test('versión sola jamás concede available', () {
    final descriptor = CapabilityDescriptor(
      key: 'slash.exec',
      state: CapabilityState.available,
      source: CapabilitySource.version,
      scope: OperationScope.session,
      risk: OperationRisk.medium,
      checkedAt: DateTime.utc(2026, 7, 22),
      connectionEpoch: 1,
    );

    expect(descriptor.state, CapabilityState.unknown);
    expect(descriptor.reason?.code, 'version_hint_only');
  });

  test('probe autenticado corrige catálogo optimista', () {
    var now = DateTime.utc(2026, 7, 22, 10);
    final registry = CapabilityRegistry(
      connectionId: 'conn-1',
      backendIdentity: BackendIdentity(
        family: 'hermes',
        version: '0.19.0',
        contractRevision: '4',
      ),
      connectionEpoch: 3,
      now: () => now,
    );
    registry.recordEvidence(
      key: 'commands.catalog',
      state: CapabilityState.available,
      source: CapabilitySource.catalog,
      scope: OperationScope.instance,
      risk: OperationRisk.read,
      readOnlyAllowed: true,
    );
    now = now.add(const Duration(seconds: 1));
    registry.recordEvidence(
      key: 'commands.catalog',
      state: CapabilityState.unsupported,
      source: CapabilitySource.probe,
      scope: OperationScope.instance,
      risk: OperationRisk.read,
      reason: CapabilityReason.methodNotFound,
    );

    expect(
      registry.lookup('commands.catalog')?.state,
      CapabilityState.unsupported,
    );
  });

  test(
    'epoch descarta resultados tardíos y conserva unsupported por backend',
    () {
      final identity = BackendIdentity(family: 'hermes', version: '0.19.0');
      final registry = CapabilityRegistry(
        connectionId: 'conn-1',
        backendIdentity: identity,
        connectionEpoch: 1,
      );
      registry.recordEvidence(
        key: 'complete.slash',
        state: CapabilityState.unsupported,
        source: CapabilitySource.probe,
        scope: OperationScope.instance,
        risk: OperationRisk.read,
      );
      registry.beginConnectionEpoch(2, backendIdentity: identity);

      expect(
        registry.lookup('complete.slash')?.state,
        CapabilityState.unsupported,
      );
      expect(
        registry.record(
          CapabilityDescriptor(
            key: 'complete.slash',
            state: CapabilityState.available,
            source: CapabilitySource.probe,
            scope: OperationScope.instance,
            risk: OperationRisk.read,
            checkedAt: DateTime.now(),
            connectionEpoch: 1,
          ),
        ),
        isFalse,
      );
    },
  );

  test('cambio de backend invalida incluso unsupported cacheado', () {
    final registry = CapabilityRegistry(
      connectionId: 'conn-1',
      backendIdentity: BackendIdentity(family: 'hermes', version: 'old'),
      connectionEpoch: 1,
    );
    registry.recordEvidence(
      key: 'slash.exec',
      state: CapabilityState.unsupported,
      source: CapabilitySource.probe,
      scope: OperationScope.session,
      risk: OperationRisk.medium,
    );

    registry.beginConnectionEpoch(
      2,
      backendIdentity: BackendIdentity(family: 'hermes', version: 'new'),
    );

    expect(registry.lookup('slash.exec'), isNull);
  });
}
