/// Model metadata returned by GET /v1/models (OpenAI-compatible format).
class ModelInfo {
  final String id;
  final String object;
  final int? created;
  final String? ownedBy;

  const ModelInfo({
    required this.id,
    this.object = 'model',
    this.created,
    this.ownedBy,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    id: _stringOrDefault(json['id'], 'hermes-agent'),
    object: _stringOrDefault(json['object'], 'model'),
    created: _intOrNull(json['created']),
    ownedBy: json['owned_by'] is String ? json['owned_by'] as String : null,
  );

  @override
  String toString() => id;

  static String _stringOrDefault(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value;
    return fallback;
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
