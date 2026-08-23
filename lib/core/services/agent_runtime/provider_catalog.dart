// Catálogo de proveedores de modelos soportados por Hermes Agent.
//
// Fuente: docs oficiales `user-guide/configuration`. Es la ÚNICA fuente de
// verdad compartida por las pantallas que configuran el agente local
// (LocalInstanceControlScreen y el Camino B de LocalInstallScreen), para que no
// diverjan. El `id` es exactamente lo que se escribe en `config.yaml`
// (`model.provider`); `AgentRuntimeConsts.envVarFor` lo mapea a su variable de
// entorno en `.env`.

/// Tipo de autenticación de un provider.
enum ProviderAuth {
  /// Necesita una API key escrita en `~/.hermes/.env`.
  apiKey,

  /// Autenticación por navegador (`hermes auth` / `hermes model set codex`).
  /// No se escribe ninguna API key.
  oauth,

  /// Provider local (Ollama): `base_url`, sin API key.
  local,
}

/// Una opción de provider para la UI.
class ProviderOption {
  /// Identificador de `config.yaml` (`model.provider`).
  final String id;

  /// Nombre legible para la UI.
  final String label;

  /// Descripción corta (modelos típicos / naturaleza del provider).
  final String blurb;

  /// Tipo de autenticación.
  final ProviderAuth auth;

  /// Sugerencias de modelo (para el campo / placeholder). Vacío = texto libre.
  final List<String> models;

  const ProviderOption({
    required this.id,
    required this.label,
    required this.blurb,
    required this.auth,
    this.models = const [],
  });

  /// Pista para el campo de modelo.
  String get modelHint =>
      models.isEmpty ? 'nombre del modelo' : 'ej. ${models.take(3).join(', ')}';
}

class ProviderCatalog {
  ProviderCatalog._();

  /// Providers con API key.
  static const List<ProviderOption> apiKey = [
    ProviderOption(
      id: 'openai',
      label: 'OpenAI',
      blurb: 'GPT-4o, o3…',
      auth: ProviderAuth.apiKey,
      models: ['gpt-4o', 'gpt-4o-mini', 'o3'],
    ),
    ProviderOption(
      id: 'anthropic',
      label: 'Anthropic',
      blurb: 'Claude 3.5, 4…',
      auth: ProviderAuth.apiKey,
      models: ['claude-opus-4-8', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001'],
    ),
    ProviderOption(
      id: 'openrouter',
      label: 'OpenRouter',
      blurb: 'Access to multiple models',
      auth: ProviderAuth.apiKey,
      models: ['openai/gpt-4o', 'anthropic/claude-sonnet-4-6'],
    ),
    ProviderOption(
      id: 'gemini',
      label: 'Google Gemini',
      blurb: 'Gemini 2.0, Flash…',
      auth: ProviderAuth.apiKey,
      models: ['gemini-2.0-flash', 'gemini-2.0-pro'],
    ),
    ProviderOption(
      id: 'deepseek',
      label: 'DeepSeek',
      blurb: 'DeepSeek-V3, R1…',
      auth: ProviderAuth.apiKey,
      models: ['deepseek-chat', 'deepseek-reasoner'],
    ),
    ProviderOption(
      id: 'mistral',
      label: 'Mistral',
      blurb: 'Mistral Large, Codestral…',
      auth: ProviderAuth.apiKey,
      models: ['mistral-large-latest', 'codestral-latest'],
    ),
    ProviderOption(
      id: 'minimax',
      label: 'MiniMax',
      blurb: 'MiniMax-01…',
      auth: ProviderAuth.apiKey,
      models: ['MiniMax-Text-01'],
    ),
    ProviderOption(
      id: 'xai',
      label: 'xAI Grok',
      blurb: 'Grok-2…',
      auth: ProviderAuth.apiKey,
      models: ['grok-2-latest'],
    ),
    ProviderOption(
      id: 'kimi-coding',
      label: 'Kimi',
      blurb: 'Kimi k1.5…',
      auth: ProviderAuth.apiKey,
      models: ['kimi-k1.5'],
    ),
    ProviderOption(
      id: 'huggingface',
      label: 'HuggingFace',
      blurb: 'Inference API',
      auth: ProviderAuth.apiKey,
    ),
    ProviderOption(
      id: 'azure-foundry',
      label: 'Azure AI Foundry',
      blurb: 'Azure OpenAI…',
      auth: ProviderAuth.apiKey,
    ),
  ];

  /// Providers OAuth (autenticación por navegador, sin API key).
  ///
  /// Solo los que Hermes soporta de verdad vía `hermes auth add ID --type oauth`
  /// (verificado en vivo). Se excluye `qwen-oauth`: crashea en el propio CLI de
  /// Hermes (traceback de Python), no es un fallo de la Consola.
  static const List<ProviderOption> oauth = [
    ProviderOption(
      id: 'nous',
      label: 'Nous Portal',
      blurb: 'OAuth — cubre modelo + herramientas',
      auth: ProviderAuth.oauth,
    ),
    ProviderOption(
      id: 'codex',
      label: 'ChatGPT / Codex',
      blurb: 'OAuth — cuenta OpenAI',
      auth: ProviderAuth.oauth,
    ),
    ProviderOption(
      id: 'minimax-oauth',
      label: 'MiniMax (OAuth)',
      blurb: 'OAuth — sin API key',
      auth: ProviderAuth.oauth,
    ),
    ProviderOption(
      id: 'xai-oauth',
      label: 'xAI Grok (OAuth)',
      blurb: 'OAuth — sin API key',
      auth: ProviderAuth.oauth,
    ),
  ];

  /// Provider local (Ollama). Se escribe como `custom` con `base_url`.
  static const List<ProviderOption> local = [
    ProviderOption(
      id: 'ollama',
      label: 'Ollama (local)',
      blurb: 'Modelos descargados localmente',
      auth: ProviderAuth.local,
    ),
  ];

  /// Todas las opciones en orden de presentación (API key → OAuth → local).
  static List<ProviderOption> get all => [...apiKey, ...oauth, ...local];

  /// Busca una opción por su id (o null).
  static ProviderOption? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// ¿Es un provider OAuth?
  static bool isOAuth(String id) => oauth.any((p) => p.id == id);

  /// ¿Es el provider local (Ollama)?
  static bool isLocal(String id) => local.any((p) => p.id == id);
}

// ── Modelos de Ollama descargables ───────────────────────────────────────────

/// Un modelo de Ollama del catálogo curado que la app puede descargar mediante
/// `ollama pull <tag>` en Termux. Compartido por la pantalla de instalación
/// (Camino A) y el panel de control local para no divergir.
class DownloadableModel {
  /// Tag exacto para `ollama pull` (lo que también aparece en `/api/tags`).
  final String tag;

  /// Nombre legible para la UI.
  final String name;

  /// RAM recomendada para ejecutarlo con holgura (GB).
  final double ramGb;

  /// Tamaño aproximado de la descarga (GB).
  final double sizeGb;

  const DownloadableModel({
    required this.tag,
    required this.name,
    required this.ramGb,
    required this.sizeGb,
  });
}

/// Catálogo curado de modelos locales descargables, ordenado de menor a mayor
/// exigencia de RAM.
class OllamaModelCatalog {
  OllamaModelCatalog._();

  // Tamaños = descarga real del tag por defecto (q4) de la librería de Ollama;
  // RAM = recomendada para ejecutarlo con holgura. Verificado en ollama.com.
  static const List<DownloadableModel> all = [
    DownloadableModel(tag: 'qwen2.5:0.5b', name: 'Qwen 2.5 0.5B', ramGb: 1.0, sizeGb: 0.4),
    DownloadableModel(tag: 'gemma3:1b', name: 'Gemma 3 1B', ramGb: 2.0, sizeGb: 0.8),
    DownloadableModel(tag: 'llama3.2:1b', name: 'Llama 3.2 1B', ramGb: 2.0, sizeGb: 0.8),
    DownloadableModel(tag: 'qwen2.5:1.5b', name: 'Qwen 2.5 1.5B', ramGb: 2.0, sizeGb: 1.0),
    DownloadableModel(tag: 'llama3.2:3b', name: 'Llama 3.2 3B', ramGb: 4.0, sizeGb: 2.0),
    DownloadableModel(tag: 'phi3:mini', name: 'Phi-3 Mini 3.8B', ramGb: 4.0, sizeGb: 2.3),
    DownloadableModel(tag: 'gemma3:4b', name: 'Gemma 3 4B', ramGb: 6.0, sizeGb: 3.3),
    DownloadableModel(tag: 'mistral:7b', name: 'Mistral 7B', ramGb: 8.0, sizeGb: 4.1),
    DownloadableModel(tag: 'llama3.1:8b', name: 'Llama 3.1 8B', ramGb: 8.0, sizeGb: 4.7),
    DownloadableModel(tag: 'gemma3n:e2b', name: 'Gemma 3n E2B', ramGb: 8.0, sizeGb: 5.6),
    DownloadableModel(tag: 'gemma4:e2b', name: 'Gemma 4 E2B', ramGb: 10.0, sizeGb: 7.2),
    DownloadableModel(tag: 'gemma3n:e4b', name: 'Gemma 3n E4B', ramGb: 10.0, sizeGb: 7.5),
    DownloadableModel(tag: 'gemma4:12b', name: 'Gemma 4 12B', ramGb: 12.0, sizeGb: 7.6),
    DownloadableModel(tag: 'gemma3:12b', name: 'Gemma 3 12B', ramGb: 12.0, sizeGb: 8.1),
    DownloadableModel(tag: 'gemma4:e4b', name: 'Gemma 4 E4B', ramGb: 14.0, sizeGb: 9.6),
  ];

  /// Modelos cuya RAM recomendada cabe en el dispositivo (umbral: 60 % de la
  /// RAM total). Con RAM desconocida (<=0) devuelve todo el catálogo.
  static List<DownloadableModel> compatible(double totalRamGb) {
    if (totalRamGb <= 0) return all;
    final threshold = totalRamGb * 0.6;
    return all.where((m) => m.ramGb <= threshold).toList();
  }
}
