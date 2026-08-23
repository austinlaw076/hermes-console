/// Modelos de la receta de Mixture of Agents (MoA) de Hermes (spec 029).
///
/// Espeja `GET/PUT /api/model/moa` (verificado contra Hermes 0.18): el MoA es
/// un proveedor virtual donde N modelos de REFERENCIA asesoran y un AGREGADOR
/// sintetiza y actúa. La receta vive en el servidor como presets con nombre.
///
/// `referenceMaxTokens` y `fanout` se LEEN (el GET los devuelve) pero el PUT no
/// los acepta → son read-only: se muestran informativos, nunca se envían.
library;

/// Un participante del comité: proveedor + modelo.
class MoaSlot {
  final String provider;
  final String model;

  const MoaSlot({required this.provider, required this.model});

  factory MoaSlot.fromJson(Map<String, dynamic> json) => MoaSlot(
        provider: (json['provider'] ?? '').toString(),
        model: (json['model'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'provider': provider, 'model': model};

  MoaSlot copyWith({String? provider, String? model}) =>
      MoaSlot(provider: provider ?? this.provider, model: model ?? this.model);

  bool get isEmpty => provider.isEmpty && model.isEmpty;
}

/// Una receta con nombre: comité de referencias + agregador + ajustes.
class MoaPreset {
  final List<MoaSlot> referenceModels;
  final MoaSlot aggregator;

  /// null = temperatura omitida (default del proveedor). Nunca forzar 0.
  final double? referenceTemperature;
  final double? aggregatorTemperature;
  final int maxTokens;
  final bool enabled;

  /// Read-only (el PUT no lo acepta): tope de tokens por advisor. null = sin cap.
  final int? referenceMaxTokens;

  /// Read-only (el PUT no lo acepta): `per_iteration` | `user_turn`.
  final String fanout;

  const MoaPreset({
    required this.referenceModels,
    required this.aggregator,
    this.referenceTemperature,
    this.aggregatorTemperature,
    this.maxTokens = 4096,
    this.enabled = true,
    this.referenceMaxTokens,
    this.fanout = 'per_iteration',
  });

  factory MoaPreset.fromJson(Map<String, dynamic> json) {
    final refs = (json['reference_models'] as List?)
            ?.whereType<Map>()
            .map((e) => MoaSlot.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        <MoaSlot>[];
    final aggRaw = json['aggregator'];
    return MoaPreset(
      referenceModels: refs,
      aggregator: aggRaw is Map
          ? MoaSlot.fromJson(aggRaw.cast<String, dynamic>())
          : const MoaSlot(provider: '', model: ''),
      referenceTemperature: _asDouble(json['reference_temperature']),
      aggregatorTemperature: _asDouble(json['aggregator_temperature']),
      maxTokens: _asInt(json['max_tokens'], 4096),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      referenceMaxTokens: _asIntOrNull(json['reference_max_tokens']),
      fanout: (json['fanout'] ?? 'per_iteration').toString(),
    );
  }

  /// Forma que acepta el PUT (`MoaPresetPayload`): SIN `reference_max_tokens`
  /// ni `fanout` (el servidor no los persiste por esta vía).
  Map<String, dynamic> toJson() => {
        'reference_models': [for (final r in referenceModels) r.toJson()],
        'aggregator': aggregator.toJson(),
        'reference_temperature': referenceTemperature,
        'aggregator_temperature': aggregatorTemperature,
        'max_tokens': maxTokens,
        'enabled': enabled,
      };

  MoaPreset copyWith({
    List<MoaSlot>? referenceModels,
    MoaSlot? aggregator,
    double? referenceTemperature,
    bool clearReferenceTemperature = false,
    double? aggregatorTemperature,
    bool clearAggregatorTemperature = false,
    int? maxTokens,
    bool? enabled,
  }) =>
      MoaPreset(
        referenceModels: referenceModels ?? this.referenceModels,
        aggregator: aggregator ?? this.aggregator,
        referenceTemperature: clearReferenceTemperature
            ? null
            : (referenceTemperature ?? this.referenceTemperature),
        aggregatorTemperature: clearAggregatorTemperature
            ? null
            : (aggregatorTemperature ?? this.aggregatorTemperature),
        maxTokens: maxTokens ?? this.maxTokens,
        enabled: enabled ?? this.enabled,
        referenceMaxTokens: referenceMaxTokens,
        fanout: fanout,
      );
}

/// La config MoA completa: presets con nombre + cuál es el default/activo.
class MoaConfig {
  final String defaultPreset;
  final String activePreset;
  final Map<String, MoaPreset> presets;

  const MoaConfig({
    required this.defaultPreset,
    required this.activePreset,
    required this.presets,
  });

  /// El preset que la pantalla edita por defecto (el `default`).
  MoaPreset? get active => presets[defaultPreset];

  factory MoaConfig.fromJson(Map<String, dynamic> json) {
    final presets = <String, MoaPreset>{};
    final raw = json['presets'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          presets[k.toString()] =
              MoaPreset.fromJson(v.cast<String, dynamic>());
        }
      });
    }
    var defaultName = (json['default_preset'] ?? '').toString().trim();
    // Compat: si el servidor no trajo presets (forma vieja aplanada), el nivel
    // raíz ES el preset default.
    if (presets.isEmpty) {
      presets['default'] = MoaPreset.fromJson(json);
      defaultName = 'default';
    }
    if (defaultName.isEmpty || !presets.containsKey(defaultName)) {
      defaultName = presets.keys.first;
    }
    var activeName = (json['active_preset'] ?? '').toString().trim();
    if (!presets.containsKey(activeName)) activeName = '';
    return MoaConfig(
      defaultPreset: defaultName,
      activePreset: activeName,
      presets: presets,
    );
  }

  /// Forma con `presets` que acepta el PUT. Reenvía TODOS los presets (no solo
  /// el editado) para que el servidor —que reemplaza el bloque `moa` entero—
  /// no pierda los ajenos (guardado atómico, FR-003).
  Map<String, dynamic> toJson() => {
        'default_preset': defaultPreset,
        'active_preset': activePreset,
        'presets': {
          for (final e in presets.entries) e.key: e.value.toJson(),
        },
      };

  /// Sustituye [name] por [preset] devolviendo una config nueva (los demás
  /// presets se conservan intactos).
  MoaConfig withPreset(String name, MoaPreset preset) => MoaConfig(
        defaultPreset: defaultPreset,
        activePreset: activePreset,
        presets: {...presets, name: preset},
      );
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _asInt(Object? v, int fallback) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
