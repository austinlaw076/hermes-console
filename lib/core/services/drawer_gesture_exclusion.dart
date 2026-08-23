import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reserva una franja pequeña del borde izquierdo para abrir el drawer.
///
/// Android limita estas exclusiones y puede recortarlas. La capa nativa usa
/// únicamente una banda central de 200 dp; nunca toca el borde derecho. Cada
/// ruta con drawer activa o desactiva la banda mediante [RouteAware].
class DrawerGestureExclusion {
  static const MethodChannel _channel = MethodChannel('hermes/system_gestures');

  static bool? _lastRequested;

  static Future<void> setEnabled(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _lastRequested == enabled) {
      return;
    }
    _lastRequested = enabled;
    try {
      await _channel.invokeMethod<void>('setDrawerEdgeExclusion', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Tests y plataformas sin el adaptador nativo: el drawer conserva la
      // banda interior de Flutter como fallback.
    } on PlatformException catch (error) {
      debugPrint('[drawer-gesture] no se pudo aplicar la exclusión: $error');
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _lastRequested = null;
  }
}
