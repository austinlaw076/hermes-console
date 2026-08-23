/// Desglose estimado de la ventana de contexto que expone Hermes Desktop 0.19.
///
/// El servidor es una frontera remota: el parser conserva solo escalares
/// acotados, descarta filas inválidas y nunca usa el color CSS recibido para
/// pintar la UI Android.
class DesktopContextBreakdown {
  final List<DesktopContextUsageCategory> categories;
  final int contextMax;
  final int contextUsed;
  final int contextPercent;
  final int estimatedTotal;
  final String? model;

  const DesktopContextBreakdown({
    this.categories = const [],
    this.contextMax = 0,
    this.contextUsed = 0,
    this.contextPercent = 0,
    this.estimatedTotal = 0,
    this.model,
  });

  factory DesktopContextBreakdown.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    if (rawCategories != null && rawCategories is! List) {
      throw const FormatException('context categories must be a list');
    }

    final byId = <String, DesktopContextUsageCategory>{};
    for (final raw in (rawCategories as List? ?? const [])) {
      final category = DesktopContextUsageCategory.tryParse(raw);
      if (category == null) continue;
      // El contrato oficial usa ids únicos. Si un servidor defectuoso repite
      // uno, gana la última fila en vez de inflar artificialmente el total.
      byId[category.id] = category;
      if (byId.length >= 64) break;
    }

    final contextMax = _nonNegativeInt(json['context_max']);
    final contextUsed = _nonNegativeInt(json['context_used']);
    final suppliedPercent = _finiteNumber(json['context_percent']);
    final computedPercent = contextMax > 0
        ? ((contextUsed / contextMax) * 100).round()
        : 0;

    return DesktopContextBreakdown(
      categories: List.unmodifiable(byId.values),
      contextMax: contextMax,
      contextUsed: contextUsed,
      contextPercent: (suppliedPercent?.round() ?? computedPercent)
          .clamp(0, 100)
          .toInt(),
      estimatedTotal: _nonNegativeInt(json['estimated_total']),
      model: _boundedText(json['model'], 160),
    );
  }
}

class DesktopContextUsageCategory {
  final String id;
  final String label;
  final int tokens;

  const DesktopContextUsageCategory({
    required this.id,
    required this.label,
    required this.tokens,
  });

  static DesktopContextUsageCategory? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _boundedText(value['id'], 64);
    if (id == null || !RegExp(r'^[a-z][a-z0-9_\-]*$').hasMatch(id)) {
      return null;
    }
    final tokens = _nonNegativeIntOrNull(value['tokens']);
    if (tokens == null || tokens == 0) return null;
    final label = _boundedText(value['label'], 96) ?? id;
    return DesktopContextUsageCategory(id: id, label: label, tokens: tokens);
  }
}

int _nonNegativeInt(Object? value) => _nonNegativeIntOrNull(value) ?? 0;

int? _nonNegativeIntOrNull(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  final integer = value.toInt();
  if (value != integer) return null;
  // Evita ratios/flex absurdos en la superficie aunque el peer esté roto.
  return integer.clamp(0, 1 << 53).toInt();
}

double? _finiteNumber(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

String? _boundedText(Object? value, int maxLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}
