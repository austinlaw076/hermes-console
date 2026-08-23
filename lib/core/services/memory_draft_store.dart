import 'package:shared_preferences/shared_preferences.dart';

/// Borradores locales de archivos de memoria.
///
/// La API /api/memory es solo lectura (metadatos): no existe endpoint para
/// leer ni escribir el contenido remoto. Este store guarda borradores LOCALES
/// por instancia+archivo y nunca sincroniza nada — la UI debe dejarlo claro.
class MemoryDraftStore {
  final SharedPreferences prefs;

  MemoryDraftStore(this.prefs);

  static String _key(String connId, String name) =>
      'memory_draft::$connId::$name';
  static String _tsKey(String connId, String name) =>
      'memory_draft_ts::$connId::$name';

  bool exists(String connId, String name) =>
      prefs.containsKey(_key(connId, name));

  String? read(String connId, String name) => prefs.getString(_key(connId, name));

  DateTime? updatedAt(String connId, String name) {
    final ms = prefs.getInt(_tsKey(connId, name));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> write(String connId, String name, String text) async {
    await prefs.setString(_key(connId, name), text);
    await prefs.setInt(
      _tsKey(connId, name),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> delete(String connId, String name) async {
    await prefs.remove(_key(connId, name));
    await prefs.remove(_tsKey(connId, name));
  }
}
