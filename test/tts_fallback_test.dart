import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';

void main() {
  group('VoiceService.speakOrFallback — fallback Kokoro → sistema TTS', () {
    test('primary OK: returns true, fallback no se llama', () async {
      bool fallbackCalled = false;

      final result = await VoiceService.speakOrFallback(
        text: 'Hola Jarvis',
        isLocal: false,
        primary: (_) async {},
        fallback: (_) async => fallbackCalled = true,
      );

      expect(result, isTrue);
      expect(fallbackCalled, isFalse);
    });

    test(
      'primary lanza (Kokoro :9443 caído), isLocal=false: fallback se ejecuta, returns true',
      () async {
        String? fallbackReceivedText;

        final result = await VoiceService.speakOrFallback(
          text: 'Hola Jarvis',
          isLocal: false,
          primary: (_) async => throw Exception('Connection refused :9443'),
          fallback: (t) async => fallbackReceivedText = t,
        );

        expect(result, isTrue);
        expect(fallbackReceivedText, equals('Hola Jarvis'));
      },
    );

    test(
      'primary lanza, isLocal=true (relleno local): fallback no se llama, returns false',
      () async {
        bool fallbackCalled = false;

        final result = await VoiceService.speakOrFallback(
          text: 'bip',
          isLocal: true,
          primary: (_) async => throw Exception('engine local colgado'),
          fallback: (_) async => fallbackCalled = true,
        );

        expect(result, isFalse);
        expect(fallbackCalled, isFalse);
      },
    );

    test(
      'primary y fallback lanzan: returns false, no propaga excepción',
      () async {
        final result = await VoiceService.speakOrFallback(
          text: 'test',
          isLocal: false,
          primary: (_) async => throw Exception('Kokoro caído'),
          fallback: (_) async => throw Exception('sistema TTS también caído'),
        );

        expect(result, isFalse);
      },
    );
  });
}
