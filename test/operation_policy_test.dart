import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/operation_policy.dart';

void main() {
  test('unknown nunca habilita una mutación', () {
    final policy = OperationPolicy.evaluate(
      scope: OperationScope.session,
      risk: OperationRisk.medium,
      capabilityKey: 'slash.exec',
      capabilityState: CapabilityState.unknown,
      instanceReadOnly: false,
      capabilityReadOnlyAllowed: false,
      targetLabel: 'Current chat',
    );

    expect(policy.canExecute, isFalse);
    expect(policy.blockReason, OperationBlockReason.unknownMutation);
  });

  test('compress available usa inline y noRetry explícitos', () {
    final policy = OperationPolicy.evaluate(
      scope: OperationScope.session,
      risk: OperationRisk.medium,
      capabilityKey: 'slash.exec',
      capabilityState: CapabilityState.available,
      instanceReadOnly: false,
      capabilityReadOnlyAllowed: false,
      targetLabel: 'Current chat',
      requestedConfirmation: OperationConfirmation.inline,
      requestedIdempotency: OperationIdempotency.noRetry,
    );

    expect(policy.canExecute, isTrue);
    expect(policy.confirmation, OperationConfirmation.inline);
    expect(policy.idempotency, OperationIdempotency.noRetry);
  });

  test('modo read-only permite lectura declarada y bloquea escritura', () {
    final read = OperationPolicy.evaluate(
      scope: OperationScope.session,
      risk: OperationRisk.read,
      capabilityKey: 'session.context_breakdown',
      capabilityState: CapabilityState.available,
      instanceReadOnly: true,
      capabilityReadOnlyAllowed: true,
    );
    final write = OperationPolicy.evaluate(
      scope: OperationScope.session,
      risk: OperationRisk.low,
      capabilityKey: 'session.title',
      capabilityState: CapabilityState.available,
      instanceReadOnly: true,
      capabilityReadOnlyAllowed: false,
      targetLabel: 'Current chat',
    );

    expect(read.canExecute, isTrue);
    expect(write.canExecute, isFalse);
    expect(write.blockReason, OperationBlockReason.readOnly);
  });

  test('destructive siempre exige app lock', () {
    final policy = OperationPolicy.evaluate(
      scope: OperationScope.session,
      risk: OperationRisk.destructive,
      capabilityKey: 'session.delete',
      capabilityState: CapabilityState.available,
      instanceReadOnly: false,
      capabilityReadOnlyAllowed: false,
      targetLabel: 'Chat 42',
      requestedConfirmation: OperationConfirmation.none,
    );

    expect(policy.confirmation, OperationConfirmation.appLock);
  });
}
