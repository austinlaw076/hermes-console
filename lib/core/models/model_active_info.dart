/// Modelo activo retornado por GET /api/model/info (Dashboard, sin auth).
class ModelActiveInfo {
  final String model;
  final String provider;
  final int effectiveContextLength;

  const ModelActiveInfo({
    required this.model,
    required this.provider,
    required this.effectiveContextLength,
  });

  factory ModelActiveInfo.fromJson(Map<String, dynamic> json) =>
      ModelActiveInfo(
        model: (json['model'] as String?) ?? 'hermes-agent',
        provider: (json['provider'] as String?) ?? '',
        effectiveContextLength: _intOrZero(json['effective_context_length']),
      );

  static int _intOrZero(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
