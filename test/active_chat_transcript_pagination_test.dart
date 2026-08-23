import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fake del canal Desktop que graba los flags de `session.resume` y permite
/// emitir eventos `session.resume_progress` como haría Hermes Agent 0.20.
class _DeferrableGateway
    implements HermesDesktopGateway, HermesDesktopSessionLifecycleGateway {
  final StreamController<TuiGatewayEvent> _events =
      StreamController<TuiGatewayEvent>.broadcast();
  DesktopSessionSnapshot? snapshot;
  int resumeExistingCalls = 0;
  bool? lastDeferHistory;
  bool? lastOmitMessages;

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<DesktopSessionSnapshot> resumeExisting(
    String storedSessionId, {
    String profile = '',
    bool omitMessages = false,
    bool deferHistory = false,
  }) async {
    resumeExistingCalls++;
    lastDeferHistory = deferHistory;
    lastOmitMessages = omitMessages;
    return snapshot!;
  }

  @override
  Future<DesktopSessionSnapshot> createForFirstSubmit({
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => throw StateError('must not create while loading');

  @override
  Future<DesktopSessionBinding> resumeSession(
    String storedSessionId, {
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => throw StateError('legacy resume must not run while loading');

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {}

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

  void emitResumeProgress(String status, {int? messageCount}) {
    _events.add(
      TuiGatewayEvent(
        type: 'session.resume_progress',
        sessionId: snapshot!.runtimeSessionId,
        payload: {
          'phase': 'history',
          'status': status,
          'message_count': ?messageCount,
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    await _events.close();
  }
}

SavedConnection _connection(String id) => SavedConnection(
  id: id,
  label: id,
  host: '127.0.0.1',
  port: 8642,
  apiKey: 'test-key',
  kind: InstanceKind.vps,
);

/// Servidor mock de `/api/sessions/{id}/messages` con la semántica
/// `order=latest` de Hermes Agent 0.20: `offset` hacia atrás desde el mensaje
/// más reciente y la página devuelta en orden cronológico. [paginate]=false
/// simula un gateway legacy que ignora la query y devuelve todo one-shot.
class _TranscriptServer {
  _TranscriptServer({required this.paginate});

  final bool paginate;
  final List<Map<String, dynamic>> rows = [];
  final List<Uri> requests = [];
  bool healthy = true;

  http.Client client() => MockClient((request) async {
    requests.add(request.url);
    if (!healthy) {
      return http.Response('unavailable', 500);
    }
    if (!paginate) {
      return http.Response(
        jsonEncode({'object': 'list', 'data': rows}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final limit = int.parse(request.url.queryParameters['limit'] ?? '120');
    final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
    final end = math.max(0, rows.length - offset);
    final start = math.max(0, end - limit);
    final page = rows.sublist(start, end);
    return http.Response(
      jsonEncode({
        'object': 'list',
        'session_id': 'stored-chat',
        'data': page,
        'pagination': {
          'limit': limit,
          'offset': offset,
          'order': 'latest',
          'returned': page.length,
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

List<Map<String, dynamic>> _rows(int count, {int from = 1}) => [
  for (var index = from; index < from + count; index++)
    {
      'id': index,
      'role': index.isOdd ? 'user' : 'assistant',
      'content': 'msg $index',
    },
];

ActiveChat _chat(
  String id,
  http.Client client, {
  _DeferrableGateway? gateway,
}) => ActiveChat(
  connection: _connection(id),
  sessionId: 'stored-chat',
  sessionTitle: 'Paginación',
  notifications: null,
  onTerminal: () {},
  api: ApiClient(
    baseUrl: 'http://127.0.0.1:8642',
    apiKey: 'test-key',
    httpClient: client,
  ),
  desktopGateway: gateway,
);

List<Map<String, dynamic>> _generatedImageRefs(Map<String, dynamic> message) {
  final raw = message['_generatedImages'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hidrata solo la cola paginada y antepone páginas anteriores', () async {
    final server = _TranscriptServer(paginate: true)..rows.addAll(_rows(300));
    final chat = _chat('tail', server.client());
    addTearDown(chat.dispose);
    final events = <ActiveChatEvent>[];
    final sub = chat.changes.listen(events.add);
    addTearDown(sub.cancel);

    await chat.loadMessages(expectedMessageCount: 300);

    expect(chat.messagesLoaded, isTrue);
    expect(chat.messages, hasLength(120));
    expect(chat.messages.first['content'], 'msg 300');
    expect(chat.messages.last['content'], 'msg 181');
    expect(chat.hasEarlierMessages, isTrue);
    expect(server.requests, hasLength(1));
    expect(server.requests.single.queryParameters['limit'], '120');
    expect(server.requests.single.queryParameters['order'], 'latest');
    expect(server.requests.single.queryParameters['offset'], '0');

    expect(await chat.loadEarlierMessages(), isTrue);
    expect(chat.messages, hasLength(240));
    expect(chat.messages.last['content'], 'msg 61');
    expect(chat.hasEarlierMessages, isTrue);
    expect(server.requests.last.queryParameters['offset'], '120');

    // Última página parcial: el backfill se retira.
    expect(await chat.loadEarlierMessages(), isTrue);
    expect(chat.messages, hasLength(300));
    expect(chat.messages.last['content'], 'msg 1');
    expect(chat.hasEarlierMessages, isFalse);
    expect(await chat.loadEarlierMessages(), isFalse);
    expect(
      events.where((event) => event == ActiveChatEvent.earlierMessagesLoaded),
      hasLength(2),
    );
  });

  test(
    'backfill asocia tool result con su image_generate al cruzar el corte de página',
    () async {
      final server = _TranscriptServer(paginate: true)
        ..rows.addAll([
          for (var id = 1; id <= 178; id++)
            {'id': id, 'role': 'system', 'content': 'relleno $id'},
          {'id': 179, 'role': 'user', 'content': 'genera una imagen'},
          {
            'id': 180,
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call-page-image',
                'type': 'function',
                'function': {
                  'name': 'image_generate',
                  'arguments': '{"prompt":"page boundary"}',
                },
              },
            ],
          },
          {
            'id': 181,
            'role': 'tool',
            'tool_call_id': 'call-page-image',
            'content':
                '{"success":true,"host_image":"/home/hermes/.hermes/cache/images/page-boundary.png"}',
          },
          {'id': 182, 'role': 'assistant', 'content': 'Imagen terminada.'},
          for (var id = 183; id <= 300; id++)
            {'id': id, 'role': 'system', 'content': 'relleno $id'},
        ]);
      final chat = _chat('image-page-boundary', server.client());
      addTearDown(chat.dispose);

      await chat.loadMessages(expectedMessageCount: 300);

      final finalAssistant = chat.messages.singleWhere(
        (message) => message['id'] == 182,
      );
      expect(_generatedImageRefs(finalAssistant), isEmpty);

      expect(await chat.loadEarlierMessages(), isTrue);

      final hydratedAssistant = chat.messages.singleWhere(
        (message) => message['id'] == 182,
      );
      final refs = _generatedImageRefs(hydratedAssistant);
      expect(refs, hasLength(1));
      expect(refs.single['basename'], 'page-boundary.png');
      expect(refs.single['tool_call_id'], 'call-page-image');
    },
  );

  test('gateway legacy sin metadata pagination: transcript one-shot', () async {
    final server = _TranscriptServer(paginate: false)..rows.addAll(_rows(300));
    final chat = _chat('legacy', server.client());
    addTearDown(chat.dispose);

    await chat.loadMessages(expectedMessageCount: 300);

    expect(chat.messages, hasLength(300));
    expect(chat.messages.first['content'], 'msg 300');
    expect(chat.hasEarlierMessages, isFalse);
    expect(await chat.loadEarlierMessages(), isFalse);
    expect(server.requests, hasLength(1));
  });

  test('backfill deduplica el solape por drift de offsets', () async {
    final server = _TranscriptServer(paginate: true)..rows.addAll(_rows(300));
    final chat = _chat('drift', server.client());
    addTearDown(chat.dispose);

    await chat.loadMessages(expectedMessageCount: 300);
    // El servidor persiste 5 mensajes nuevos tras la hidratación: la página
    // pedida con offset=120 solapa 5 filas ya visibles.
    server.rows.addAll(_rows(5, from: 301));

    expect(await chat.loadEarlierMessages(), isTrue);
    final ids = chat.messages.map((message) => message['id']).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(chat.messages, hasLength(235));
    expect(chat.messages.first['content'], 'msg 300');
    expect(chat.messages.last['content'], 'msg 66');
  });

  test('resume diferido: ack hydrating + resume_progress complete aplica el '
      'historial aunque el primer REST falle', () async {
    final gateway = _DeferrableGateway()
      ..snapshot = DesktopSessionSnapshot.fromJson(
        {
          'session_id': 'runtime-deferred',
          'session_key': 'stored-chat',
          'hydrating': true,
          'message_count': 2,
          'messages': <Object>[],
        },
        requestedStoredSessionId: 'stored-chat',
        created: false,
        method: 'session.resume',
      );
    final server = _TranscriptServer(paginate: true)
      ..rows.addAll([
        {'id': 1, 'role': 'user', 'content': 'pregunta'},
        {'id': 2, 'role': 'assistant', 'content': 'respuesta'},
      ])
      ..healthy = false;
    final chat = _chat('deferred', server.client(), gateway: gateway);
    addTearDown(chat.dispose);

    final load = chat.loadMessages(expectedMessageCount: 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(gateway.lastDeferHistory, isTrue);
    expect(chat.isHydratingDesktopHistory, isTrue);
    expect(chat.messagesLoaded, isFalse);

    server.healthy = true;
    gateway.emitResumeProgress('complete', messageCount: 2);
    await load;

    expect(chat.messagesLoaded, isTrue);
    expect(chat.isHydratingDesktopHistory, isFalse);
    expect(chat.messages, hasLength(2));
    expect(chat.messages.first['content'], 'respuesta');
    // Prefetch fallido + reintento tras el resume_progress.
    expect(server.requests, hasLength(2));
  });

  test(
    'resume diferido: server sin defer_history conserva el path actual',
    () async {
      final gateway = _DeferrableGateway()
        ..snapshot = DesktopSessionSnapshot.fromJson(
          {
            'session_id': 'runtime-legacy',
            'session_key': 'stored-chat',
            'message_count': 2,
            'messages': [
              {'role': 'user', 'content': 'pregunta'},
              {'role': 'assistant', 'content': 'respuesta'},
            ],
          },
          requestedStoredSessionId: 'stored-chat',
          created: false,
          method: 'session.resume',
        );
      final server = _TranscriptServer(paginate: false)..healthy = false;
      final chat = _chat('no-defer', server.client(), gateway: gateway);
      addTearDown(chat.dispose);

      await chat.loadMessages(expectedMessageCount: 2);

      expect(gateway.lastDeferHistory, isTrue);
      expect(chat.messagesLoaded, isTrue);
      expect(chat.isHydratingDesktopHistory, isFalse);
      expect(chat.messages, hasLength(2));
      expect(chat.messages.first['content'], 'respuesta');
      expect(chat.messages.last['content'], 'pregunta');
    },
  );
}
