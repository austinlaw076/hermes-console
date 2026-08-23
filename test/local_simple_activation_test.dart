// Tests TASK-019b: activación de chat-local-simple desde la instancia.
//
// Cubre:
//  1. Serialización round-trip de LocalChatMode en SavedConnection (complementa
//     connection_manager_test.dart que ya tiene el grupo LocalChatMode).
//  2. Resolución de modo: auto/simple → useSimple=true; agent → useSimple=false.
//     Esta es la lógica central de _sendViaBridge() en active_chat_service.dart.
//  3. Instancia remota (kind != localhost) no es afectada por localChatMode.
//  4. BridgeClient.chatSimple no incluye tools (regresión desde TASK-019).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/bridge_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Replica la lógica de resolución de _sendViaBridge() para testearla como
// función pura sin levantar el servicio completo.
bool resolveUseSimple(LocalChatMode mode) =>
    mode == LocalChatMode.simple || mode == LocalChatMode.auto;

void main() {
  // =========================================================
  // Grupo 1: Resolución de modo
  // =========================================================
  group('Resolución de modo local (TASK-019b)', () {
    test('auto → useSimple = true', () {
      expect(
        resolveUseSimple(LocalChatMode.auto),
        isTrue,
        reason:
            'auto debe resolver a simple porque sin detección de '
            'capacidad del modelo asumimos modelo pequeño',
      );
    });

    test('simple → useSimple = true', () {
      expect(resolveUseSimple(LocalChatMode.simple), isTrue);
    });

    test('agent → useSimple = false (agente completo)', () {
      expect(
        resolveUseSimple(LocalChatMode.agent),
        isFalse,
        reason: 'agent usa hermes -z con tools; reservado para modelos ≥7B',
      );
    });
  });

  // =========================================================
  // Grupo 2: LocalChatMode en SavedConnection
  // =========================================================
  group('SavedConnection.localChatMode', () {
    SavedConnection localConn({LocalChatMode mode = LocalChatMode.auto}) =>
        SavedConnection(
          id: 'loc',
          label: 'Local Termux',
          host: '127.0.0.1',
          port: 8642,
          apiKey: 'tok',
          onDeviceLoopback: true,
          kind: InstanceKind.localhost,
          localChatMode: mode,
        );

    SavedConnection remoteConn() => SavedConnection(
      id: 'rem',
      label: 'VPS',
      host: 'hermes.example.com',
      port: 8642,
      apiKey: 'tok',
      kind: InstanceKind.vps,
      // localChatMode se ignora en remoto
    );

    test('instancia local: kind == localhost, localChatMode se persiste', () {
      final conn = localConn(mode: LocalChatMode.simple);
      expect(conn.kind, InstanceKind.localhost);
      expect(conn.localChatMode, LocalChatMode.simple);
    });

    test('instancia remota: kind != localhost, localChatMode irrelevante', () {
      final conn = remoteConn();
      // El campo existe pero _sendViaBridge no se llama para remotos.
      expect(conn.kind, isNot(InstanceKind.localhost));
    });

    test('round-trip simple', () {
      final conn = localConn(mode: LocalChatMode.simple);
      expect(
        SavedConnection.fromMap(conn.toMap()).localChatMode,
        LocalChatMode.simple,
      );
    });

    test('round-trip agent', () {
      final conn = localConn(mode: LocalChatMode.agent);
      expect(
        SavedConnection.fromMap(conn.toMap()).localChatMode,
        LocalChatMode.agent,
      );
    });

    test('clave ausente en mapa migra a auto', () {
      final map = localConn().toMap()..remove('local_chat_mode');
      expect(SavedConnection.fromMap(map).localChatMode, LocalChatMode.auto);
    });

    test('copyWith sin localChatMode conserva el valor actual', () {
      final conn = localConn(mode: LocalChatMode.agent);
      expect(conn.copyWith(label: 'X').localChatMode, LocalChatMode.agent);
    });
  });

  // =========================================================
  // Grupo 3: chatSimple no incluye tools (regresión TASK-019)
  // =========================================================
  group('chatSimple no incluye tools (regresión TASK-019)', () {
    BridgeClient clientWith(MockClient mock) => BridgeClient(
      baseUrl: 'http://127.0.0.1:9131',
      token: 'tok',
      httpClient: mock,
    );

    test('T-REG: payload de chatSimple no tiene tools/tool_choice', () async {
      late Map<String, dynamic> captured;
      final c = clientWith(
        MockClient((req) async {
          captured = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'ok': true, 'response': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await c.chatSimple('hola');
      expect(captured.containsKey('tools'), isFalse);
      expect(captured.containsKey('tool_choice'), isFalse);
      expect(captured['mode'], 'simple');
    });

    test(
      'T-REG: chat() estándar no envía mode=simple (remoto intacto)',
      () async {
        late Map<String, dynamic> captured;
        final c = clientWith(
          MockClient((req) async {
            captured = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({'ok': true, 'response': 'ok'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await c.chat('hola');
        expect(
          captured.containsKey('mode'),
          isFalse,
          reason: 'chat() estándar no debe mandar mode=simple',
        );
      },
    );
  });
}
