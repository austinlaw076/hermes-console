import 'dart:io';

import 'package:flutter/services.dart';

/// Adaptador mínimo para decorar la notificación del foreground service sin
/// crear otra notificación ni modificar `flutter_foreground_task`.
class VoiceNotificationCardAdapter {
  static const String channelName = 'hermes/voice_notification_card';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<bool> apply({
    required bool paused,
    required String expectedPrimaryAction,
    required String stateLabel,
    required String microphoneLabel,
    required String openHintLabel,
    required String orbDescription,
    required String durationDescription,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('apply', {
        'paused': paused,
        // updateService() encola el cambio del FGS. El host nativo espera a que
        // esta acción aparezca antes de recuperar y decorar la notificación,
        // evitando volver a publicar una versión anterior de los botones.
        'expectedPrimaryAction': expectedPrimaryAction,
        // El host nativo no conoce el locale elegido dentro de Flutter. Pasar
        // la misma copia que usa el resto de la notificación evita mezclar el
        // idioma de la app con el idioma del sistema Android.
        'stateLabel': stateLabel,
        'microphoneLabel': microphoneLabel,
        'openHintLabel': openHintLabel,
        'orbDescription': orbDescription,
        'durationDescription': durationDescription,
      });
      return result?['applied'] == true || result?['scheduled'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Olvida el cronómetro nativo. El plugin sustituye la vista custom cuando
  /// se degrada/reinicia el FGS; este método no cancela notificaciones.
  static Future<void> clear() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Tests/plataformas sin host Android: no hay superficie que limpiar.
    } on PlatformException {
      // La salida de voz debe seguir siendo fail-closed aunque falle la UI.
    }
  }

  /// Diagnóstico categórico para tests físicos; nunca contiene transcript,
  /// respuesta, URL, comandos ni payloads del usuario.
  static Future<Map<String, dynamic>> inspect() async {
    if (!Platform.isAndroid) return const {'active': false};
    try {
      return await _channel.invokeMapMethod<String, dynamic>('inspect') ??
          const {'active': false};
    } on MissingPluginException {
      return const {'active': false};
    } on PlatformException {
      return const {'active': false};
    }
  }
}
