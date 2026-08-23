import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notifications/voice_notification_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVoicePlatform implements VoicePlatformNotifier {
  int channelCalls = 0;
  final List<({int id, String body})> posts = [];
  final List<int> cancels = [];

  @override
  Future<void> ensureChannel() async => channelCalls++;

  @override
  Future<bool> post({
    required int id,
    required String title,
    required String body,
  }) async {
    posts.add((id: id, body: body));
    return true;
  }

  @override
  Future<void> cancel(int id) async => cancels.add(id);
}

void main() {
  // Los textos se localizan leyendo `app_locale` de SharedPreferences (i18n
  // seguro en 2º plano). Fijamos español para aserciones estables.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'app_locale': 'es'}));

  group('VoiceNotificationController', () {
    test(
      'mapea cada estado al texto y al mismo id (notificación única)',
      () async {
        final fake = _FakeVoicePlatform();
        final c = VoiceNotificationController(fake);

        await c.showListening();
        await c.showTranscribing();
        await c.showThinking();
        await c.showToolRunning();
        await c.showWaitingApproval();
        await c.showSpeaking();
        await c.showError();

        expect(fake.posts.map((p) => p.body).toList(), [
          'Escuchando…',
          'Transcribiendo…',
          'Pensando…',
          'Ejecutando una herramienta…',
          'Necesita aprobación',
          'Hablando…',
          'Error en modo voz',
        ]);
        // Siempre la MISMA notificación (mismo id ⇒ se actualiza en sitio).
        expect(
          fake.posts.every((p) => p.id == VoiceNotificationController.notifId),
          isTrue,
        );
        // El canal se crea una sola vez (perezoso).
        expect(fake.channelCalls, 1);
      },
    );

    test('speaking actualiza la misma notificación, no crea otra', () async {
      final fake = _FakeVoicePlatform();
      final c = VoiceNotificationController(fake);
      await c.showThinking();
      await c.showSpeaking();
      expect(fake.posts, hasLength(2));
      expect(fake.posts[0].id, fake.posts[1].id);
    });

    test(
      'no genera spam: mismo estado consecutivo no vuelve a postear',
      () async {
        final fake = _FakeVoicePlatform();
        final c = VoiceNotificationController(fake);
        await c.showListening();
        await c.showListening();
        await c.showListening();
        expect(fake.posts, hasLength(1));
      },
    );

    test('clear cancela la notificación; segundo clear no hace nada', () async {
      final fake = _FakeVoicePlatform();
      final c = VoiceNotificationController(fake);
      await c.showSpeaking();
      await c.clearVoiceNotification();
      await c.clearVoiceNotification();
      expect(fake.cancels, [VoiceNotificationController.notifId]);
    });

    test(
      'tras clear, el mismo estado vuelve a postear (sesión nueva)',
      () async {
        final fake = _FakeVoicePlatform();
        final c = VoiceNotificationController(fake);
        await c.showListening();
        await c.clearVoiceNotification();
        await c.showListening();
        expect(fake.posts, hasLength(2));
      },
    );

    test('canal e id propios, separados de alerts/runs', () {
      expect(VoiceNotificationController.channelId, 'hermes_voice');
      // Fuera de runs (7100–8123 / 9000–9511) y alertas fijas (7000–7004).
      expect(VoiceNotificationController.notifId, 8801);
    });
  });
}
