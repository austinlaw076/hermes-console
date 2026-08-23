import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/conversation/local_voice_command_detector.dart';

void main() {
  const detector = LocalVoiceCommandDetector();

  LocalVoiceCommand? es(String text) =>
      detector.detect(text, language: 'es-ES');
  LocalVoiceCommand? en(String text) =>
      detector.detect(text, language: 'en-US');

  group('comandos naturales en español', () {
    test('silencia con variantes, cortesía y más de una cláusula', () {
      expect(es('Cállate.'), LocalVoiceCommand.silenceCurrent);
      expect(
        es('Vale, cállate; no hable más, por favor.'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(
        es('Hermes, ¿puedes parar de hablar?'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(es('Ya está, gracias.'), LocalVoiceCommand.silenceCurrent);
      expect(es('No quiero escucharte más.'), LocalVoiceCommand.silenceCurrent);
      expect(
        es('Serías tan amable de dejar de leer ya.'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(
        es('Creo que ya puedes cortar el audio, gracias.'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(
        es('No me apetece seguir escuchando, puedes parar.'),
        LocalVoiceCommand.silenceCurrent,
      );
    });

    test('pausa y terminar son intenciones distintas', () {
      expect(es('Pausa la conversación.'), LocalVoiceCommand.pause);
      expect(es('Vale, haz una pausa.'), LocalVoiceCommand.pause);
      expect(es('Hermes, termina la conversación.'), LocalVoiceCommand.end);
      expect(es('Dejémoslo aquí, gracias.'), LocalVoiceCommand.end);
    });

    test('no consume charla que solo contiene palabras parecidas', () {
      expect(es('Háblame del silencio.'), isNull);
      expect(es('Vale.'), isNull);
      expect(es('¿Por qué no hablas más despacio?'), isNull);
      expect(es('No quiero que hables más rápido.'), isNull);
      expect(es('Explícame la frase no hables más.'), isNull);
      expect(es('¿Cómo puedo silenciar el audio?'), isNull);
    });
  });

  group('comandos naturales en inglés', () {
    test('acepta controles completos', () {
      expect(
        en('Okay Hermes, stop talking please.'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(en("That's enough, thanks."), LocalVoiceCommand.silenceCurrent);
      expect(
        en('Could you quit speaking now?'),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(
        en("I don't want to keep listening, you can stop now."),
        LocalVoiceCommand.silenceCurrent,
      );
      expect(en('Pause the conversation.'), LocalVoiceCommand.pause);
      expect(en("Let's stop here."), LocalVoiceCommand.end);
    });

    test('rechaza conversación y locales no soportados', () {
      expect(en('Tell me why people stop talking.'), isNull);
      expect(en('Could you speak more slowly?'), isNull);
      expect(en('How do I mute the audio?'), isNull);
      expect(detector.detect('cállate', language: 'fr-FR'), isNull);
    });
  });

  test('rechaza entradas anormalmente largas', () {
    final text = List.filled(50, 'cállate').join(' ');
    expect(es(text), isNull);
  });
}
