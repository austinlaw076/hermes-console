import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/moa_config.dart';

/// Respuesta REAL de GET /api/model/moa en SERVER (Hermes 0.18), como fixture.
const _realGet = {
  'default_preset': 'default',
  'active_preset': '',
  'presets': {
    'default': {
      'reference_models': [
        {'provider': 'openai-codex', 'model': 'gpt-5.5'},
        {'provider': 'openrouter', 'model': 'deepseek/deepseek-v4-pro'},
      ],
      'aggregator': {
        'provider': 'openrouter',
        'model': 'anthropic/claude-opus-4.8',
      },
      'reference_temperature': 0.6,
      'aggregator_temperature': 0.4,
      'max_tokens': 4096,
      'reference_max_tokens': null,
      'fanout': 'per_iteration',
      'enabled': true,
    },
  },
  // Vista aplanada del preset default (el cliente la ignora si hay presets).
  'reference_models': [
    {'provider': 'openai-codex', 'model': 'gpt-5.5'},
    {'provider': 'openrouter', 'model': 'deepseek/deepseek-v4-pro'},
  ],
  'aggregator': {
    'provider': 'openrouter',
    'model': 'anthropic/claude-opus-4.8',
  },
  'reference_temperature': 0.6,
  'aggregator_temperature': 0.4,
  'max_tokens': 4096,
  'reference_max_tokens': null,
  'fanout': 'per_iteration',
  'enabled': true,
};

void main() {
  group('MoaConfig.fromJson — parseo del GET real (spec 029)', () {
    final cfg = MoaConfig.fromJson(Map<String, dynamic>.from(_realGet));

    test('default_preset y presets', () {
      expect(cfg.defaultPreset, 'default');
      expect(cfg.activePreset, '');
      expect(cfg.presets.keys, ['default']);
    });

    test('comité: 2 referencias reales', () {
      final p = cfg.active!;
      expect(p.referenceModels.length, 2);
      expect(p.referenceModels[0].provider, 'openai-codex');
      expect(p.referenceModels[0].model, 'gpt-5.5');
      expect(p.referenceModels[1].model, 'deepseek/deepseek-v4-pro');
    });

    test('agregador y ajustes', () {
      final p = cfg.active!;
      expect(p.aggregator.provider, 'openrouter');
      expect(p.aggregator.model, 'anthropic/claude-opus-4.8');
      expect(p.referenceTemperature, 0.6);
      expect(p.aggregatorTemperature, 0.4);
      expect(p.maxTokens, 4096);
      expect(p.enabled, isTrue);
    });

    test('read-only: reference_max_tokens null y fanout per_iteration', () {
      final p = cfg.active!;
      expect(p.referenceMaxTokens, isNull);
      expect(p.fanout, 'per_iteration');
    });
  });

  group('toJson — forma del PUT', () {
    final cfg = MoaConfig.fromJson(Map<String, dynamic>.from(_realGet));

    test('NO incluye reference_max_tokens ni fanout (read-only)', () {
      final out = jsonEncode(cfg.toJson());
      expect(out.contains('reference_max_tokens'), isFalse);
      expect(out.contains('fanout'), isFalse);
    });

    test('emite la forma con presets y reenvía todos', () {
      final j = cfg.toJson();
      expect(j['presets'], isA<Map>());
      expect((j['presets'] as Map).keys, contains('default'));
      expect(j['default_preset'], 'default');
    });

    test('round-trip fromJson→toJson→fromJson preserva campos editables', () {
      final j = cfg.toJson();
      final back = MoaConfig.fromJson(j);
      final a = cfg.active!;
      final b = back.active!;
      expect(
        b.referenceModels.map((r) => '${r.provider}/${r.model}'),
        a.referenceModels.map((r) => '${r.provider}/${r.model}'),
      );
      expect(b.aggregator.model, a.aggregator.model);
      expect(b.referenceTemperature, a.referenceTemperature);
      expect(b.aggregatorTemperature, a.aggregatorTemperature);
      expect(b.maxTokens, a.maxTokens);
      expect(b.enabled, a.enabled);
    });
  });

  group('guardado atómico — presets ajenos preservados', () {
    test('withPreset conserva los demás presets', () {
      final base = MoaConfig.fromJson({
        'default_preset': 'default',
        'active_preset': '',
        'presets': {
          'default': (_realGet['presets'] as Map)['default'],
          'rapido': {
            'reference_models': [
              {'provider': 'openai-codex', 'model': 'gpt-5.4-mini'},
            ],
            'aggregator': {'provider': 'openai-codex', 'model': 'gpt-5.4'},
            'max_tokens': 2048,
            'enabled': true,
          },
        },
      });
      final edited = base.active!.copyWith(maxTokens: 8192);
      final next = base.withPreset('default', edited);
      // El preset ajeno "rapido" sigue intacto en el toJson.
      final j = next.toJson();
      final presets = j['presets'] as Map;
      expect(presets.keys, containsAll(['default', 'rapido']));
      expect((presets['default'] as Map)['max_tokens'], 8192);
      expect((presets['rapido'] as Map)['max_tokens'], 2048);
    });
  });

  group('compat — forma vieja aplanada sin presets', () {
    test('el nivel raíz se toma como preset default', () {
      final cfg = MoaConfig.fromJson({
        'reference_models': [
          {'provider': 'x', 'model': 'y'},
        ],
        'aggregator': {'provider': 'a', 'model': 'b'},
        'max_tokens': 4096,
        'enabled': true,
      });
      expect(cfg.defaultPreset, 'default');
      expect(cfg.active!.referenceModels.single.provider, 'x');
    });
  });
}
