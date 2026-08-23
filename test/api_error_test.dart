import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/api_error.dart';

void main() {
  group('humanizeApiError', () {
    test('extrae detail de un error HTTP con JSON', () {
      final e = Exception(
        'HTTP 400: {"detail":"Profile name \'test\' is reserved"}',
      );
      expect(humanizeApiError(e), "Profile name 'test' is reserved");
    });

    test('soporta campo message', () {
      final e = Exception('HTTP 500: {"message":"algo falló"}');
      expect(humanizeApiError(e), 'algo falló');
    });

    test('soporta detail como lista de validación de FastAPI', () {
      final e = Exception(
        'HTTP 422: {"detail":[{"loc":["body","name"],"msg":"field required"}]}',
      );
      expect(humanizeApiError(e), 'field required');
    });

    test('cuerpo no-JSON se devuelve tal cual', () {
      final e = Exception('HTTP 404: Not Found');
      expect(humanizeApiError(e), 'Not Found');
    });

    test('JSON sin campo conocido cae a mensaje genérico con código', () {
      final e = Exception('HTTP 503: {"foo":"bar"}');
      expect(humanizeApiError(e), contains('503'));
    });

    test('quita el prefijo Exception:', () {
      final e = Exception('algo sin formato http');
      expect(humanizeApiError(e), 'algo sin formato http');
    });
  });
}
