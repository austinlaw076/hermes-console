import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:hermes_android/core/services/voice/voice_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy Kokoro prefs migrate only into the Kokoro profile', () async {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'es',
      'voice_streaming_tts_profile': 'kokoro',
      'voice_streaming_tts_url': 'http://kokoro.test:8880/v1',
      'voice_streaming_tts_voice': 'ef_dora',
      'voice_streaming_tts_model': 'kokoro',
    });
    final prefs = await SharedPreferences.getInstance();

    final settings = VoiceSettings.load(prefs);

    expect(settings.kokoroTtsUrl, 'http://kokoro.test:8880/v1');
    expect(settings.kokoroTtsVoice, 'ef_dora');
    expect(settings.kokoroTtsModel, 'kokoro');
    expect(settings.openAiTtsUrl, isEmpty);
    expect(settings.openAiTtsVoice, 'alloy');
    expect(settings.openAiTtsModel, 'tts-1');

    final openAi = settings.copyWith(
      streamingTtsProfile: StreamingTtsProfile.openAiCompatible,
    );
    expect(openAi.streamingTtsUrl, isEmpty);
    expect(openAi.streamingTtsVoice, 'alloy');
    expect(openAi.streamingTtsModel, 'tts-1');
  });

  test('legacy OpenAI prefs without profile are inferred as OpenAI', () async {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'es',
      'voice_streaming_tts_url': 'https://voice.example.com/v1',
      'voice_streaming_tts_voice': 'nova',
      'voice_streaming_tts_model': 'gpt-4o-mini-tts',
    });
    final prefs = await SharedPreferences.getInstance();

    final settings = VoiceSettings.load(prefs);

    expect(settings.openAiTtsUrl, 'https://voice.example.com/v1');
    expect(settings.openAiTtsVoice, 'nova');
    expect(settings.openAiTtsModel, 'gpt-4o-mini-tts');
    expect(settings.kokoroTtsUrl, isEmpty);
    expect(settings.kokoroTtsVoice, 'em_santa');
    expect(settings.kokoroTtsModel, 'kokoro');
  });

  test(
    'Kokoro -> OpenAI -> Kokoro keeps independent round-trip values',
    () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'es'});
      final prefs = await SharedPreferences.getInstance();
      final kokoro = const VoiceSettings().copyWith(
        ttsEngine: TtsEngineKind.streaming,
        streamingTtsProfile: StreamingTtsProfile.kokoro,
        streamingTtsUrl: 'http://192.168.1.20:8880/v1',
        streamingTtsVoice: 'ef_dora',
        streamingTtsModel: 'kokoro',
      );
      final openAi = kokoro.copyWith(
        streamingTtsProfile: StreamingTtsProfile.openAiCompatible,
        streamingTtsUrl: 'https://voice.example.com/v1',
        streamingTtsVoice: 'nova',
        streamingTtsModel: 'gpt-4o-mini-tts',
      );

      expect(openAi.kokoroTtsUrl, 'http://192.168.1.20:8880/v1');
      expect(openAi.openAiTtsUrl, 'https://voice.example.com/v1');
      final backToKokoro = openAi.copyWith(
        streamingTtsProfile: StreamingTtsProfile.kokoro,
      );
      expect(backToKokoro.streamingTtsUrl, 'http://192.168.1.20:8880/v1');
      expect(backToKokoro.streamingTtsVoice, 'ef_dora');
      expect(backToKokoro.streamingTtsModel, 'kokoro');

      await openAi.save(prefs);
      final reloaded = VoiceSettings.load(prefs);
      expect(
        reloaded.streamingTtsProfile,
        StreamingTtsProfile.openAiCompatible,
      );
      expect(reloaded.streamingTtsUrl, 'https://voice.example.com/v1');
      expect(reloaded.streamingTtsVoice, 'nova');
      expect(reloaded.streamingTtsModel, 'gpt-4o-mini-tts');
      expect(reloaded.kokoroTtsUrl, 'http://192.168.1.20:8880/v1');
      expect(reloaded.kokoroTtsVoice, 'ef_dora');
    },
  );

  test(
    'legacy token migrates only to the profile active in old prefs',
    () async {
      final secureStore = <String, String>{
        'app_secret_streaming_tts_token': 'legacy-openai-token',
      };
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final args = call.arguments as Map? ?? const {};
              final key = args['key'] as String?;
              switch (call.method) {
                case 'read':
                  return secureStore[key];
                case 'write':
                  secureStore[key!] = args['value'] as String;
                case 'delete':
                  secureStore.remove(key);
              }
              return null;
            },
          );
      addTearDown(
        () => TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(
                'plugins.it_nomads.com/flutter_secure_storage',
              ),
              null,
            ),
      );
      SharedPreferences.setMockInitialValues({
        'voice_streaming_tts_profile': 'openai_compatible',
      });
      final prefs = await SharedPreferences.getInstance();
      final voice = VoiceService(prefs, SecureStorage());

      expect(
        await voice.streamingTtsToken(
          profile: StreamingTtsProfile.openAiCompatible,
        ),
        'legacy-openai-token',
      );
      expect(
        await voice.streamingTtsToken(profile: StreamingTtsProfile.kokoro),
        isNull,
      );
      await voice.setStreamingTtsToken(
        'kokoro-token',
        profile: StreamingTtsProfile.kokoro,
      );
      expect(
        await voice.streamingTtsToken(profile: StreamingTtsProfile.kokoro),
        'kokoro-token',
      );
      expect(
        await voice.streamingTtsToken(
          profile: StreamingTtsProfile.openAiCompatible,
        ),
        'legacy-openai-token',
      );
    },
  );
}
