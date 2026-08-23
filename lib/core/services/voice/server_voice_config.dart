import 'dart:convert';

/// Resumen no secreto de la configuración de voz efectiva de Hermes Agent.
///
/// Hermes no usa el mismo nombre de campo para todos los proveedores
/// (`voice`/`voice_id`, `model`/`model_id`). Centralizarlo evita que la UI
/// muestre una configuración vacía cuando el servidor sí está listo.
/// Builds a new voice-only snapshot from Hermes' config response.
///
/// Only non-secret STT/TTS paths published by the server schema are copied.
/// A deliberately small set of harmless descriptors is retained so the UI can
/// still explain the effective provider on older Hermes versions whose schema
/// does not publish every provider field. The source map is never returned or
/// mutated.
Map<String, dynamic> sanitizeHermesServerVoiceConfig(
  Map<String, dynamic> response,
  Map<String, dynamic> schema,
) {
  final nested = response['config'];
  final source = Map<String, dynamic>.from(nested is Map ? nested : response);
  final paths = <String>{
    'stt.provider',
    'tts.provider',
    'tts.streaming.provider',
  };

  final wrappedSchema = _record(schema['schema']);
  final schemaRoot = wrappedSchema.isEmpty ? schema : wrappedSchema;
  final fields = schemaRoot['fields'];
  if (fields is Map) {
    for (final entry in fields.entries) {
      final path = entry.key.toString();
      if (_isVoicePath(path) && !_isSecretSchemaField(path, entry.value)) {
        paths.add(path);
      }
    }
  }
  _collectPublishedVoicePaths(schemaRoot, const [], paths);

  for (final section in const ['stt', 'tts']) {
    final provider = _text(_readPath(source, '$section.provider'));
    if (provider == null || _looksSecret(provider)) continue;
    for (final field in const [
      'model',
      'model_id',
      'voice',
      'voice_id',
      'language',
      'language_code',
    ]) {
      paths
        ..add('$section.$provider.$field')
        ..add('$section.providers.$provider.$field');
    }
  }

  final safe = <String, dynamic>{};
  for (final path in paths) {
    if (!_isVoicePath(path) || _looksSecret(path)) continue;
    final value = _safeLeaf(_readPath(source, path));
    if (value != null) _writePath(safe, path, value);
  }
  return safe;
}

/// Stable signature for the non-secret TTS configuration visible to the app.
/// PCM evidence is bound to this value so changing provider, voice, model or a
/// published streaming option returns the UI to "check when speaking".
String hermesServerTtsConfigurationSignature(Map<String, dynamic> config) {
  final tts = _record(config['tts']);
  return jsonEncode(_canonicalValue(tts));
}

class HermesServerVoiceSummary {
  const HermesServerVoiceSummary({
    required this.sttProvider,
    required this.sttModel,
    required this.sttLanguage,
    required this.ttsProvider,
    required this.ttsModel,
    required this.ttsVoice,
    required this.delivery,
  });

  final String? sttProvider;
  final String? sttModel;
  final String? sttLanguage;
  final String? ttsProvider;
  final String? ttsModel;
  final String? ttsVoice;
  final HermesServerSpeechDelivery delivery;

  factory HermesServerVoiceSummary.fromConfig(
    Map<String, dynamic> config, {
    bool pcmStreamingObserved = false,
  }) {
    final stt = _record(config['stt']);
    final tts = _record(config['tts']);
    // Hermes omits default values from config.yaml. When an STT section is
    // present without an explicit provider, the runtime still resolves it as
    // Local Whisper. Inferring that effective default is important because
    // stt.local.language takes precedence over the global stt.language.
    final sttProvider =
        _text(stt['provider']) ?? (stt.isEmpty ? null : 'local');
    final ttsProvider = _text(tts['provider']);
    final sttConfig = _providerConfig(stt, sttProvider);
    final ttsConfig = _providerConfig(tts, ttsProvider);

    final streaming = _record(tts['streaming']);
    final streamingOverride = _text(streaming['provider']);
    final deliveryProvider = switch (streamingOverride) {
      null || 'default' => ttsProvider,
      'auto' => null,
      final provider => provider,
    };

    return HermesServerVoiceSummary(
      sttProvider: sttProvider,
      sttModel: _providerModel(sttProvider, sttConfig),
      sttLanguage:
          _text(sttConfig['language']) ??
          _text(sttConfig['language_code']) ??
          _text(stt['language']),
      ttsProvider: ttsProvider,
      ttsModel: _providerModel(ttsProvider, ttsConfig),
      ttsVoice: _providerVoice(ttsProvider, ttsConfig),
      delivery: _deliveryFor(
        deliveryProvider,
        pcmStreamingObserved: pcmStreamingObserved,
      ),
    );
  }

  static Map<String, dynamic> _record(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static Map<String, dynamic> _providerConfig(
    Map<String, dynamic> section,
    String? provider,
  ) {
    if (provider == null) return const <String, dynamic>{};
    final direct = _record(section[provider]);
    if (direct.isNotEmpty) return direct;
    return _record(_record(section['providers'])[provider]);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _providerModel(
    String? provider,
    Map<String, dynamic> config,
  ) => _text(provider == 'elevenlabs' ? config['model_id'] : config['model']);

  static String? _providerVoice(
    String? provider,
    Map<String, dynamic> config,
  ) => _text(
    const {'elevenlabs', 'xai', 'minimax', 'mistral'}.contains(provider)
        ? config['voice_id']
        : config['voice'],
  );

  static HermesServerSpeechDelivery _deliveryFor(
    String? provider, {
    required bool pcmStreamingObserved,
  }) {
    if (const {
      'edge',
      'piper',
      'kittentts',
      'neutts',
      'mistral',
      'minimax',
      'deepinfra',
    }.contains(provider)) {
      return HermesServerSpeechDelivery.phraseFallback;
    }
    if (pcmStreamingObserved) return HermesServerSpeechDelivery.pcmStreaming;
    return HermesServerSpeechDelivery.checkWhenSpeaking;
  }
}

/// Detecta cuando Hermes fuerza un idioma distinto al idioma efectivo de la
/// app. `auto` (o un valor vacío) no es una incompatibilidad: en esos casos el
/// proveedor conserva su detección automática.
bool hermesServerSttLanguageMismatch({
  required String? serverLanguage,
  required String appLanguage,
}) {
  final server = _canonicalSpeechLanguage(serverLanguage);
  final app = _canonicalSpeechLanguage(appLanguage);
  return server != null && app != null && server != app;
}

String? _canonicalSpeechLanguage(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll('_', '-');
  if (normalized == null ||
      normalized.isEmpty ||
      const {'auto', 'automatic', 'detect', 'system'}.contains(normalized)) {
    return null;
  }
  return normalized.split('-').first;
}

/// Catálogo publicado por el schema de la instancia conectada.
///
/// No contiene una lista incluida en Android: acepta las variantes habituales
/// de JSON Schema (`enum`) y formularios (`options`/`choices`) para que una
/// versión nueva de Hermes siga siendo la autoridad.
class HermesServerVoiceCatalog {
  const HermesServerVoiceCatalog({
    required this.sttProviders,
    required this.ttsProviders,
    required this.published,
  });

  final List<String> sttProviders;
  final List<String> ttsProviders;
  final bool published;

  bool get isEmpty => sttProviders.isEmpty && ttsProviders.isEmpty;

  factory HermesServerVoiceCatalog.fromSchema(
    Map<String, dynamic> response, {
    String? currentSttProvider,
    String? currentTtsProvider,
  }) {
    final wrapped = _record(response['schema']);
    final schema = wrapped.isEmpty ? response : wrapped;
    final sttOptions = _providerOptions(schema, 'stt');
    final ttsOptions = _providerOptions(schema, 'tts');
    return HermesServerVoiceCatalog(
      sttProviders: _withCurrent(sttOptions, currentSttProvider),
      ttsProviders: _withCurrent(ttsOptions, currentTtsProvider),
      published: sttOptions.isNotEmpty || ttsOptions.isNotEmpty,
    );
  }

  static List<String> _providerOptions(
    Map<String, dynamic> schema,
    String section,
  ) {
    // Hermes Desktop publica hoy un registro plano `fields` con claves como
    // `tts.provider`. Aceptar también JSON Schema mantiene compatibilidad con
    // bridges/versiones intermedias sin convertir ninguna forma en allowlist.
    final fields = _record(schema['fields']);
    final flatProviderNode = _record(fields['$section.provider']);
    final sectionNode = _property(schema, section);
    final nestedProviderNode = _property(sectionNode, 'provider');
    final providerNode = flatProviderNode.isNotEmpty
        ? flatProviderNode
        : nestedProviderNode;
    final raw =
        providerNode['enum'] ??
        providerNode['options'] ??
        providerNode['choices'];
    if (raw is! List) return const [];
    final values = <String>[];
    for (final option in raw) {
      final value = option is Map
          ? option['value'] ?? option['id'] ?? option['name']
          : option;
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && !values.contains(text)) {
        values.add(text);
      }
    }
    return List.unmodifiable(values);
  }

  static Map<String, dynamic> _property(
    Map<String, dynamic> node,
    String name,
  ) {
    final properties = _record(node['properties']);
    return _record(properties[name] ?? node[name]);
  }

  static Map<String, dynamic> _record(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static List<String> _withCurrent(List<String> values, String? current) {
    final normalized = current?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        values.contains(normalized)) {
      return values;
    }
    return List.unmodifiable([...values, normalized]);
  }
}

enum HermesServerSpeechDelivery {
  /// Se observó un frame PCM real en esta ejecución.
  pcmStreaming,

  /// El proveedor conocido usa síntesis completa por frase.
  phraseFallback,

  /// El proveedor puede transmitir, pero todavía no existe evidencia runtime.
  checkWhenSpeaking,
}

void _collectPublishedVoicePaths(
  Map<String, dynamic> node,
  List<String> prefix,
  Set<String> output,
) {
  final properties = _record(node['properties']);
  for (final entry in properties.entries) {
    final path = [...prefix, entry.key].join('.');
    if (prefix.isEmpty && (entry.key == 'stt' || entry.key == 'tts')) {
      _collectPublishedVoicePaths(_record(entry.value), [entry.key], output);
      continue;
    }
    if (!_isVoicePath(path)) continue;
    if (_isSecretSchemaField(path, entry.value)) continue;
    final child = _record(entry.value);
    final childProperties = _record(child['properties']);
    if (childProperties.isNotEmpty) {
      _collectPublishedVoicePaths(child, [...prefix, entry.key], output);
    } else {
      output.add(path);
    }
  }
}

bool _isVoicePath(String path) {
  final segments = path.split('.');
  return segments.length >= 2 &&
      (segments.first == 'stt' || segments.first == 'tts') &&
      segments.every(
        (segment) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment),
      );
}

Object? _readPath(Map<String, dynamic> root, String path) {
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is! Map || !current.containsKey(segment)) return null;
    current = current[segment];
  }
  return current;
}

void _writePath(Map<String, dynamic> root, String path, Object value) {
  final segments = path.split('.');
  var current = root;
  for (final segment in segments.take(segments.length - 1)) {
    final existing = current[segment];
    final next = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    current[segment] = next;
    current = next;
  }
  current[segments.last] = value;
}

Object? _safeLeaf(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    final safe = <Object?>[];
    for (final item in value) {
      final copied = _safeLeaf(item);
      if (copied == null && item != null) return null;
      safe.add(copied);
    }
    return List<Object?>.unmodifiable(safe);
  }
  return null;
}

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalValue).toList(growable: false);
  return value;
}

bool _isSecretSchemaField(String path, Object? rawSpec) {
  if (_looksSecret(path)) return true;
  if (rawSpec is! Map) return false;
  final nodes = <Map<dynamic, dynamic>>[rawSpec];
  for (final key in const ['ui', 'metadata', 'annotations', 'x-ui']) {
    final nested = rawSpec[key];
    if (nested is Map) nodes.add(nested);
  }
  for (final node in nodes) {
    for (final entry in node.entries) {
      final key = _collapsed(entry.key.toString());
      final value = entry.value;
      if (const {
            'secret',
            'issecret',
            'sensitive',
            'issensitive',
            'writeonly',
            'obscuretext',
            'obscured',
          }.contains(key) &&
          _metadataFlag(value)) {
        return true;
      }
      if ((key == 'format' || key == 'type' || key == 'inputtype') &&
          _looksSecret(value?.toString() ?? '')) {
        return true;
      }
    }
  }
  return false;
}

bool _looksSecret(String value) {
  final normalized = _collapsed(value);
  return const [
    'apikey',
    'token',
    'secret',
    'password',
    'passwd',
    'credential',
    'authorization',
    'privatekey',
    'bearer',
    'authcookie',
    'sessioncookie',
  ].any(normalized.contains);
}

String _collapsed(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

bool _metadataFlag(Object? value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == 'yes' || normalized == '1';
}

Map<String, dynamic> _record(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
