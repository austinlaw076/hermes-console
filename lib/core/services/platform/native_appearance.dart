import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps Android's per-app day/night resources aligned with the active Hermes
/// profile. Android 12 draws its splash before Flutter's first frame, so this
/// setting is what lets the next cold start select the matching native splash.
final class NativeAppearance {
  static const MethodChannel _channel = MethodChannel('hermes/appearance');

  const NativeAppearance._();

  static Future<void> sync(Brightness brightness) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setBrightness', {
        'brightness': brightness == Brightness.light ? 'light' : 'dark',
      });
    } on MissingPluginException {
      // Widget tests and non-Android embedders do not register this channel.
    } on PlatformException {
      // Appearance sync is best-effort; it must never block app startup.
    }
  }
}
