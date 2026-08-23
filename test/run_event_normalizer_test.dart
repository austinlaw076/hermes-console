import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/run_event_normalizer.dart';

void main() {
  group('normalizeRunEvent', () {
    test(
      'tool.started → progressLabel con nombre de herramienta y status running',
      () {
        // El normalizador lee event['tool'] en raíz, no en event['data'].
        final result = normalizeRunEvent({
          'event': 'tool.started',
          'tool': 'bash',
        });
        expect(result, isNotNull);
        expect(result!.progressLabel, contains('bash'));
        expect(result.lastStatus, 'running');
        expect(result.isTerminal, isFalse);
        expect(result.shouldPersist, isTrue);
      },
    );

    test('tool.started sin tool → usa fallback "herramienta"', () {
      final result = normalizeRunEvent({'event': 'tool.started'});
      expect(result, isNotNull);
      expect(result!.lastStatus, 'running');
      expect(result.progressLabel, contains('herramienta'));
    });

    test(
      'tool.completed sin error → progressLabel "Completado:", shouldPersist true',
      () {
        final result = normalizeRunEvent({
          'event': 'tool.completed',
          'tool': 'python',
        });
        expect(result, isNotNull);
        expect(result!.progressLabel, contains('Completado'));
        expect(result.lastStatus, 'running');
        expect(result.isTerminal, isFalse);
        expect(result.shouldPersist, isTrue);
      },
    );

    test('tool.completed con error:true → progressLabel "Error en:"', () {
      // La señal de error es el booleano event['error'] == true (no un string).
      final result = normalizeRunEvent({
        'event': 'tool.completed',
        'tool': 'bash',
        'error': true,
      });
      expect(result, isNotNull);
      expect(result!.progressLabel, contains('Error'));
      expect(result.progressLabel, isNot(contains('Completado')));
    });

    test('approval.request → status waiting_for_approval, no terminal', () {
      final result = normalizeRunEvent({'event': 'approval.request'});
      expect(result, isNotNull);
      expect(result!.lastStatus, 'waiting_for_approval');
      expect(result.isTerminal, isFalse);
      expect(result.shouldPersist, isTrue);
    });

    test('approval.responded con choice → label incluye la elección', () {
      // El normalizador lee event['choice'] en raíz.
      final result = normalizeRunEvent({
        'event': 'approval.responded',
        'choice': 'once',
      });
      expect(result, isNotNull);
      expect(result!.lastStatus, 'running');
      expect(result.progressLabel, contains('once'));
      expect(result.isTerminal, isFalse);
    });

    test('approval.responded sin choice → label genérico', () {
      final result = normalizeRunEvent({'event': 'approval.responded'});
      expect(result, isNotNull);
      expect(result!.lastStatus, 'running');
      expect(result.progressLabel, isNotNull);
    });

    test('run.completed → isTerminal true, status completed', () {
      final result = normalizeRunEvent({'event': 'run.completed', 'data': {}});
      expect(result, isNotNull);
      expect(result!.isTerminal, isTrue);
      expect(result.lastStatus, 'completed');
      expect(result.shouldPersist, isTrue);
    });

    test('run.failed → isTerminal true, status failed', () {
      final result = normalizeRunEvent({
        'event': 'run.failed',
        'data': {'error': 'timeout'},
      });
      expect(result, isNotNull);
      expect(result!.isTerminal, isTrue);
      expect(result.lastStatus, 'failed');
      expect(result.shouldPersist, isTrue);
    });

    test('run.cancelled → isTerminal true, status cancelled', () {
      final result = normalizeRunEvent({'event': 'run.cancelled', 'data': {}});
      expect(result, isNotNull);
      expect(result!.isTerminal, isTrue);
      expect(result.lastStatus, 'cancelled');
    });

    test(
      'message.delta → shouldPersist false (no escribe en SharedPreferences)',
      () {
        final result = normalizeRunEvent({
          'event': 'message.delta',
          'data': {'content': 'hello', 'delta': 'hello'},
        });
        expect(result, isNotNull);
        expect(result!.shouldPersist, isFalse);
        expect(result.isTerminal, isFalse);
      },
    );

    test(
      'message.delta → lastStatus es running (actualiza override en memoria)',
      () {
        final result = normalizeRunEvent({'event': 'message.delta'});
        expect(result, isNotNull);
        expect(result!.lastStatus, 'running');
      },
    );

    test('evento desconocido → devuelve null', () {
      expect(normalizeRunEvent({'event': 'unknown.event'}), isNull);
      expect(normalizeRunEvent({'event': ''}), isNull);
      expect(normalizeRunEvent({}), isNull);
    });

    test('evento null en campo event → devuelve null', () {
      expect(normalizeRunEvent({'event': null}), isNull);
    });
  });
}
