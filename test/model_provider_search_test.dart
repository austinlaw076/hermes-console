import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/model_provider.dart';

void main() {
  ModelProvider provider(String slug, String name, List<String> models) =>
      ModelProvider(
        slug: slug,
        name: name,
        isCurrent: false,
        authenticated: true,
        authType: '',
        oauthProviderId: '',
        keyEnv: '',
        warning: '',
        models: models,
      );

  final providers = [
    provider('nous', 'Nous Research', ['hermes-4-70b', 'qwen3-coder']),
    provider('openai-codex', 'OpenAI Codex', ['gpt-5.5', 'gpt-5.4-mini']),
    provider('local', 'Servidor local', ['llama3.3']),
  ];

  test('la consulta vacía conserva el catálogo y su orden curado', () {
    final filtered = filterModelProviders(providers, '   ');

    expect(identical(filtered, providers), isTrue);
    expect(filtered.map((provider) => provider.slug), [
      'nous',
      'openai-codex',
      'local',
    ]);
  });

  test('filtra por id de modelo sin reordenar proveedores ni modelos', () {
    final filtered = filterModelProviders(providers, '  GPT-5  ');

    expect(filtered, hasLength(1));
    expect(filtered.single.slug, 'openai-codex');
    expect(filtered.single.models, ['gpt-5.5', 'gpt-5.4-mini']);
  });

  test('una coincidencia de nombre o slug conserva todos sus modelos', () {
    final byName = filterModelProviders(providers, 'research');
    final bySlug = filterModelProviders(providers, 'codex');

    expect(byName.single.slug, 'nous');
    expect(byName.single.models, ['hermes-4-70b', 'qwen3-coder']);
    expect(bySlug.single.slug, 'openai-codex');
    expect(bySlug.single.models, ['gpt-5.5', 'gpt-5.4-mini']);
  });

  test('una consulta sin coincidencias devuelve un resultado vacío', () {
    expect(filterModelProviders(providers, 'modelo-inexistente'), isEmpty);
  });
}
