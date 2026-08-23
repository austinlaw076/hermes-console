import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Escala visual fija de Hermes.
///
/// El 110 % es la densidad aceptada para la interfaz. Se multiplica por la
/// escala de accesibilidad de Android en `MaterialApp.builder`, de modo que no
/// limita el tamaño configurado por el usuario en el sistema.
class FontSizeService extends ChangeNotifier {
  static const double fixedScale = 1.10;
  static const double minScale = 0.90;
  static const double maxScale = 1.25;
  static const int divisions = 7;

  // Se conserva el parámetro para no alterar el contrato de arranque del app.
  // Las preferencias antiguas dejan de influir en el layout.
  FontSizeService(SharedPreferences _);

  double get scale => fixedScale;

  static double normalize(double _) => fixedScale;

  /// Compatibilidad binaria con pantallas antiguas: la densidad ya no cambia.
  Future<void> setScale(double _) async {}
}
