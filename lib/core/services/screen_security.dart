import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla FLAG_SECURE en Android para impedir capturas, grabación de pantalla
/// y miniaturas recientes cuando el usuario lo activa.
class ScreenSecurityService {
  static const prefKey = 'security_block_screenshots';
  static const _channel = MethodChannel('hermes/security');

  final SharedPreferences _prefs;

  ScreenSecurityService(this._prefs);

  bool get enabled => _prefs.getBool(prefKey) ?? false;

  Future<void> apply() async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', enabled);
    } on MissingPluginException {
      // Tests y plataformas no Android: la preferencia se conserva sin fallar.
    } on PlatformException {
      // Protección best-effort; nunca debe impedir abrir la app.
    }
  }

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(prefKey, value);
    await apply();
  }
}
