import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/model_provider.dart';

/// El selector del chat filtra proveedores/modelos ocultos leyendo las MISMAS
/// claves que la pantalla de Modelos (`hidden_providers` = slugs,
/// `hidden_models` = "slug/modelId"). Aquí se fija la lógica de filtrado que
/// el chat aplica sobre el catálogo (bug: antes no filtraba nada).
void main() {
  ModelProvider prov(String slug, List<String> models) => ModelProvider(
    slug: slug,
    name: slug,
    isCurrent: false,
    authenticated: true,
    authType: '',
    oauthProviderId: '',
    keyEnv: '',
    warning: '',
    models: models,
  );

  /// Réplica del filtro que aplica _loadModelOptions en chat_screen.
  List<ModelProvider> filter(
    List<ModelProvider> providers,
    Set<String> hiddenProviders,
    Set<String> hiddenModels,
  ) {
    final out = <ModelProvider>[];
    for (final p in providers) {
      if (hiddenProviders.contains(p.slug)) continue;
      final models = p.models.where(
        (m) => !hiddenModels.contains('${p.slug}/$m'),
      );
      out.add(p.copyWith(models: models.toList()));
    }
    return out;
  }

  test('copyWith reemplaza solo los modelos', () {
    final p = prov('openai-codex', ['gpt-5.5', 'gpt-5.4']);
    final c = p.copyWith(models: ['gpt-5.5']);
    expect(c.slug, 'openai-codex');
    expect(c.authenticated, isTrue);
    expect(c.models, ['gpt-5.5']);
  });

  test('proveedor oculto desaparece entero', () {
    final res = filter(
      [
        prov('moa', ['default']),
        prov('openai-codex', ['gpt-5.5']),
      ],
      {'moa'},
      {},
    );
    expect(res.map((p) => p.slug), ['openai-codex']);
  });

  test('modelo oculto se quita por "slug/modelId", no el proveedor', () {
    final res = filter(
      [
        prov('openai-codex', ['gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini']),
      ],
      {},
      {'openai-codex/gpt-5.4'},
    );
    expect(res.single.models, ['gpt-5.5', 'gpt-5.4-mini']);
  });

  test('el formato con barra evita colisiones entre proveedores', () {
    // Ocultar "a/x" no debe afectar a "b/x".
    final res = filter(
      [
        prov('a', ['x']),
        prov('b', ['x']),
      ],
      {},
      {'a/x'},
    );
    expect(res.firstWhere((p) => p.slug == 'a').models, isEmpty);
    expect(res.firstWhere((p) => p.slug == 'b').models, ['x']);
  });

  test('sin ocultos, la lista pasa intacta', () {
    final input = [
      prov('openai-codex', ['gpt-5.5']),
    ];
    final res = filter(input, {}, {});
    expect(res.single.models, ['gpt-5.5']);
  });
}
