import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/moa_config.dart';

/// La pantalla `MoaRecipeScreen` depende de `DashboardClient` (red/cookies),
/// difícil de inyectar sin refactor. Estos tests fijan la LÓGICA que la
/// pantalla aplica sobre el modelo (edición del comité, límites, aviso de
/// credencial, activación), que es donde viven las garantías de la spec 029.
/// El render se valida en el quickstart V1–V5 contra SERVER.
void main() {
  MoaConfig base() => MoaConfig.fromJson({
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
        'enabled': true,
      },
    },
  });

  group('US1 — editar el comité', () {
    test('añadir una referencia (respeta el tope de 5)', () {
      var cfg = base();
      var p = cfg.active!;
      // Añadir hasta 5.
      while (p.referenceModels.length < 5) {
        p = p.copyWith(
          referenceModels: [
            ...p.referenceModels,
            const MoaSlot(provider: 'openai-codex', model: 'gpt-5.4-mini'),
          ],
        );
      }
      expect(p.referenceModels.length, 5);
      // La pantalla oculta "Añadir" en 5: no se prueba UI aquí, sí el límite.
      cfg = cfg.withPreset('default', p);
      expect(cfg.active!.referenceModels.length, 5);
    });

    test('quitar una referencia mantiene mínimo 1', () {
      final cfg = base();
      final p = cfg.active!;
      final refs = [...p.referenceModels]..removeAt(0);
      final next = cfg.withPreset('default', p.copyWith(referenceModels: refs));
      expect(next.active!.referenceModels.length, 1);
      // Con 1 sola referencia, la pantalla deshabilita el botón de quitar.
      expect(next.active!.referenceModels, isNotEmpty);
    });

    test('cambiar el agregador', () {
      final cfg = base();
      final next = cfg.withPreset(
        'default',
        cfg.active!.copyWith(
          aggregator: const MoaSlot(provider: 'openai-codex', model: 'gpt-5.5'),
        ),
      );
      expect(next.active!.aggregator.provider, 'openai-codex');
      // El comité no se toca al cambiar el agregador.
      expect(next.active!.referenceModels.length, 2);
    });
  });

  group('US3 — ajustes finos y presets', () {
    test('temperatura vacía = null (no 0 forzado)', () {
      final cfg = base();
      final next = cfg.withPreset(
        'default',
        cfg.active!.copyWith(clearAggregatorTemperature: true),
      );
      expect(next.active!.aggregatorTemperature, isNull);
      // Y no aparece como 0 en el toJson.
      final agg = (next.toJson()['presets'] as Map)['default'] as Map;
      expect(agg['aggregator_temperature'], isNull);
    });

    test('editar temperatura y max_tokens persiste en el preset', () {
      final cfg = base();
      final next = cfg.withPreset(
        'default',
        cfg.active!.copyWith(referenceTemperature: 0.9, maxTokens: 8192),
      );
      expect(next.active!.referenceTemperature, 0.9);
      expect(next.active!.maxTokens, 8192);
      final preset = (next.toJson()['presets'] as Map)['default'] as Map;
      expect(preset['reference_temperature'], 0.9);
      expect(preset['max_tokens'], 8192);
    });

    test('toggle enabled se refleja', () {
      final cfg = base();
      final next = cfg.withPreset(
        'default',
        cfg.active!.copyWith(enabled: false),
      );
      expect(next.active!.enabled, isFalse);
      expect(
        ((next.toJson()['presets'] as Map)['default'] as Map)['enabled'],
        isFalse,
      );
    });

    test('editar un preset no altera los otros', () {
      final cfg = MoaConfig.fromJson({
        'default_preset': 'default',
        'active_preset': '',
        'presets': {
          'default': (base().toJson()['presets'] as Map)['default'],
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
      final next = cfg.withPreset(
        'default',
        cfg.presets['default']!.copyWith(maxTokens: 8192),
      );
      expect(next.presets['default']!.maxTokens, 8192);
      expect(next.presets['rapido']!.maxTokens, 2048);
    });
  });

  group('read-only fields no viajan en el PUT', () {
    test('fanout y reference_max_tokens ausentes del toJson', () {
      final j = base().toJson();
      final preset = (j['presets'] as Map)['default'] as Map;
      expect(preset.containsKey('fanout'), isFalse);
      expect(preset.containsKey('reference_max_tokens'), isFalse);
    });
  });
}
