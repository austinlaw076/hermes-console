/// Typed projection of the Hermes Desktop blocking request events.
///
/// Requests are kept in memory only. In particular, sudo passwords and secret
/// values are response data and never belong in these models.
enum InteractivePromptKind { clarify, sudo, secret, terminalRead }

enum InteractivePromptStatus {
  pending,
  responding,
  responded,
  cancelled,
  expired,
}

extension InteractivePromptStatusLifecycle on InteractivePromptStatus {
  bool get isTerminal =>
      this == InteractivePromptStatus.responded ||
      this == InteractivePromptStatus.cancelled ||
      this == InteractivePromptStatus.expired;
}

/// Opaque identity of one blocking request inside one live Desktop runtime.
///
/// Request IDs are only unique inside their runtime, so neither component may
/// be dropped when parking or resolving a prompt.
final class InteractivePromptKey {
  final String runtimeSessionId;
  final String requestId;

  factory InteractivePromptKey({
    required String runtimeSessionId,
    required String requestId,
  }) {
    if (runtimeSessionId.trim().isEmpty) {
      throw const FormatException('Missing runtime session id');
    }
    if (requestId.trim().isEmpty) {
      throw const FormatException('Missing interactive request id');
    }
    return InteractivePromptKey._(runtimeSessionId, requestId);
  }

  const InteractivePromptKey._(this.runtimeSessionId, this.requestId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractivePromptKey &&
          runtimeSessionId == other.runtimeSessionId &&
          requestId == other.requestId;

  @override
  int get hashCode => Object.hash(runtimeSessionId, requestId);

  @override
  String toString() =>
      'InteractivePromptKey(runtime: $runtimeSessionId, request: $requestId)';
}

sealed class InteractivePromptRequest {
  final InteractivePromptKey key;

  const InteractivePromptRequest({required this.key});

  InteractivePromptKind get kind;

  /// Parses only the documented fields and never retains the source map.
  ///
  /// Unknown event types and malformed identities fail closed. This keeps a
  /// future gateway payload from becoming an accidental secret container.
  static InteractivePromptRequest fromGatewayEvent({
    required String type,
    required String runtimeSessionId,
    required Map<String, dynamic> payload,
  }) => switch (type) {
    'clarify.request' => ClarifyPromptRequest.fromGatewayEvent(
      runtimeSessionId: runtimeSessionId,
      payload: payload,
    ),
    'sudo.request' => SudoPromptRequest.fromGatewayEvent(
      runtimeSessionId: runtimeSessionId,
      payload: payload,
    ),
    'secret.request' => SecretPromptRequest.fromGatewayEvent(
      runtimeSessionId: runtimeSessionId,
      payload: payload,
    ),
    'terminal.read.request' => TerminalReadPromptRequest.fromGatewayEvent(
      runtimeSessionId: runtimeSessionId,
      payload: payload,
    ),
    _ => throw FormatException('Unsupported interactive event type: $type'),
  };

  /// Safe request metadata only. Response passwords/values cannot enter this
  /// representation because no request type has a field for them.
  Map<String, Object?> toJson();

  @override
  String toString() => '$runtimeType(key: $key)';
}

final class ClarifyPromptRequest extends InteractivePromptRequest {
  final String question;
  final List<String> choices;

  ClarifyPromptRequest({
    required super.key,
    required this.question,
    List<String> choices = const [],
  }) : choices = List.unmodifiable(choices);

  factory ClarifyPromptRequest.fromGatewayEvent({
    required String runtimeSessionId,
    required Map<String, dynamic> payload,
  }) => ClarifyPromptRequest(
    key: _requestKey(runtimeSessionId, payload),
    question: _requiredString(payload, 'question'),
    choices: _stringList(payload['choices'], 'choices'),
  );

  @override
  InteractivePromptKind get kind => InteractivePromptKind.clarify;

  @override
  Map<String, Object?> toJson() => {
    'type': 'clarify.request',
    'runtime_session_id': key.runtimeSessionId,
    'request_id': key.requestId,
    'question': question,
    'choices': choices,
  };
}

/// A sudo challenge. The password is deliberately not representable here.
final class SudoPromptRequest extends InteractivePromptRequest {
  const SudoPromptRequest({required super.key});

  factory SudoPromptRequest.fromGatewayEvent({
    required String runtimeSessionId,
    required Map<String, dynamic> payload,
  }) => SudoPromptRequest(key: _requestKey(runtimeSessionId, payload));

  @override
  InteractivePromptKind get kind => InteractivePromptKind.sudo;

  @override
  Map<String, Object?> toJson() => {
    'type': 'sudo.request',
    'runtime_session_id': key.runtimeSessionId,
    'request_id': key.requestId,
  };
}

/// A named secret challenge. The submitted value is deliberately absent.
///
/// Gateway `metadata` is not retained: it is an open-ended map and therefore
/// cannot be proven safe to log, serialize, or keep after disconnect.
final class SecretPromptRequest extends InteractivePromptRequest {
  final String envVar;
  final String prompt;

  const SecretPromptRequest({
    required super.key,
    required this.envVar,
    required this.prompt,
  });

  factory SecretPromptRequest.fromGatewayEvent({
    required String runtimeSessionId,
    required Map<String, dynamic> payload,
  }) => SecretPromptRequest(
    key: _requestKey(runtimeSessionId, payload),
    envVar: _requiredString(payload, 'env_var'),
    prompt: _requiredString(payload, 'prompt'),
  );

  @override
  InteractivePromptKind get kind => InteractivePromptKind.secret;

  @override
  Map<String, Object?> toJson() => {
    'type': 'secret.request',
    'runtime_session_id': key.runtimeSessionId,
    'request_id': key.requestId,
    'env_var': envVar,
    'prompt': prompt,
  };

  @override
  String toString() => 'SecretPromptRequest(key: $key, envVar: $envVar)';
}

final class TerminalReadPromptRequest extends InteractivePromptRequest {
  final int? start;
  final int? count;

  const TerminalReadPromptRequest({required super.key, this.start, this.count});

  factory TerminalReadPromptRequest.fromGatewayEvent({
    required String runtimeSessionId,
    required Map<String, dynamic> payload,
  }) => TerminalReadPromptRequest(
    key: _requestKey(runtimeSessionId, payload),
    start: _optionalInt(payload['start'], 'start'),
    count: _optionalInt(payload['count'], 'count'),
  );

  @override
  InteractivePromptKind get kind => InteractivePromptKind.terminalRead;

  @override
  Map<String, Object?> toJson() => {
    'type': 'terminal.read.request',
    'runtime_session_id': key.runtimeSessionId,
    'request_id': key.requestId,
    if (start != null) 'start': start,
    if (count != null) 'count': count,
  };
}

/// Mobile policy for a gateway terminal read when the app owns no managed
/// terminal pane. This is intentionally a constant empty response: it must not
/// inspect clipboard, files, process output, logs, or any ambient shell state.
abstract final class TerminalReadResponsePolicy {
  static const String noOwnedTerminalText = '';
}

/// One-use holder for a sudo password or secret response value.
///
/// Dart strings cannot be zeroed in place. `redact` and `dispose` therefore
/// clear this holder's reference as soon as possible; callers must likewise
/// avoid retaining the value returned by [take]. The value never appears in
/// serialization or diagnostics.
final class EphemeralSensitiveValue {
  String? _value;
  bool _disposed = false;

  EphemeralSensitiveValue(String value) : _value = value;

  bool get hasValue => !_disposed && _value != null;
  bool get isDisposed => _disposed;

  String take() {
    if (_disposed) {
      throw StateError('Sensitive value holder is disposed');
    }
    final value = _value;
    if (value == null) {
      throw StateError('Sensitive value has already been redacted');
    }
    _value = null;
    return value;
  }

  void redact() {
    _value = null;
  }

  void dispose() {
    if (_disposed) return;
    redact();
    _disposed = true;
  }

  Map<String, Object?> toJson() => const {'value': '<redacted>'};

  @override
  String toString() => 'EphemeralSensitiveValue(<redacted>)';
}

InteractivePromptKey _requestKey(
  String runtimeSessionId,
  Map<String, dynamic> payload,
) => InteractivePromptKey(
  runtimeSessionId: runtimeSessionId,
  requestId: _requiredString(payload, 'request_id'),
);

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid $key');
  }
  return value;
}

List<String> _stringList(Object? value, String key) {
  if (value == null) return const [];
  if (value is! List) throw FormatException('Invalid $key');
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw FormatException('Invalid $key item');
    }
    result.add(item);
  }
  return List.unmodifiable(result);
}

int? _optionalInt(Object? value, String key) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.toInt()) {
    return value.toInt();
  }
  throw FormatException('Invalid $key');
}
