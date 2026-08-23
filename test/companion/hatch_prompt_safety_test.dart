import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/hatch/prompt_safety.dart';

void main() {
  const safety = PromptSafety();

  group('PromptSafety', () {
    test('acepta y normaliza un prompt válido', () {
      expect(safety.sanitize('  un zorro   naranja  '), 'un zorro naranja');
      expect(safety.isAcceptable('gato astronauta'), isTrue);
    });

    test('rechaza vacío', () {
      expect(
        () => safety.sanitize('   '),
        throwsA(isA<PromptRejectedException>()),
      );
      expect(safety.isAcceptable(''), isFalse);
    });

    test('rechaza demasiado largo', () {
      final long = 'a' * (PromptSafety.maxLength + 1);
      expect(
        () => safety.sanitize(long),
        throwsA(isA<PromptRejectedException>()),
      );
    });

    test('rechaza términos bloqueados (es/en)', () {
      expect(safety.isAcceptable('un gato nsfw'), isFalse);
      expect(safety.isAcceptable('algo con sangre'), isFalse);
      expect(safety.isAcceptable('imagen porno'), isFalse);
    });
  });
}
