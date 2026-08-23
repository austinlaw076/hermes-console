import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/state/companion_presence_controller.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';

void main() {
  late CompanionPresenceController c;
  setUp(() => c = CompanionPresenceController());
  tearDown(() => c.dispose());

  group('CompanionPresenceController (006 US1)', () {
    test('estado inicial = idle (online)', () {
      expect(c.mood, HermesSparkMood.idle);
    });

    test('conexión: connecting/offline/online', () {
      c.setConnectionStatus(PresenceConnection.connecting);
      expect(c.mood, HermesSparkMood.connecting);
      c.setConnectionStatus(PresenceConnection.offline);
      expect(c.mood, HermesSparkMood.offline);
      c.setConnectionStatus(PresenceConnection.online);
      expect(c.mood, HermesSparkMood.idle);
    });

    test(
      'messageSent → salto breve → thinking; completado → success → idle',
      () {
        c.onEvent(PresenceEvent.messageSent);
        expect(c.mood, HermesSparkMood.jump); // gesto breve al enviar
        c.debugSettleTransient(); // decae el salto
        expect(c.mood, HermesSparkMood.thinking);
        c.onEvent(PresenceEvent.responseCompleted);
        expect(c.mood, HermesSparkMood.success);
        c.debugSettleTransient();
        expect(c.mood, HermesSparkMood.idle);
      },
    );

    test('approvalNeeded → waiting (persistente) hasta resolver', () {
      c.onEvent(PresenceEvent.approvalNeeded);
      expect(c.mood, HermesSparkMood.waiting);
      c.onEvent(PresenceEvent.responseCompleted);
      expect(c.mood, HermesSparkMood.success);
      c.debugSettleTransient();
      expect(c.mood, HermesSparkMood.idle);
    });

    test('runFailed → error → idle', () {
      c.onEvent(PresenceEvent.messageSent);
      c.onEvent(PresenceEvent.runFailed);
      expect(c.mood, HermesSparkMood.error);
      c.debugSettleTransient();
      expect(c.mood, HermesSparkMood.idle);
    });

    test('prioridad: error overlay manda sobre approval', () {
      c.onEvent(PresenceEvent.approvalNeeded); // waiting
      c.onEvent(PresenceEvent.runFailed); // limpia approval + overlay error
      expect(c.mood, HermesSparkMood.error);
    });

    test('prioridad: approval(waiting) sobre thinking', () {
      c.onEvent(PresenceEvent.messageSent); // thinking
      c.onEvent(PresenceEvent.approvalNeeded); // waiting gana
      expect(c.mood, HermesSparkMood.waiting);
    });

    test('appOpened y petTapped → saludo(success) transitorio', () {
      c.onEvent(PresenceEvent.appOpened);
      expect(c.mood, HermesSparkMood.success);
      c.debugSettleTransient();
      expect(c.mood, HermesSparkMood.idle);

      c.onEvent(PresenceEvent.petTapped);
      expect(c.mood, HermesSparkMood.success);
    });

    test('petTapped sobre estado offline vuelve a offline tras el saludo', () {
      c.setConnectionStatus(PresenceConnection.offline);
      c.onEvent(PresenceEvent.petTapped);
      expect(c.mood, HermesSparkMood.success);
      c.debugSettleTransient();
      expect(c.mood, HermesSparkMood.offline);
    });

    test('replayToken incrementa en cada transitorio', () {
      final t0 = c.replayToken;
      c.onEvent(PresenceEvent.petTapped);
      expect(c.replayToken, greaterThan(t0));
    });

    test('notifica a los listeners en los cambios de ánimo', () {
      var n = 0;
      c.addListener(() => n++);
      c.onEvent(PresenceEvent.messageSent); // idle→thinking
      expect(n, greaterThan(0));
    });
  });
}
