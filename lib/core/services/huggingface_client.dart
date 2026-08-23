// Cliente de solo lectura para la API pública de Hugging Face.
//
// Se usa en el navegador de modelos locales (Android/GGUF). No requiere clave
// para modelos públicos. NO descarga ni instala nada por sí mismo: solo lista
// modelos y sus ficheros para que la UI ofrezca el enlace de descarga.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Modelo de HF (resumen de la búsqueda).
class HfModel {
  final String id; // p.ej. "TheBloke/Llama-2-7B-GGUF"
  final int downloads;
  final int likes;
  final List<String> tags;

  HfModel({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.tags,
  });

  String get owner => id.contains('/') ? id.split('/').first : '';
  String get name => id.contains('/') ? id.split('/').last : id;

  static final RegExp _paramsRe = RegExp(r'(\d+(?:\.\d+)?)\s*[bB]\b');

  /// Parámetros totales (en miles de millones) deducidos del nombre del modelo
  /// (p.ej. "Qwen3.6-35B-A3B" → 35). Para MoE cuenta el total (lo que ocupa en
  /// RAM al cargar el GGUF), no los activos. null si no se puede deducir.
  double? get paramsB {
    final m = _paramsRe.firstMatch(name);
    final v = m == null ? null : double.tryParse(m.group(1)!);
    if (v == null || v <= 0 || v > 2000) return null;
    return v;
  }

  /// Huella estimada en RAM de una cuantización Q4 (GB): ~0.55 GB/B + overhead.
  /// Es una ESTIMACIÓN (depende del quant/contexto reales).
  double? get estimatedQ4Gb {
    final p = paramsB;
    return p == null ? null : p * 0.55 + 0.7;
  }

  /// RAM realmente usable para inferencia ≈ 55% de la total (OS + apps + app).
  static double usableRamGb(double totalRamGb) => totalRamGb * 0.55;

  /// ¿Cabe (estimado, Q4) en la RAM usable del dispositivo?
  bool fitsIn(double totalRamGb) {
    final need = estimatedQ4Gb;
    if (need == null) return false;
    return need <= usableRamGb(totalRamGb);
  }

  factory HfModel.fromJson(Map<String, dynamic> j) => HfModel(
        id: (j['id'] ?? j['modelId'] ?? '').toString(),
        downloads: (j['downloads'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// Fichero dentro de un repo de modelo (con tamaño).
class HfFile {
  final String path;
  final int sizeBytes;
  HfFile({required this.path, required this.sizeBytes});

  bool get isGguf => path.toLowerCase().endsWith('.gguf');

  String get humanSize {
    if (sizeBytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var s = sizeBytes.toDouble();
    var i = 0;
    while (s >= 1024 && i < units.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(s >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }
}

class HuggingFaceClient {
  final http.Client _http;
  static const _base = 'https://huggingface.co';
  static const _timeout = Duration(seconds: 12);

  HuggingFaceClient({http.Client? client}) : _http = client ?? http.Client();

  /// Busca modelos GGUF (compatibles con inferencia local on-device).
  Future<List<HfModel>> searchGgufModels({
    String query = '',
    int limit = 30,
  }) async {
    final params = {
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$limit',
      if (query.trim().isNotEmpty) 'search': query.trim(),
    };
    final uri = Uri.parse('$_base/api/models').replace(queryParameters: params);
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HF HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HfModel.fromJson)
        .toList();
  }

  /// Lista los ficheros (con tamaño) del repo del modelo, ordenando GGUF.
  Future<List<HfFile>> listFiles(String modelId) async {
    final uri = Uri.parse('$_base/api/models/$modelId/tree/main?recursive=true');
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HF HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    final files = <HfFile>[];
    for (final e in data) {
      if (e is Map && e['type'] == 'file') {
        files.add(HfFile(
          path: (e['path'] ?? '').toString(),
          sizeBytes: (e['size'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    files.sort((a, b) {
      if (a.isGguf != b.isGguf) return a.isGguf ? -1 : 1;
      return a.path.compareTo(b.path);
    });
    return files;
  }

  /// URL de descarga directa de un fichero del repo.
  static Uri downloadUrl(String modelId, String path) =>
      Uri.parse('$_base/$modelId/resolve/main/$path?download=true');

  void close() => _http.close();
}
