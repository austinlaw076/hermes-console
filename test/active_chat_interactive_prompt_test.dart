import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/interactive_prompt.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InteractiveGateway
    implements HermesDesktopGateway, HermesDesktopInteractivePromptGateway {
  final StreamController<TuiGatewayEvent> _events =
      StreamController<TuiGatewayEvent>.broadcast();

  bool _connected = false;
  int terminalResponses = 0;
  int sensitiveResponses = 0;
  String? clarifyRequestId;
  String? clarifyAnswer;
  DesktopPromptResponseStatus nextSensitiveStatus =
      DesktopPromptResponseStatus.ok;
  Object? nextSensitiveError;

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async => _connected = true;

  @override
  Future<DesktopSessionBinding> resumeSession(
    String storedSessionId, {
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => DesktopSessionBinding(
    runtimeSessionId: 'runtime-interactive',
    storedSessionId: storedSessionId,
    created: false,
  );

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {}

  void emit(
    String type,
    Map<String, dynamic> payload, {
    String sessionId = 'runtime-interactive',
  }) {
    _events.add(
      TuiGatewayEvent(type: type, sessionId: sessionId, payload: payload),
    );
  }

  void disconnect() {
    _connected = false;
    _events.addError(StateError('test disconnect'));
  }

  @override
  Future<DesktopPromptResponse> respondToClarify(
    String requestId,
    String answer,
  ) async {
    clarifyRequestId = requestId;
    clarifyAnswer = answer;
    return DesktopPromptResponse.fromJson(const {
      'status': 'ok',
    }, method: 'clarify.respond');
  }

  @override
  Future<DesktopPromptResponse> respondToSudo(
    String requestId,
    EphemeralSensitiveValue password,
  ) => _sensitive('sudo.respond', password);

  @override
  Future<DesktopPromptResponse> respondToSecret(
    String requestId,
    EphemeralSensitiveValue value,
  ) => _sensitive('secret.respond', value);

  Future<DesktopPromptResponse> _sensitive(
    String method,
    EphemeralSensitiveValue value,
  ) async {
    sensitiveResponses++;
    value.take();
    value.dispose();
    if (nextSensitiveError case final error?) throw error;
    return DesktopPromptResponse.fromJson(
      {'status': nextSensitiveStatus.name},
      method: method,
      allowExpired: true,
    );
  }

  @override
  Future<DesktopPromptResponse> respondToTerminalRead(String requestId) async {
    terminalResponses++;
    return DesktopPromptResponse.fromJson(const {
      'status': 'ok',
    }, method: 'terminal.read.respond');
  }

  @override
  Future<void> steer(String runtimeSessionId, String text) async {}

  @override
  Future<void> interrupt(String runtimeSessionId) async {}

  @override
  Future<void> resolveApproval(
    String runtimeSessionId,
    String choice, {
    bool resolveAll = false,
  }) async {}

  @override
  Future<void> close() async {
    _connected = false;
    if (!_events.isClosed) await _events.close();
  }
}

ActiveChat _chat(_InteractiveGateway gateway) => ActiveChat(
  connection: SavedConnection(
    id: 'conn-interactive',
    label: 'Interactive',
    host: 'example.invalid',
    port: 443,
    apiKey: 'test-only',
    useHttps: true,
    kind: InstanceKind.vps,
  ),
  sessionId: 'stored-interactive',
  sessionTitle: 'Interactive',
  notifications: null,
  onTerminal: () {},
  api: ApiClient(
    baseUrl: 'https://example.invalid',
    apiKey: 'test-only',
    httpClient: MockClient((_) async => http.Response('unused', 500)),
  ),
  desktopGateway: gateway,
);

Future<ActiveChat> _start(_InteractiveGateway gateway) async {
  final chat = _chat(gateway);
  expect(
    await chat.send(
      fullText: 'turno de prueba',
      model: 'hermes-agent',
      history: const [],
    ),
    isTrue,
  );
  return chat;
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clarify se aparca por runtime y responde una sola vez', () async {
    final gateway = _InteractiveGateway();
    final chat = await _start(gateway);
    addTearDown(chat.dispose);

    gateway.emit('clarify.request', const {
      'request_id': 'foreign',
      'question': 'Foreign',
    }, sessionId: 'runtime-other');
    gateway.emit('clarify.request', const {
      'request_id': 'clarify-1',
      'question': '¿Qué opción?',
      'choices': ['A', 'B'],
    });
    await _waitUntil(() => chat.pendingInteractivePrompt != null);

    final entry = chat.pendingInteractivePrompt!;
    expect(entry.request, isA<ClarifyPromptRequest>());
    expect(chat.needsInput, isTrue);
    await chat.respondToClarify(entry.key, 'B');

    expect(gateway.clarifyRequestId, 'clarify-1');
    expect(gateway.clarifyAnswer, 'B');
    expect(chat.pendingInteractivePrompt, isNull);
    expect(chat.needsInput, isFalse);
  });

  test(
    'terminal.read se responde vacío por política y deduplica replay',
    () async {
      final gateway = _InteractiveGateway();
      final chat = await _start(gateway);
      addTearDown(chat.dispose);
      const payload = {'request_id': 'terminal-1', 'start': 0, 'count': 40};

      gateway.emit('terminal.read.request', payload);
      gateway.emit('terminal.read.request', payload);
      await _waitUntil(() => gateway.terminalResponses == 1);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.terminalResponses, 1);
      expect(chat.pendingInteractivePrompt, isNull);
    },
  );

  test('secret expired se borra y un replay tardío no lo reabre', () async {
    final gateway = _InteractiveGateway()
      ..nextSensitiveStatus = DesktopPromptResponseStatus.expired;
    final chat = await _start(gateway);
    addTearDown(chat.dispose);
    const payload = {
      'request_id': 'secret-1',
      'env_var': 'DEPLOY_TOKEN',
      'prompt': 'Token',
    };
    gateway.emit('secret.request', payload);
    await _waitUntil(() => chat.pendingInteractivePrompt != null);
    final entry = chat.pendingInteractivePrompt!;
    final value = EphemeralSensitiveValue('one-shot-value');

    final result = await chat.respondToSecret(entry.key, value);
    expect(result.isExpired, isTrue);
    expect(value.isDisposed, isTrue);
    expect(value.hasValue, isFalse);
    expect(chat.pendingInteractivePrompt, isNull);

    gateway.emit('secret.request', payload);
    await Future<void>.delayed(Duration.zero);
    expect(chat.pendingInteractivePrompt, isNull);
    expect(gateway.sensitiveResponses, 1);
  });

  test(
    'fallo sensible exige valor nuevo y el holder siempre se dispone',
    () async {
      final gateway = _InteractiveGateway()
        ..nextSensitiveError = StateError('sanitized transport failure');
      final chat = await _start(gateway);
      addTearDown(chat.dispose);
      gateway.emit('sudo.request', const {'request_id': 'sudo-1'});
      await _waitUntil(() => chat.pendingInteractivePrompt != null);
      final entry = chat.pendingInteractivePrompt!;
      final password = EphemeralSensitiveValue('one-shot-password');

      await expectLater(
        chat.respondToSudo(entry.key, password),
        throwsA(isA<StateError>()),
      );
      expect(password.isDisposed, isTrue);
      expect(password.hasValue, isFalse);
      expect(
        chat.pendingInteractivePrompt?.status,
        InteractivePromptStatus.pending,
      );
    },
  );

  test(
    'disconnect expira la petición del runtime sin cruzarla a otro chat',
    () async {
      final gateway = _InteractiveGateway();
      final chat = await _start(gateway);
      addTearDown(chat.dispose);
      gateway.emit('sudo.request', const {'request_id': 'sudo-disconnect'});
      await _waitUntil(() => chat.pendingInteractivePrompt != null);
      final key = chat.pendingInteractivePrompt!.key;

      gateway.disconnect();
      await _waitUntil(
        () =>
            chat.interactivePrompts[key]?.status ==
            InteractivePromptStatus.expired,
      );

      expect(chat.pendingInteractivePrompt, isNull);
    },
  );
}
