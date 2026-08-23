import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/stt_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStt extends SttEngine {
  @override
  bool get supportsPartials => true;

  @override
  Future<bool> available() async => true;

  @override
  Stream<SttResult> listen({
    String localeId = 'es_ES',
    void Function()? onSpeechEnd,
    void Function()? onCaptureReady,
    bool continuous = false,
  }) {
    onCaptureReady?.call();
    return const Stream<SttResult>.empty();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la captura manual queda disponible sin un dueño exterior', () async {
    SharedPreferences.setMockInitialValues({});
    final voice = VoiceService(
      await SharedPreferences.getInstance(),
      SecureStorage(),
    );

    expect(await voice.prepareForMicrophoneCapture(), isTrue);

    await voice.dispose();
  });

  test('publica captura activa y liberada durante el dictado', () async {
    SharedPreferences.setMockInitialValues({});
    final voice = VoiceService(
      await SharedPreferences.getInstance(),
      SecureStorage(),
    )..debugSttFactory = _FakeStt.new;
    final states = <bool>[];
    voice.microphoneCapturing.addListener(
      () => states.add(voice.microphoneCapturing.value),
    );

    voice.startDictation();
    await voice.stopDictation();

    expect(states, [true, false]);
    await voice.dispose();
  });

  test('conversación y dictado esperan la barrera antes de startDictation', () {
    for (final path in const [
      'lib/core/services/voice/conversation/'
          'local_voice_conversation_controller.dart',
      'lib/core/screens/chat_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final prepare = source.indexOf('prepareForMicrophoneCapture()');
      final start = source.indexOf('startDictation(', prepare);
      expect(prepare, greaterThanOrEqualTo(0), reason: path);
      expect(start, greaterThan(prepare), reason: path);
    }
  });
}
