import 'agent_runtime/agent_runtime.dart';

/// Utilidades de versión del Mobile Bridge: compara la versión que CORRE en el
/// servidor con la que ESTE APK trae empaquetada
/// ([AgentRuntimeConsts.expectedBridgeVersion]) para avisar de actualizaciones.
class BridgeVersion {
  /// Compara dos versiones tipo "1.8.0": `<0` si a&lt;b, `0` si igual, `>0` si mayor.
  /// Tolerante: trozos no numéricos cuentan como 0, longitudes distintas se
  /// rellenan con 0.
  static int compare(String a, String b) {
    final pa = a.trim().split('.');
    final pb = b.trim().split('.');
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? (int.tryParse(pa[i].trim()) ?? 0) : 0;
      final vb = i < pb.length ? (int.tryParse(pb[i].trim()) ?? 0) : 0;
      if (va != vb) return va < vb ? -1 : 1;
    }
    return 0;
  }

  /// La versión empaquetada en este APK (la que el bridge debería tener).
  static String get expected => AgentRuntimeConsts.expectedBridgeVersion;

  /// True si [running] es una versión ANTERIOR a la empaquetada (hay update).
  /// Null/vacío → false (no sabemos; no molestamos con un aviso).
  static bool isOutdated(String? running) {
    final r = (running ?? '').trim();
    if (r.isEmpty) return false;
    return compare(r, expected) < 0;
  }
}
