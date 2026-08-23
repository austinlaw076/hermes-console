import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/capability_payload_sanitizer.dart';

void main() {
  const sanitizer = CapabilityPayloadSanitizer();

  test('diagnóstico conserva solo allowlist y nunca contenido sensible', () {
    final safe = sanitizer.sanitizeDiagnostic({
      'method': 'slash.exec',
      'capability_state': 'available',
      'capability_source': 'probe',
      'duration_bucket': 'lt_500ms',
      'response_size': 120,
      'response_count': 1,
      'error_code': 4018,
      'error_class': 'rpc_error',
      'connection_id': 'conn-opaque-1',
      'arg': 'private focus',
      'output': 'private output',
      'prompt': 'private prompt',
      'headers': {'Authorization': 'Bearer secret'},
      'cookies': 'session=secret',
      'cwd': '/home/private/project',
      'raw': {'nested': 'payload'},
    });

    expect(safe.keys, {
      'method',
      'capability_state',
      'capability_source',
      'duration_bucket',
      'response_size',
      'response_count',
      'error_code',
      'error_class',
      'connection_id',
    });
    expect(safe.toString(), isNot(contains('secret')));
    expect(safe.toString(), isNot(contains('/home/private')));
  });

  test('respuesta operacional aplica allowlist y límites', () {
    final safe = sanitizer.sanitizeCommandResponse({
      'type': 'exec',
      'output': 'x' * 5000,
      'message': 'message',
      'api_key': 'secret',
      'headers': {'authorization': 'secret'},
    });

    expect(
      safe['output'],
      isA<String>().having((v) => v.length, 'length', 4000),
    );
    expect(safe, isNot(contains('api_key')));
    expect(safe, isNot(contains('headers')));
  });

  test('límite estructural detecta nesting y exceso de nodos', () {
    expect(
      sanitizer.withinStructuralLimits({
        'a': {
          'b': {
            'c': {
              'd': {'e': true},
            },
          },
        },
      }, maxDepth: 3),
      isFalse,
    );
  });
}
