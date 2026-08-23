import '../models/capability_descriptor.dart';

export '../models/capability_descriptor.dart'
    show CapabilityState, OperationRisk, OperationScope;

enum OperationConfirmation { none, inline, dialog, appLock }

enum OperationReadOnly { allowed, blocked }

enum OperationIdempotency { safe, retryWithKey, noRetry }

enum OperationBlockReason {
  none,
  readOnly,
  unsupported,
  unavailable,
  forbidden,
  unknownMutation,
  invalidTarget,
}

/// Decisión única de política antes de ejecutar una operación.
///
/// No sustituye a ApprovalPolicy: describe la operación y decide si puede
/// llegar a su superficie de confirmación. Las aprobaciones de herramientas
/// siguen usando el flujo existente del Gateway.
final class OperationPolicy {
  final OperationScope scope;
  final OperationRisk risk;
  final OperationConfirmation confirmation;
  final OperationReadOnly readOnly;
  final OperationIdempotency idempotency;
  final String? targetLabel;
  final String capabilityKey;
  final CapabilityState capabilityState;
  final bool canExecute;
  final OperationBlockReason blockReason;

  const OperationPolicy._({
    required this.scope,
    required this.risk,
    required this.confirmation,
    required this.readOnly,
    required this.idempotency,
    required this.targetLabel,
    required this.capabilityKey,
    required this.capabilityState,
    required this.canExecute,
    required this.blockReason,
  });

  factory OperationPolicy.evaluate({
    required OperationScope scope,
    required OperationRisk risk,
    required String capabilityKey,
    required CapabilityState capabilityState,
    required bool instanceReadOnly,
    required bool capabilityReadOnlyAllowed,
    String? targetLabel,
    OperationConfirmation? requestedConfirmation,
    OperationIdempotency? requestedIdempotency,
  }) {
    final key = _capabilityKey(capabilityKey);
    final target = _target(targetLabel);
    final isMutation = risk != OperationRisk.read;

    var blockReason = OperationBlockReason.none;
    if (capabilityState == CapabilityState.unsupported) {
      blockReason = OperationBlockReason.unsupported;
    } else if (capabilityState == CapabilityState.unavailable) {
      blockReason = OperationBlockReason.unavailable;
    } else if (capabilityState == CapabilityState.forbidden) {
      blockReason = OperationBlockReason.forbidden;
    } else if (capabilityState == CapabilityState.unknown && isMutation) {
      blockReason = OperationBlockReason.unknownMutation;
    } else if (isMutation && target == null) {
      blockReason = OperationBlockReason.invalidTarget;
    } else if (instanceReadOnly && (isMutation || !capabilityReadOnlyAllowed)) {
      blockReason = OperationBlockReason.readOnly;
    }

    final confirmation = _confirmationFor(risk, requestedConfirmation);
    final idempotency = requestedIdempotency ?? _idempotencyFor(risk);
    final readOnly =
        instanceReadOnly && blockReason == OperationBlockReason.readOnly
        ? OperationReadOnly.blocked
        : OperationReadOnly.allowed;

    return OperationPolicy._(
      scope: scope,
      risk: risk,
      confirmation: confirmation,
      readOnly: readOnly,
      idempotency: idempotency,
      targetLabel: target,
      capabilityKey: key,
      capabilityState: capabilityState,
      canExecute: blockReason == OperationBlockReason.none,
      blockReason: blockReason,
    );
  }
}

OperationConfirmation _confirmationFor(
  OperationRisk risk,
  OperationConfirmation? requested,
) => switch (risk) {
  OperationRisk.read => OperationConfirmation.none,
  OperationRisk.low => requested ?? OperationConfirmation.inline,
  OperationRisk.medium => requested ?? OperationConfirmation.dialog,
  OperationRisk.high =>
    requested == OperationConfirmation.appLock
        ? OperationConfirmation.appLock
        : OperationConfirmation.dialog,
  OperationRisk.destructive => OperationConfirmation.appLock,
};

OperationIdempotency _idempotencyFor(OperationRisk risk) => switch (risk) {
  OperationRisk.read => OperationIdempotency.safe,
  OperationRisk.low => OperationIdempotency.retryWithKey,
  OperationRisk.medium ||
  OperationRisk.high ||
  OperationRisk.destructive => OperationIdempotency.noRetry,
};

String _capabilityKey(String raw) {
  final value = raw.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_.-]{0,127}$').hasMatch(value)) {
    throw const FormatException('invalid capability key');
  }
  return value;
}

String? _target(Object? value) {
  if (value is! String) return null;
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length <= 256 ? cleaned : cleaned.substring(0, 256);
}
