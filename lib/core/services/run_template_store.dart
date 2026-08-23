// Persistencia de las plantillas de ejecución propias del usuario.
//
// Las predefinidas (RunTemplate.builtins) viven en código; aquí solo se guardan
// las que el usuario crea, en SharedPreferences como una lista JSON. El método
// [all] devuelve builtins + propias en ese orden, listo para la UI.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/run_template.dart';

class RunTemplateStore {
  static const String _key = 'run_templates_custom_v1';

  final SharedPreferences _prefs;
  final List<RunTemplate> _custom;

  RunTemplateStore._(this._prefs, this._custom);

  /// Carga las plantillas propias persistidas. Tolerante a datos corruptos:
  /// si el JSON no parsea, arranca vacío en vez de fallar.
  static Future<RunTemplateStore> load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    final custom = <RunTemplate>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is Map<String, dynamic>) custom.add(RunTemplate.fromJson(e));
          }
        }
      } catch (_) {
        // Datos corruptos: se ignoran (no se borran por si son recuperables).
      }
    }
    return RunTemplateStore._(prefs, custom);
  }

  /// Plantillas propias del usuario. La UI las combina con las predefinidas
  /// localizadas (`builtinRunTemplates`).
  List<RunTemplate> get custom => List.unmodifiable(_custom);

  Future<void> add(RunTemplate t) async {
    _custom.add(t);
    await _persist();
  }

  Future<void> update(RunTemplate t) async {
    final i = _custom.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      _custom[i] = t;
      await _persist();
    }
  }

  Future<void> remove(String id) async {
    _custom.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    final raw = jsonEncode(_custom.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, raw);
  }

  /// Genera un id único para una plantilla nueva del usuario.
  static String newId() =>
      'c_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
