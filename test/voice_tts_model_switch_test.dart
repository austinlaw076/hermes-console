import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:hermes_android/core/services/voice/voice_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SwitchingTts implements TtsEngine {
  _SwitchingTts({required this.block});

  final bool block;
  final Completer<void> started = Completer<void>();
  final Completer<void> _released = Completer<void>();
  final List<String> spoken = [];
  bool disposed = false;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    if (!started.isCompleted) started.complete();
    if (block) await _released.future;
  }

  @override
  Future<void> stop() async => _release();

  @override
  Future<void> dispose() async {
    disposed = true;
    _release();
  }

  void _release() {
    if (!_released.isCompleted) _released.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cambiar de voz durante síntesis libera la anterior antes de hablar',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = _SwitchingTts(block: true);
      final second = _SwitchingTts(block: false);
      var factoryCalls = 0;
      final voice = VoiceService(
        prefs,
        SecureStorage(),
        initialSettings: const VoiceSettings(
          ttsEngine: TtsEngineKind.onnx,
          onnxVoiceId: 'es_ES-carlos-medium',
        ),
      );
      voice.debugTtsFactory = () => factoryCalls++ == 0 ? first : second;
      addTearDown(voice.dispose);

      await voice.enqueueSpeech('Frase con la voz anterior.');
      await first.started.future.timeout(const Duration(seconds: 1));

      await voice.saveSettings(
        voice.settings.copyWith(onnxVoiceId: 'es_ES-davefx-medium'),
      );

      expect(first.disposed, isTrue);
      await voice.enqueueSpeech('Frase con David.');
      await second.started.future.timeout(const Duration(seconds: 1));
      await voice.waitSpeechDone().timeout(const Duration(seconds: 1));

      expect(first.spoken, ['Frase con la voz anterior.']);
      expect(second.spoken, ['Frase con David.']);
      expect(factoryCalls, 2);
    },
  );
}
