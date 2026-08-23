import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/chat_event_cards.dart';

void main() {
  group('ChatEventInfo.classify', () {
    test('pending_approval JSON NO se trata como texto de chat', () {
      final msg = {
        'role': 'assistant',
        'content': jsonEncode({
          'command': 'rm -rf /var/data',
          'description': 'Borrar datos antiguos',
          'approval_pending': true,
          'pattern_key': 'fs.delete',
          'status': 'pending_approval',
          'run_id': 'run_123',
        }),
      };
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.approval);
      expect(ev.approvalPending, isTrue);
      expect(ev.command, 'rm -rf /var/data');
      expect(ev.runId, 'run_123');
    });

    test('salida de herramienta con exit_code → toolEvent, no burbuja', () {
      final msg = {
        'role': 'tool',
        'content': jsonEncode({
          'command': 'ls -la',
          'output': 'total 0\ndrwxr-xr-x ...',
          'exit_code': 0,
          'status': 'completed',
        }),
      };
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.toolEvent);
      expect(ev.exitCode, 0);
      expect(ev.output, contains('total 0'));
    });

    test('content como Map (no string) también se estructura', () {
      final msg = {
        'role': 'assistant',
        'content': {'command': 'systemctl restart nginx', 'exit_code': 1},
      };
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.toolEvent);
      expect(ev.exitCode, 1);
    });

    test('respuesta normal del asistente se mantiene como texto', () {
      final msg = {
        'role': 'assistant',
        'content': 'Claro, aquí tienes el resumen que pediste.',
      };
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.text);
      expect(ev.text, contains('resumen'));
    });

    test('markdown con bloque de código NO se confunde con payload', () {
      final msg = {
        'role': 'assistant',
        'content': 'Ejecuta esto:\n```\nrm -rf build\n```\nY listo.',
      };
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.text);
    });

    test(
      'JSON bare sin claves internas se trata como texto (sin falsos positivos)',
      () {
        final msg = {
          'role': 'assistant',
          'content': jsonEncode({'foo': 'bar', 'n': 1}),
        };
        final ev = ChatEventInfo.classify(msg);
        expect(ev.kind, ChatEventKind.text);
      },
    );

    test('mensaje de usuario nunca se estructura aunque parezca payload', () {
      // El llamador (chat) ya excluye role==user; aquí validamos que el rol
      // tool es la otra vía y que un user con JSON simple cae en texto.
      final msg = {'role': 'user', 'content': 'mi comando favorito es ls'};
      final ev = ChatEventInfo.classify(msg);
      expect(ev.kind, ChatEventKind.text);
    });
  });

  group('traceOutcome (TASK-017: errores de tool recuperados)', () {
    ChatTraceEvent ev(String status) =>
        ChatTraceEvent(id: status, label: status, status: status);

    test('run activo → working (sin importar fallos intermedios)', () {
      expect(
        traceOutcome(events: [ev('failed'), ev('running')], active: true),
        TraceOutcome.working,
      );
    });

    test('sin fallos y terminado → completed', () {
      expect(
        traceOutcome(events: [ev('completed'), ev('finished')], active: false),
        TraceOutcome.completed,
      );
    });

    test('failed + completed (terminado) → recovered, NO error crítico', () {
      expect(
        traceOutcome(events: [ev('failed'), ev('completed')], active: false),
        TraceOutcome.recovered,
      );
    });

    test('solo fallos y terminado → failed (error real)', () {
      expect(
        traceOutcome(events: [ev('failed'), ev('error')], active: false),
        TraceOutcome.failed,
      );
    });

    test('sin eventos y terminado → completed', () {
      expect(traceOutcome(events: [], active: false), TraceOutcome.completed);
    });
  });
}
