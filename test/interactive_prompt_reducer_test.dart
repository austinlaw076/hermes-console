import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/interactive_prompt.dart';
import 'package:hermes_android/core/services/interactive_prompt_reducer.dart';

InteractivePromptKey _key(String runtime, [String request = 'request-1']) =>
    InteractivePromptKey(runtimeSessionId: runtime, requestId: request);

ClarifyPromptRequest _clarify(String runtime, [String request = 'request-1']) =>
    ClarifyPromptRequest(
      key: _key(runtime, request),
      question: '¿Qué entorno?',
      choices: const ['Pruebas', 'Producción'],
    );

void main() {
  group('typed gateway requests', () {
    test('parses all four Hermes 0.19 blocking event shapes', () {
      final clarify = InteractivePromptRequest.fromGatewayEvent(
        type: 'clarify.request',
        runtimeSessionId: 'runtime-a',
        payload: const {
          'request_id': 'clarify-1',
          'question': '¿Cuál?',
          'choices': ['A', 'B'],
        },
      );
      final sudo = InteractivePromptRequest.fromGatewayEvent(
        type: 'sudo.request',
        runtimeSessionId: 'runtime-a',
        payload: const {'request_id': 'sudo-1'},
      );
      final secret = InteractivePromptRequest.fromGatewayEvent(
        type: 'secret.request',
        runtimeSessionId: 'runtime-a',
        payload: const {
          'request_id': 'secret-1',
          'env_var': 'DEPLOY_TOKEN',
          'prompt': 'Token de despliegue',
          'metadata': {'provider': 'example'},
        },
      );
      final terminal = InteractivePromptRequest.fromGatewayEvent(
        type: 'terminal.read.request',
        runtimeSessionId: 'runtime-a',
        payload: const {'request_id': 'terminal-1', 'start': 4, 'count': 12},
      );

      expect(clarify, isA<ClarifyPromptRequest>());
      expect((clarify as ClarifyPromptRequest).choices, ['A', 'B']);
      expect(sudo, isA<SudoPromptRequest>());
      expect(secret, isA<SecretPromptRequest>());
      expect((secret as SecretPromptRequest).envVar, 'DEPLOY_TOKEN');
      expect(terminal, isA<TerminalReadPromptRequest>());
      expect((terminal as TerminalReadPromptRequest).start, 4);
      expect(terminal.count, 12);
    });

    test('rejects malformed opaque identities instead of coercing them', () {
      expect(
        () => InteractivePromptRequest.fromGatewayEvent(
          type: 'sudo.request',
          runtimeSessionId: 'runtime-a',
          payload: const {'request_id': 42},
        ),
        throwsFormatException,
      );
      expect(
        () =>
            InteractivePromptKey(runtimeSessionId: ' ', requestId: 'request-1'),
        throwsFormatException,
      );
    });
  });

  group('InteractivePromptReducer', () {
    test('duplicate request is idempotent', () {
      const initial = InteractivePromptState.empty();
      final event = InteractivePromptReceived(_clarify('runtime-a'));
      final once = InteractivePromptReducer.reduce(initial, event);
      final twice = InteractivePromptReducer.reduce(once, event);

      expect(once.entries, hasLength(1));
      expect(identical(once, twice), isTrue);
      expect(once[_key('runtime-a')]?.status, InteractivePromptStatus.pending);
    });

    test('terminal out-of-order event creates an absorbing tombstone', () {
      const initial = InteractivePromptState.empty();
      final key = _key('runtime-a');
      final expired = InteractivePromptReducer.reduce(
        initial,
        InteractivePromptExpired(key),
      );
      final delayedRequest = InteractivePromptReducer.reduce(
        expired,
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      final delayedResponse = InteractivePromptReducer.reduce(
        delayedRequest,
        InteractivePromptResponded(key),
      );

      expect(expired[key]?.request, isNull);
      expect(expired[key]?.status, InteractivePromptStatus.expired);
      expect(identical(expired, delayedRequest), isTrue);
      expect(identical(delayedRequest, delayedResponse), isTrue);
    });

    test(
      'non-terminal out-of-order event attaches request without rollback',
      () {
        const initial = InteractivePromptState.empty();
        final key = _key('runtime-a');
        final responding = InteractivePromptReducer.reduce(
          initial,
          InteractivePromptResponseStarted(key),
        );
        final received = InteractivePromptReducer.reduce(
          responding,
          InteractivePromptReceived(_clarify('runtime-a')),
        );

        expect(received[key]?.request, isA<ClarifyPromptRequest>());
        expect(received[key]?.status, InteractivePromptStatus.responding);
      },
    );

    test('failed response requires a fresh explicit input', () {
      var state = InteractivePromptReducer.reduce(
        const InteractivePromptState.empty(),
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      final key = _key('runtime-a');
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptResponseStarted(key),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptResponseFailed(key),
      );

      expect(state[key]?.status, InteractivePromptStatus.pending);
      expect(state[key]?.needsInput, isTrue);
    });

    test('same request id in two runtimes remains independent', () {
      var state = const InteractivePromptState.empty();
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-b')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptResponded(_key('runtime-a')),
      );

      expect(state.entries, hasLength(2));
      expect(
        state[_key('runtime-a')]?.status,
        InteractivePromptStatus.responded,
      );
      expect(state[_key('runtime-b')]?.status, InteractivePromptStatus.pending);
    });

    test('cancelled is terminal and cannot be reopened or overwritten', () {
      var state = const InteractivePromptState.empty();
      final key = _key('runtime-a');
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptCancelled(key),
      );
      final cancelled = state;
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptResponded(key),
      );

      expect(identical(cancelled, state), isTrue);
      expect(state[key]?.status, InteractivePromptStatus.cancelled);
      expect(state.blocking, isEmpty);
    });

    test('runtime expiry affects only its live requests', () {
      var state = const InteractivePromptState.empty();
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-a', 'one')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-a', 'two')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptResponded(_key('runtime-a', 'two')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        InteractivePromptReceived(_clarify('runtime-b', 'one')),
      );
      state = InteractivePromptReducer.reduce(
        state,
        const InteractivePromptRuntimeExpired('runtime-a'),
      );

      expect(
        state[_key('runtime-a', 'one')]?.status,
        InteractivePromptStatus.expired,
      );
      expect(
        state[_key('runtime-a', 'two')]?.status,
        InteractivePromptStatus.responded,
      );
      expect(
        state[_key('runtime-b', 'one')]?.status,
        InteractivePromptStatus.pending,
      );
    });

    test('dispose clears all entries and absorbs later socket events', () {
      final populated = InteractivePromptReducer.reduce(
        const InteractivePromptState.empty(),
        InteractivePromptReceived(_clarify('runtime-a')),
      );
      final disposed = InteractivePromptReducer.reduce(
        populated,
        const InteractivePromptDisposed(),
      );
      final late = InteractivePromptReducer.reduce(
        disposed,
        InteractivePromptReceived(_clarify('runtime-a')),
      );

      expect(disposed.isDisposed, isTrue);
      expect(disposed.entries, isEmpty);
      expect(identical(disposed, late), isTrue);
    });
  });

  group('sensitive response handling', () {
    test(
      'secret and sudo parsers never retain raw maps or accidental values',
      () {
        const secretValue = 'actual-secret-value-DO-NOT-LOG';
        const password = 'actual-sudo-password-DO-NOT-LOG';
        final secret = InteractivePromptRequest.fromGatewayEvent(
          type: 'secret.request',
          runtimeSessionId: 'runtime-a',
          payload: const {
            'request_id': 'secret-1',
            'env_var': 'DEPLOY_TOKEN',
            'prompt': 'Token',
            'metadata': {'accidental_value': secretValue},
            'value': secretValue,
          },
        );
        final sudo = InteractivePromptRequest.fromGatewayEvent(
          type: 'sudo.request',
          runtimeSessionId: 'runtime-a',
          payload: const {'request_id': 'sudo-1', 'password': password},
        );

        final diagnostics =
            '${jsonEncode(secret)} $secret ${jsonEncode(sudo)} '
            '$sudo';
        expect(diagnostics, isNot(contains(secretValue)));
        expect(diagnostics, isNot(contains(password)));
        expect(diagnostics, isNot(contains('metadata')));
      },
    );

    test('one-use value redacts on take and never serializes its contents', () {
      const raw = 'one-use-sensitive-value';
      final value = EphemeralSensitiveValue(raw);

      expect(value.hasValue, isTrue);
      expect(value.toString(), isNot(contains(raw)));
      expect(jsonEncode(value), isNot(contains(raw)));
      expect(value.take(), raw);
      expect(value.hasValue, isFalse);
      expect(() => value.take(), throwsStateError);
      expect(value.toString(), isNot(contains(raw)));
      expect(jsonEncode(value), isNot(contains(raw)));
    });

    test('redact and dispose remove the holder reference idempotently', () {
      final redacted = EphemeralSensitiveValue('redact-me');
      redacted.redact();
      expect(redacted.hasValue, isFalse);
      expect(() => redacted.take(), throwsStateError);

      final disposed = EphemeralSensitiveValue('dispose-me');
      disposed.dispose();
      disposed.dispose();
      expect(disposed.hasValue, isFalse);
      expect(disposed.isDisposed, isTrue);
      expect(() => disposed.take(), throwsStateError);
    });
  });

  test('terminal read without an owned terminal is exactly empty text', () {
    expect(TerminalReadResponsePolicy.noOwnedTerminalText, isEmpty);
    expect(TerminalReadResponsePolicy.noOwnedTerminalText, '');
  });
}
