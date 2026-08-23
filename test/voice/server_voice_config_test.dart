import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/server_voice_config.dart';

void main() {
  group('sanitizeHermesServerVoiceConfig', () {
    test('conserva solo voz publicada y descriptores seguros', () {
      final sanitized = sanitizeHermesServerVoiceConfig(
        {
          'gateway': {'api_key': 'gateway-secret'},
          'stt': {
            'provider': 'local',
            'local': {
              'model': 'whisper-small',
              'language': 'es',
              'api_key': 'stt-secret',
              'temperature': 0.1,
            },
          },
          'tts': {
            'provider': 'openai',
            'openai': {
              'model': 'gpt-4o-mini-tts',
              'voice': 'alloy',
              'api_key': 'tts-secret',
              'speed': 1.1,
            },
            'streaming': {'provider': 'openai'},
          },
        },
        {
          'fields': {
            'stt.local.temperature': {'type': 'number'},
            'stt.local.api_key': {'type': 'password'},
            'tts.openai.speed': {'type': 'number'},
            'tts.openai.api_key': {'secret': true},
            'gateway.api_key': {'type': 'string'},
          },
        },
      );

      expect(sanitized, {
        'stt': {
          'provider': 'local',
          'local': {
            'model': 'whisper-small',
            'language': 'es',
            'temperature': 0.1,
          },
        },
        'tts': {
          'provider': 'openai',
          'openai': {
            'model': 'gpt-4o-mini-tts',
            'voice': 'alloy',
            'speed': 1.1,
          },
          'streaming': {'provider': 'openai'},
        },
      });
      expect(sanitized.toString(), isNot(contains('secret')));
      expect(sanitized, isNot(containsPair('gateway', anything)));
    });

    test('acepta config y schema envueltos sin devolver mapas ajenos', () {
      final source = {
        'config': {
          'tts': {
            'provider': 'edge',
            'edge': {'voice': 'es-ES-ElviraNeural', 'rate': '+5%'},
          },
        },
      };
      final sanitized = sanitizeHermesServerVoiceConfig(source, {
        'schema': {
          'properties': {
            'tts': {
              'properties': {
                'provider': {'type': 'string'},
                'edge': {
                  'properties': {
                    'rate': {'type': 'string'},
                  },
                },
              },
            },
          },
        },
      });

      expect((sanitized['tts'] as Map)['edge'], {
        'voice': 'es-ES-ElviraNeural',
        'rate': '+5%',
      });
      ((source['config'] as Map)['tts'] as Map)['provider'] = 'changed';
      expect((sanitized['tts'] as Map)['provider'], 'edge');
    });

    test('la firma TTS es estable y cambia con voz o streaming', () {
      final first = {
        'tts': {
          'provider': 'openai',
          'openai': {'voice': 'alloy', 'model': 'tts-1'},
          'streaming': {'provider': 'openai'},
        },
      };
      final reordered = {
        'tts': {
          'streaming': {'provider': 'openai'},
          'openai': {'model': 'tts-1', 'voice': 'alloy'},
          'provider': 'openai',
        },
      };
      final changed = {
        'tts': {
          'provider': 'openai',
          'openai': {'voice': 'nova', 'model': 'tts-1'},
          'streaming': {'provider': 'openai'},
        },
      };

      expect(
        hermesServerTtsConfigurationSignature(first),
        hermesServerTtsConfigurationSignature(reordered),
      );
      expect(
        hermesServerTtsConfigurationSignature(first),
        isNot(hermesServerTtsConfigurationSignature(changed)),
      );
    });
  });

  group('HermesServerVoiceSummary', () {
    test('lee Edge y Whisper local sin anunciar PCM', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'stt': {
          'provider': 'local',
          'local': {'model': 'whisper-small', 'language': 'es'},
        },
        'tts': {
          'provider': 'edge',
          'edge': {'model': 'edge-default', 'voice': 'es-ES-ElviraNeural'},
        },
      });

      expect(summary.sttProvider, 'local');
      expect(summary.sttModel, 'whisper-small');
      expect(summary.sttLanguage, 'es');
      expect(summary.ttsProvider, 'edge');
      expect(summary.ttsModel, 'edge-default');
      expect(summary.ttsVoice, 'es-ES-ElviraNeural');
      expect(summary.delivery, HermesServerSpeechDelivery.phraseFallback);
    });

    test('infiere Whisper local y respeta su idioma si provider se omite', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'stt': {
          'language': 'en',
          'local': {'model': 'base', 'language': 'es'},
        },
      });

      expect(summary.sttProvider, 'local');
      expect(summary.sttModel, 'base');
      expect(summary.sttLanguage, 'es');
      expect(
        hermesServerSttLanguageMismatch(
          serverLanguage: summary.sttLanguage,
          appLanguage: 'es',
        ),
        isFalse,
      );
    });

    test('respeta model_id y voice_id de ElevenLabs', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'elevenlabs',
          'elevenlabs': {
            'model_id': 'eleven_flash_v2_5',
            'voice_id': 'voice-123',
          },
        },
      });

      expect(summary.ttsModel, 'eleven_flash_v2_5');
      expect(summary.ttsVoice, 'voice-123');
      expect(summary.delivery, HermesServerSpeechDelivery.checkWhenSpeaking);
    });

    test('lee un proveedor TTS command desde providers', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'voxcpm',
          'providers': {
            'voxcpm': {
              'type': 'command',
              'command': 'voxcpm --in {input_path} --out {output_path}',
              'model': 'voxcpm-1.5',
              'voice': 'voz-local',
            },
          },
        },
      });

      expect(summary.ttsProvider, 'voxcpm');
      expect(summary.ttsModel, 'voxcpm-1.5');
      expect(summary.ttsVoice, 'voz-local');
    });

    test('lee un proveedor STT command desde providers', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'stt': {
          'provider': 'parakeet',
          'providers': {
            'parakeet': {
              'type': 'command',
              'command': 'parakeet --in {input_path} --out {output_path}',
              'model': 'nvidia/parakeet-tdt-0.6b-v2',
              'language': 'es',
            },
          },
        },
      });

      expect(summary.sttProvider, 'parakeet');
      expect(summary.sttModel, 'nvidia/parakeet-tdt-0.6b-v2');
      expect(summary.sttLanguage, 'es');
    });

    test('mantiene la configuración directa de proveedores integrados', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'edge',
          'edge': {'voice': 'es-ES-ElviraNeural'},
          'providers': {
            'edge': {
              'type': 'command',
              'command': 'otro-motor {input_path}',
              'voice': 'incorrecta',
            },
          },
        },
      });

      expect(summary.ttsVoice, 'es-ES-ElviraNeural');
    });

    for (final provider in const ['xai', 'minimax', 'mistral']) {
      test('lee voice_id de $provider', () {
        final summary = HermesServerVoiceSummary.fromConfig({
          'tts': {
            'provider': provider,
            provider: {'voice_id': '$provider-voice'},
          },
        });

        expect(summary.ttsVoice, '$provider-voice');
      });
    }

    test('solo anuncia PCM después de observarlo', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'openai',
          'openai': {'voice': 'alloy'},
        },
      }, pcmStreamingObserved: true);

      expect(summary.delivery, HermesServerSpeechDelivery.pcmStreaming);
    });

    test('un proveedor por frases nunca hereda evidencia PCM anterior', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'edge',
          'edge': {'voice': 'es-ES-ElviraNeural'},
        },
      }, pcmStreamingObserved: true);

      expect(summary.delivery, HermesServerSpeechDelivery.phraseFallback);
    });

    test('streaming auto queda pendiente de comprobar al hablar', () {
      final summary = HermesServerVoiceSummary.fromConfig({
        'tts': {
          'provider': 'edge',
          'edge': {'voice': 'es-ES-ElviraNeural'},
          'streaming': {'provider': 'auto'},
        },
      });

      expect(summary.delivery, HermesServerSpeechDelivery.checkWhenSpeaking);
    });
  });

  group('hermesServerSttLanguageMismatch', () {
    test('detecta servidor inglés con app española', () {
      expect(
        hermesServerSttLanguageMismatch(
          serverLanguage: 'en-US',
          appLanguage: 'es',
        ),
        isTrue,
      );
    });

    test('acepta locale equivalente y detección automática', () {
      expect(
        hermesServerSttLanguageMismatch(
          serverLanguage: 'es_ES',
          appLanguage: 'es',
        ),
        isFalse,
      );
      expect(
        hermesServerSttLanguageMismatch(
          serverLanguage: 'auto',
          appLanguage: 'es',
        ),
        isFalse,
      );
      expect(
        hermesServerSttLanguageMismatch(
          serverLanguage: null,
          appLanguage: 'es',
        ),
        isFalse,
      );
    });
  });

  group('HermesServerVoiceCatalog', () {
    test('lee enum del schema y conserva el proveedor custom actual', () {
      final catalog = HermesServerVoiceCatalog.fromSchema(
        {
          'properties': {
            'stt': {
              'properties': {
                'provider': {
                  'enum': ['local', 'groq'],
                },
              },
            },
            'tts': {
              'properties': {
                'provider': {
                  'enum': ['edge', 'elevenlabs'],
                },
              },
            },
          },
        },
        currentSttProvider: 'custom_stt',
        currentTtsProvider: 'edge',
      );

      expect(catalog.sttProviders, ['local', 'groq', 'custom_stt']);
      expect(catalog.ttsProviders, ['edge', 'elevenlabs']);
      expect(catalog.published, isTrue);
    });

    test('acepta schema envuelto y opciones de formulario', () {
      final catalog = HermesServerVoiceCatalog.fromSchema({
        'schema': {
          'properties': {
            'tts': {
              'properties': {
                'provider': {
                  'options': [
                    {'value': 'edge'},
                    {'id': 'custom'},
                  ],
                },
              },
            },
          },
        },
      });

      expect(catalog.sttProviders, isEmpty);
      expect(catalog.ttsProviders, ['edge', 'custom']);
      expect(catalog.published, isTrue);
    });

    test('lee el registro fields publicado por Hermes Desktop', () {
      final catalog = HermesServerVoiceCatalog.fromSchema({
        'fields': {
          'stt.provider': {
            'options': ['local', 'groq', 'openai'],
          },
          'tts.provider': {
            'options': [
              {'value': 'edge', 'label': 'Edge'},
              {'value': 'gemini', 'label': 'Gemini'},
            ],
          },
        },
      });

      expect(catalog.sttProviders, ['local', 'groq', 'openai']);
      expect(catalog.ttsProviders, ['edge', 'gemini']);
      expect(catalog.published, isTrue);
    });

    test('no presenta el proveedor actual como catálogo publicado', () {
      final catalog = HermesServerVoiceCatalog.fromSchema(
        {'properties': <String, Object?>{}},
        currentSttProvider: 'local',
        currentTtsProvider: 'edge',
      );

      expect(catalog.sttProviders, ['local']);
      expect(catalog.ttsProviders, ['edge']);
      expect(catalog.published, isFalse);
    });
  });
}
