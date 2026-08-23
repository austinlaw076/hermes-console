/// Typed, forward-compatible representation of
/// `GET /api/tools/toolsets/tts/config`.
///
/// The Dashboard may add fields independently of the Android release. Every
/// model therefore exposes [extraFields] and merges them back in [toJson], so
/// callers can inspect and forward a response without silently dropping data.
class HermesTtsToolsetConfig {
  final String? activeProvider;
  final List<HermesTtsToolsetProvider> providers;
  final Map<String, dynamic> extraFields;

  const HermesTtsToolsetConfig({
    this.activeProvider,
    this.providers = const [],
    this.extraFields = const {},
  });

  factory HermesTtsToolsetConfig.fromJson(Map<String, dynamic> json) {
    return HermesTtsToolsetConfig(
      activeProvider: _string(json['active_provider']),
      providers: _records(
        json['providers'],
      ).map(HermesTtsToolsetProvider.fromJson).toList(growable: false),
      extraFields: _extraFields(json, const {'active_provider', 'providers'}),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    ..._mutableCopyMap(extraFields),
    'active_provider': activeProvider,
    'providers': providers.map((provider) => provider.toJson()).toList(),
  };
}

class HermesTtsToolsetProvider {
  final String? name;
  final String? tag;
  final String? status;
  final bool? isActive;
  final String? ttsProvider;
  final List<HermesTtsToolsetEnvVar> envVars;

  /// Provider-specific setup metadata. Hermes currently publishes this as
  /// JSON data, and its shape is intentionally left open for future providers.
  final Object? postSetup;

  final Map<String, dynamic> extraFields;

  const HermesTtsToolsetProvider({
    this.name,
    this.tag,
    this.status,
    this.isActive,
    this.ttsProvider,
    this.envVars = const [],
    this.postSetup,
    this.extraFields = const {},
  });

  factory HermesTtsToolsetProvider.fromJson(Map<String, dynamic> json) {
    return HermesTtsToolsetProvider(
      name: _string(json['name']),
      tag: _string(json['tag']),
      status: _string(json['status']),
      isActive: _bool(json['is_active']),
      ttsProvider: _string(json['tts_provider']),
      envVars: _records(
        json['env_vars'],
      ).map(HermesTtsToolsetEnvVar.fromJson).toList(growable: false),
      postSetup: _immutableCopy(json['post_setup']),
      extraFields: _extraFields(json, const {
        'name',
        'tag',
        'status',
        'is_active',
        'tts_provider',
        'env_vars',
        'post_setup',
      }),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    ..._mutableCopyMap(extraFields),
    'name': name,
    'tag': tag,
    'status': status,
    'is_active': isActive,
    'tts_provider': ttsProvider,
    'env_vars': envVars.map((envVar) => envVar.toJson()).toList(),
    'post_setup': _mutableCopy(postSetup),
  };
}

class HermesTtsToolsetEnvVar {
  final String? key;
  final String? label;
  final bool? isSet;
  final bool? secret;
  final Map<String, dynamic> extraFields;

  const HermesTtsToolsetEnvVar({
    this.key,
    this.label,
    this.isSet,
    this.secret,
    this.extraFields = const {},
  });

  factory HermesTtsToolsetEnvVar.fromJson(Map<String, dynamic> json) {
    return HermesTtsToolsetEnvVar(
      key: _string(json['key']),
      label: _string(json['label']),
      isSet: _bool(json['is_set']),
      secret: _bool(json['secret']),
      extraFields: _extraFields(json, const {
        'key',
        'label',
        'is_set',
        'secret',
      }),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    ..._mutableCopyMap(extraFields),
    'key': key,
    'label': label,
    'is_set': isSet,
    'secret': secret,
  };
}

String? _string(Object? value) => value is String ? value : null;

bool? _bool(Object? value) => value is bool ? value : null;

List<Map<String, dynamic>> _records(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> _extraFields(
  Map<String, dynamic> source,
  Set<String> knownKeys,
) {
  return Map<String, dynamic>.unmodifiable({
    for (final entry in source.entries)
      if (!knownKeys.contains(entry.key))
        entry.key: _immutableCopy(entry.value),
  });
}

Object? _immutableCopy(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _immutableCopy(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_immutableCopy));
  }
  return value;
}

Map<String, dynamic> _mutableCopyMap(Map<String, dynamic> value) => {
  for (final entry in value.entries) entry.key: _mutableCopy(entry.value),
};

Object? _mutableCopy(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _mutableCopy(entry.value),
    };
  }
  if (value is List) return value.map(_mutableCopy).toList();
  return value;
}
