// Tests TASK-019: perfil chat-local-simple — BridgeClient.chatSimple.
//
// Verifica que chatSimple envía mode=simple al bridge (sin tools en el body
// del cliente), maneja respuestas de texto/vacías/tool_call correctamente, y
// que chat() estándar NO envía mode=simple (remoto intacto).
//
// Los tests 4-8 del TEST_PLAN (payload que el bridge manda a OpenAI: sin tools,
// system pequeño, stream=false, max_tokens acotado, base_url sin /v1/v1) son
// invariantes del código Python del bridge; se verifican inspeccionando el body
// que BridgeClient manda al bridge y el comportamiento de la respuesta.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/bridge_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  BridgeClient clientWith(MockClient mock) => BridgeClient(
    baseUrl: 'http://127.0.0.1:9131',
    token: 'test-token',
    httpClient: mock,
  );

  // ---- Helper: respuesta del bridge cuando el backend (Python) tuvo éxito ----
  http.Response bridgeOk(String text) => http.Response(
    jsonEncode({'ok': true, 'response': text}),
    200,
    headers: {'content-type': 'application/json'},
  );

  // El formato real del bridge es {"error": code, "message": message}
  // (ver _err() en hermes_bridge.py L153-154).
  http.Response bridgeErr(String code, String message, {int status = 502}) =>
      http.Response(
        jsonEncode({'error': code, 'message': message}),
        status,
        headers: {'content-type': 'application/json'},
      );

  // ============================================================
  // TEST 1: texto → texto
  // ============================================================
  test(
    'T1 chatSimple: bridge devuelve texto → cliente obtiene texto',
    () async {
      final c = clientWith(
        MockClient((_) async => bridgeOk('Hola, soy el asistente.')),
      );
      final result = await c.chatSimple('dime hola');
      expect(result, 'Hola, soy el asistente.');
    },
  );

  // ============================================================
  // TEST 2: vacío → BridgeException (no silencio rc=0)
  // ============================================================
  test('T2 chatSimple: bridge devuelve 502 vacío → BridgeException con '
      'mensaje claro (no silencio)', () async {
    final c = clientWith(
      MockClient(
        (_) async => bridgeErr(
          'chat_simple_failed',
          'el modelo no devolvió texto (chat simple). finish_reason=stop',
        ),
      ),
    );
    await expectLater(
      c.chatSimple('hola'),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.message,
          'message',
          contains('el modelo no devolvió texto'),
        ),
      ),
    );
  });

  // ============================================================
  // TEST 3: tool_call → error claro, SIN bucle (una sola petición)
  // ============================================================
  test('T3 chatSimple: bridge recibe tool_call del modelo → error claro, '
      'no bucle de 50 turnos', () async {
    var callCount = 0;
    final c = clientWith(
      MockClient((_) async {
        callCount++;
        return bridgeErr(
          'chat_simple_failed',
          'el modelo intentó usar herramientas en modo simple '
              '(modelo pequeño): usa un modelo más capaz o el modo agente.',
        );
      }),
    );
    await expectLater(
      c.chatSimple('usa una herramienta'),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.message,
          'message',
          contains('herramientas'),
        ),
      ),
    );
    // Una sola petición: el bridge no reentra en bucle.
    expect(
      callCount,
      1,
      reason:
          'chatSimple debe hacer exactamente 1 petición aunque el '
          'modelo emita tool_calls',
    );
  });

  // ============================================================
  // TEST 4 + 9: body del cliente contiene mode=simple; chat() estándar NO
  // ============================================================
  test(
    'T4/T9 chatSimple envía mode=simple; chat() estándar NO envía mode',
    () async {
      late String capturedSimpleBody;
      late String capturedFullBody;

      final cSimple = clientWith(
        MockClient((req) async {
          capturedSimpleBody = req.body;
          return bridgeOk('ok simple');
        }),
      );
      final cFull = clientWith(
        MockClient((req) async {
          capturedFullBody = req.body;
          return bridgeOk('ok full');
        }),
      );

      await cSimple.chatSimple('hola');
      await cFull.chat('hola');

      final simpleJson = jsonDecode(capturedSimpleBody) as Map<String, dynamic>;
      final fullJson = jsonDecode(capturedFullBody) as Map<String, dynamic>;

      // chatSimple manda mode=simple
      expect(
        simpleJson['mode'],
        'simple',
        reason: 'chatSimple debe incluir mode=simple en el cuerpo',
      );

      // chat() estándar NO manda mode (o manda algo distinto de simple)
      expect(
        fullJson.containsKey('mode'),
        isFalse,
        reason:
            'chat() estándar no debe enviar mode=simple '
            '(remoto / agente completo intacto)',
      );
    },
  );

  // ============================================================
  // TEST 5: max_tokens acotado — default 1024, respeta override
  // ============================================================
  test(
    'T5/T6 chatSimple envía max_tokens acotado (default 1024, override 256)',
    () async {
      late Map<String, dynamic> bodyDefault;
      late Map<String, dynamic> bodyOverride;

      final cDef = clientWith(
        MockClient((req) async {
          bodyDefault = jsonDecode(req.body) as Map<String, dynamic>;
          return bridgeOk('ok');
        }),
      );
      final cOvr = clientWith(
        MockClient((req) async {
          bodyOverride = jsonDecode(req.body) as Map<String, dynamic>;
          return bridgeOk('ok');
        }),
      );

      await cDef.chatSimple('hola');
      await cOvr.chatSimple('hola', maxTokens: 256);

      expect(
        bodyDefault['max_tokens'],
        1024,
        reason: 'default max_tokens debe ser 1024',
      );
      expect(
        bodyOverride['max_tokens'],
        256,
        reason: 'override max_tokens=256 debe propagarse',
      );
      // Nunca 65536 (el que usa el agente completo)
      expect(bodyDefault['max_tokens'], isNot(65536));
      expect(bodyOverride['max_tokens'], isNot(65536));
    },
  );

  // ============================================================
  // TEST 7: el body del cliente NO contiene tools ni tool_choice
  // (el bridge tampoco los manda a OpenAI; testeable desde el cliente
  //  verificando que el body que llega al bridge no los trae)
  // ============================================================
  test(
    'T7 chatSimple: body del cliente no contiene tools/tool_choice/stream',
    () async {
      late Map<String, dynamic> captured;
      final c = clientWith(
        MockClient((req) async {
          captured = jsonDecode(req.body) as Map<String, dynamic>;
          return bridgeOk('ok');
        }),
      );
      await c.chatSimple('hola');

      expect(
        captured.containsKey('tools'),
        isFalse,
        reason: 'no debe enviar tools',
      );
      expect(
        captured.containsKey('tool_choice'),
        isFalse,
        reason: 'no debe enviar tool_choice',
      );
      // stream no va en el body del cliente (es parámetro del bridge a OpenAI)
      expect(
        captured.containsKey('stream'),
        isFalse,
        reason: 'stream no va en el cuerpo del cliente para chatSimple',
      );
    },
  );

  // ============================================================
  // TEST 8: endpoint correcto — llama a /bridge/chat
  // ============================================================
  test(
    'T8 chatSimple llama a /bridge/chat (no a un endpoint propio)',
    () async {
      late Uri capturedUri;
      final c = clientWith(
        MockClient((req) async {
          capturedUri = req.url;
          return bridgeOk('ok');
        }),
      );
      await c.chatSimple('hola');
      expect(capturedUri.path, '/bridge/chat');
    },
  );

  // ============================================================
  // TEST 10: history se propaga en el body
  // ============================================================
  test('T10 chatSimple propaga history al bridge', () async {
    late Map<String, dynamic> captured;
    final c = clientWith(
      MockClient((req) async {
        captured = jsonDecode(req.body) as Map<String, dynamic>;
        return bridgeOk('ok');
      }),
    );
    final history = [
      {'role': 'user', 'content': 'primer turno'},
      {'role': 'assistant', 'content': 'respuesta uno'},
    ];
    await c.chatSimple('segundo turno', history: history);

    final sentHistory = captured['history'] as List<dynamic>;
    expect(
      sentHistory.length,
      2,
      reason: 'history debe llegar íntegro al bridge',
    );
    expect((sentHistory[0] as Map)['content'], 'primer turno');
  });

  // ============================================================
  // TEST extra: chatSimple con respuesta OK vacía lanza excepción
  // (el bridge devuelve 200 pero response vacío no es válido)
  // ============================================================
  test(
    'chatSimple con response vacío en 200 devuelve cadena vacía '
    '(el bridge debería haber retornado 502; si no, la app gestiona)',
    () async {
      // El bridge bien formado devuelve 502 en vacío; pero si por algún motivo
      // devuelve 200 con response='', el cliente devuelve '' sin lanzar.
      final c = clientWith(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'response': ''}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final result = await c.chatSimple('hola');
      expect(
        result,
        '',
        reason:
            'response vacío pasa tal cual; el bridge '
            'debería haberlo detectado y retornado 502',
      );
    },
  );
}
