import '../models/interactive_prompt.dart';

/// One parked request or terminal tombstone.
///
/// A tombstone has no [request] when a lifecycle event arrived before the
/// request payload. Keeping it prevents a delayed request from reopening an
/// already completed/cancelled/expired prompt.
final class InteractivePromptEntry {
  final InteractivePromptKey key;
  final InteractivePromptRequest? request;
  final InteractivePromptStatus status;

  const InteractivePromptEntry({
    required this.key,
    required this.request,
    required this.status,
  });

  bool get isTerminal => status.isTerminal;
  bool get needsInput => !isTerminal;

  InteractivePromptEntry withRequest(InteractivePromptRequest value) =>
      InteractivePromptEntry(key: key, request: value, status: status);

  InteractivePromptEntry withStatus(InteractivePromptStatus value) =>
      InteractivePromptEntry(key: key, request: request, status: value);

  @override
  String toString() =>
      'InteractivePromptEntry(key: $key, kind: ${request?.kind.name}, '
      'status: ${status.name})';
}

/// Immutable in-memory state for all live runtime prompts.
final class InteractivePromptState {
  final Map<InteractivePromptKey, InteractivePromptEntry> _entries;
  final bool isDisposed;

  const InteractivePromptState.empty()
    : _entries = const {},
      isDisposed = false;

  const InteractivePromptState.disposed()
    : _entries = const {},
      isDisposed = true;

  InteractivePromptState._(
    Map<InteractivePromptKey, InteractivePromptEntry> entries,
  ) : _entries = Map.unmodifiable(entries),
      isDisposed = false;

  Map<InteractivePromptKey, InteractivePromptEntry> get entries => _entries;

  InteractivePromptEntry? operator [](InteractivePromptKey key) =>
      _entries[key];

  Iterable<InteractivePromptEntry> forRuntime(String runtimeSessionId) =>
      _entries.values.where(
        (entry) => entry.key.runtimeSessionId == runtimeSessionId,
      );

  Iterable<InteractivePromptEntry> get blocking =>
      _entries.values.where((entry) => entry.needsInput);

  @override
  String toString() =>
      'InteractivePromptState(entries: ${_entries.length}, '
      'disposed: $isDisposed)';
}

sealed class InteractivePromptEvent {
  const InteractivePromptEvent();
}

final class InteractivePromptReceived extends InteractivePromptEvent {
  final InteractivePromptRequest request;

  const InteractivePromptReceived(this.request);
}

final class InteractivePromptResponseStarted extends InteractivePromptEvent {
  final InteractivePromptKey key;

  const InteractivePromptResponseStarted(this.key);
}

final class InteractivePromptResponded extends InteractivePromptEvent {
  final InteractivePromptKey key;

  const InteractivePromptResponded(this.key);
}

/// A response failed before an authoritative terminal outcome was known.
///
/// No value is retained here. Returning to pending only permits a fresh,
/// explicit user entry; callers must never retry a sensitive value.
final class InteractivePromptResponseFailed extends InteractivePromptEvent {
  final InteractivePromptKey key;

  const InteractivePromptResponseFailed(this.key);
}

final class InteractivePromptCancelled extends InteractivePromptEvent {
  final InteractivePromptKey key;

  const InteractivePromptCancelled(this.key);
}

final class InteractivePromptExpired extends InteractivePromptEvent {
  final InteractivePromptKey key;

  const InteractivePromptExpired(this.key);
}

/// Expires every non-terminal prompt owned by a disconnected runtime.
final class InteractivePromptRuntimeExpired extends InteractivePromptEvent {
  final String runtimeSessionId;

  const InteractivePromptRuntimeExpired(this.runtimeSessionId);
}

/// Permanently closes the reducer. Later socket events are ignored.
final class InteractivePromptDisposed extends InteractivePromptEvent {
  const InteractivePromptDisposed();
}

/// Pure state machine for Hermes Desktop blocking requests.
///
/// Terminal states are absorbing. All transitions are keyed by both runtime
/// and request ID, and duplicate events return the original state instance.
abstract final class InteractivePromptReducer {
  static InteractivePromptState reduce(
    InteractivePromptState state,
    InteractivePromptEvent event,
  ) {
    if (state.isDisposed) return state;

    return switch (event) {
      InteractivePromptReceived(:final request) => _receive(state, request),
      InteractivePromptResponseStarted(:final key) => _transition(
        state,
        key,
        InteractivePromptStatus.responding,
      ),
      InteractivePromptResponded(:final key) => _transition(
        state,
        key,
        InteractivePromptStatus.responded,
      ),
      InteractivePromptResponseFailed(:final key) => _responseFailed(
        state,
        key,
      ),
      InteractivePromptCancelled(:final key) => _transition(
        state,
        key,
        InteractivePromptStatus.cancelled,
      ),
      InteractivePromptExpired(:final key) => _transition(
        state,
        key,
        InteractivePromptStatus.expired,
      ),
      InteractivePromptRuntimeExpired(:final runtimeSessionId) =>
        _expireRuntime(state, runtimeSessionId),
      InteractivePromptDisposed() => const InteractivePromptState.disposed(),
    };
  }

  static InteractivePromptState _receive(
    InteractivePromptState state,
    InteractivePromptRequest request,
  ) {
    final current = state[request.key];
    if (current == null) {
      return _replace(
        state,
        InteractivePromptEntry(
          key: request.key,
          request: request,
          status: InteractivePromptStatus.pending,
        ),
      );
    }
    if (current.isTerminal || current.request != null) return state;

    // A non-terminal lifecycle event beat its request over the wire. Attach
    // the typed payload without rolling the lifecycle backwards to pending.
    return _replace(state, current.withRequest(request));
  }

  static InteractivePromptState _transition(
    InteractivePromptState state,
    InteractivePromptKey key,
    InteractivePromptStatus next,
  ) {
    final current = state[key];
    if (current?.isTerminal == true) return state;
    if (current?.status == next) return state;

    return _replace(
      state,
      current?.withStatus(next) ??
          InteractivePromptEntry(key: key, request: null, status: next),
    );
  }

  static InteractivePromptState _expireRuntime(
    InteractivePromptState state,
    String runtimeSessionId,
  ) {
    Map<InteractivePromptKey, InteractivePromptEntry>? changed;
    for (final entry in state.entries.values) {
      if (entry.key.runtimeSessionId != runtimeSessionId || entry.isTerminal) {
        continue;
      }
      changed ??= Map.of(state.entries);
      changed[entry.key] = entry.withStatus(InteractivePromptStatus.expired);
    }
    return changed == null ? state : InteractivePromptState._(changed);
  }

  static InteractivePromptState _responseFailed(
    InteractivePromptState state,
    InteractivePromptKey key,
  ) {
    final current = state[key];
    if (current == null || current.isTerminal) return state;
    if (current.status != InteractivePromptStatus.responding) return state;
    return _replace(state, current.withStatus(InteractivePromptStatus.pending));
  }

  static InteractivePromptState _replace(
    InteractivePromptState state,
    InteractivePromptEntry entry,
  ) {
    final changed = Map<InteractivePromptKey, InteractivePromptEntry>.of(
      state.entries,
    );
    changed[entry.key] = entry;
    return InteractivePromptState._(changed);
  }
}
