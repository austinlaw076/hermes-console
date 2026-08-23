import 'dart:convert';
import 'dart:ui' as ui;

import 'hatch_provider.dart';
import 'package:flutter/foundation.dart';

/// Proveedor de generación de **prueba** (sin red).
///
/// - `availability()` → disponible y sin consentimiento de privacidad (es local).
/// - `generate()` → produce una imagen estática **192×208** dibujada con
///   `dart:ui` a partir del prompt (color derivado del texto). Si el entorno no
///   puede codificar PNG (algunos test runners headless), cae a un PNG mínimo
///   embebido para no romper el pipeline.
///
/// Permite forzar fallos (`failWith`) y no-disponibilidad (`unavailableReason`)
/// para tests.
class MockHatchProvider implements HatchProvider {
  /// Si no es `null`, `availability()` devuelve no disponible con esta razón.
  final String? unavailableReason;

  /// Si no es `null`, `generate()` lanza [HatchException] con este mensaje.
  final String? failWith;

  const MockHatchProvider({this.unavailableReason, this.failWith});

  @override
  Future<HatchAvailability> availability() async {
    if (unavailableReason != null) {
      return HatchAvailability.unavailable(unavailableReason!);
    }
    return const HatchAvailability(available: true, requiresPrivacyConsent: false);
  }

  @override
  Future<HatchResult> generate(HatchRequest request) async {
    if (failWith != null) {
      throw HatchException(failWith!);
    }
    final bytes = await _drawPng(request.prompt) ?? _fallbackPng();
    return HatchResult(
      imageBytes: bytes,
      fileName: 'spritesheet.png',
      author: 'Hatch (mock)',
      note: 'mock',
    );
  }

  /// Dibuja un avatar simple 192×208 (fondo + círculo) con color derivado del
  /// prompt. Devuelve PNG, o `null` si el entorno no soporta `toByteData(png)`.
  Future<Uint8List?> _drawPng(String prompt) async {
    try {
      const w = 192, h = 208;
      const rect = ui.Rect.fromLTWH(0, 0, 192, 208);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, rect);
      final hue = (prompt.hashCode & 0xFFFFFF);
      final bg = ui.Color(0xFF000000 | (hue & 0x3F3F3F));
      final fg = ui.Color(0xFF000000 | (0xC0A060 ^ (hue & 0xFFFFFF)));
      canvas.drawRect(rect, ui.Paint()..color = bg);
      canvas.drawCircle(const ui.Offset(96, 104), 56, ui.Paint()..color = fg);
      final img = await recorder.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('[hatch-mock] excepción silenciada (se devuelve null): $e');
      return null;
    }
  }

  /// PNG 1×1 transparente válido (fallback para entornos sin codificación PNG).
  Uint8List _fallbackPng() => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
}
