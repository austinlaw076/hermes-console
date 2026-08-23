import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/tts_toolset_config.dart';

void main() {
  test('parses the TTS toolset configuration contract', () {
    final config = HermesTtsToolsetConfig.fromJson({
      'active_provider': 'elevenlabs',
      'providers': [
        {
          'name': 'ElevenLabs',
          'tag': 'cloud',
          'status': 'configured',
          'is_active': true,
          'tts_provider': 'elevenlabs',
          'env_vars': [
            {
              'key': 'ELEVENLABS_API_KEY',
              'label': 'API key',
              'is_set': true,
              'secret': true,
            },
          ],
          'post_setup': 'Restart the voice worker',
        },
      ],
    });

    expect(config.activeProvider, 'elevenlabs');
    expect(config.providers, hasLength(1));
    final provider = config.providers.single;
    expect(provider.name, 'ElevenLabs');
    expect(provider.tag, 'cloud');
    expect(provider.status, 'configured');
    expect(provider.isActive, isTrue);
    expect(provider.ttsProvider, 'elevenlabs');
    expect(provider.envVars, hasLength(1));
    expect(provider.envVars.single.key, 'ELEVENLABS_API_KEY');
    expect(provider.envVars.single.label, 'API key');
    expect(provider.envVars.single.isSet, isTrue);
    expect(provider.envVars.single.secret, isTrue);
    expect(provider.postSetup, 'Restart the voice worker');
  });

  test('preserves unknown fields at every response level', () {
    final payload = <String, dynamic>{
      'active_provider': 'edge',
      'api_revision': 3,
      'capabilities': {'streaming': true},
      'providers': [
        {
          'name': 'Edge',
          'tag': 'built_in',
          'status': 'ready',
          'is_active': true,
          'tts_provider': 'edge',
          'provider_revision': 7,
          'env_vars': [
            {
              'key': 'EDGE_VOICE',
              'label': 'Voice',
              'is_set': false,
              'secret': false,
              'input_hint': 'es-ES-ElviraNeural',
            },
          ],
          'post_setup': [
            'download voices',
            {'optional': true},
          ],
        },
      ],
    };

    final config = HermesTtsToolsetConfig.fromJson(payload);
    expect(config.extraFields['api_revision'], 3);
    expect(config.extraFields['capabilities'], {'streaming': true});
    expect(config.providers.single.extraFields['provider_revision'], 7);
    expect(
      config.providers.single.envVars.single.extraFields['input_hint'],
      'es-ES-ElviraNeural',
    );
    expect(config.toJson(), payload);
  });

  test('ignores malformed records without coercing contract types', () {
    final config = HermesTtsToolsetConfig.fromJson({
      'active_provider': 42,
      'providers': [
        'not a provider',
        {
          'name': 7,
          'is_active': 'yes',
          'env_vars': [
            null,
            {'key': 9, 'is_set': 1, 'secret': 'false'},
          ],
          'post_setup': false,
        },
      ],
    });

    expect(config.activeProvider, isNull);
    expect(config.providers, hasLength(1));
    final provider = config.providers.single;
    expect(provider.name, isNull);
    expect(provider.isActive, isNull);
    expect(provider.envVars, hasLength(1));
    expect(provider.envVars.single.key, isNull);
    expect(provider.envVars.single.isSet, isNull);
    expect(provider.envVars.single.secret, isNull);
    expect(provider.postSetup, isFalse);
  });

  test('unknown collections are immutable inside the parsed model', () {
    final config = HermesTtsToolsetConfig.fromJson({
      'active_provider': 'edge',
      'providers': const [],
      'future': {
        'nested': [1, 2],
      },
    });

    expect(
      () => (config.extraFields['future'] as Map)['new'] = true,
      throwsUnsupportedError,
    );
    expect(
      () => ((config.extraFields['future'] as Map)['nested'] as List).add(3),
      throwsUnsupportedError,
    );
  });
}
