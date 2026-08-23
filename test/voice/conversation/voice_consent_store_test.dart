import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/conversation/voice_consent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'el primer uso es foreground-only y todavía no implica consentimiento',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = VoiceConsentStore(prefs);

      expect(store.disclosureAccepted, isFalse);
      expect(store.continueWhenLocked, isFalse);
      expect(store.conversationEnabled, isTrue);
    },
  );

  test('aceptar guarda de forma explícita la opción elegida', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = VoiceConsentStore(prefs);

    await store.acceptDisclosure(continueWhenLocked: true);

    expect(store.disclosureAccepted, isTrue);
    expect(store.continueWhenLocked, isTrue);
    final restored = VoiceConsentStore(prefs);
    expect(restored.disclosureAccepted, isTrue);
    expect(restored.continueWhenLocked, isTrue);
  });

  test(
    'cambiar la continuidad no inventa consentimiento de primer uso',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = VoiceConsentStore(prefs);

      await store.setContinueWhenLocked(true);

      expect(store.continueWhenLocked, isTrue);
      expect(store.disclosureAccepted, isFalse);
    },
  );

  test('notifica únicamente cuando cambia una preferencia', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = VoiceConsentStore(prefs);
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.setContinueWhenLocked(false);
    expect(notifications, 0);

    await store.acceptDisclosure(continueWhenLocked: false);
    expect(notifications, 1);

    await store.setContinueWhenLocked(true);
    expect(notifications, 2);

    await store.setConversationEnabled(false);
    expect(store.conversationEnabled, isFalse);
    expect(notifications, 3);
    expect(VoiceConsentStore(prefs).conversationEnabled, isFalse);
  });
}
