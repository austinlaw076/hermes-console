import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HangingTtsEngine implements TtsEngine {
  final Completer<void> speaking = Completer<void>();
  int stopCount = 0;

  @override
  Future<void> speak(String text) => speaking.future;

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la prueba TTS colgada vence y detiene el motor', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final voice = VoiceService(prefs, SecureStorage());
    final engine = _HangingTtsEngine();
    addTearDown(voice.dispose);

    await expectLater(
      voice.previewTts(
        engine,
        'Prueba',
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(engine.stopCount, 1);
  });
}
