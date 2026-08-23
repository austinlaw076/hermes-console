import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/agent_profile.dart';

/// Normaliza la imagen elegida con el mismo resultado visible que Bot Mode:
/// crop centrado, raster cuadrado y PNG 256x256 antes de subir el avatar.
///
/// El original puede ser mayor que el límite de assets de Hermes porque sólo
/// se envía el PNG normalizado. [ImageDescriptor] reduce durante el decode para
/// no materializar fotografías de cámara a resolución completa en memoria.
final class ProfileImageNormalizer {
  static const maxInputBytes = 15000000;
  static const outputSize = 256;

  const ProfileImageNormalizer._();

  static Future<AgentProfileAvatar> normalize(Uint8List source) async {
    if (source.isEmpty || source.length > maxInputBytes) {
      throw const FormatException('Profile image exceeds input limit');
    }
    if (!_isSupportedRaster(source)) {
      throw const FormatException('Unsupported profile image');
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    ui.Picture? picture;
    ui.Image? normalized;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) {
        throw const FormatException('Invalid profile image dimensions');
      }

      final shortest = descriptor.width < descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = outputSize / shortest;
      final targetWidth = (descriptor.width * scale).round().clamp(
        outputSize,
        16384,
      );
      final targetHeight = (descriptor.height * scale).round().clamp(
        outputSize,
        16384,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      decoded = (await codec.getNextFrame()).image;

      final cropSize = decoded.width < decoded.height
          ? decoded.width.toDouble()
          : decoded.height.toDouble();
      final sourceRect = ui.Rect.fromLTWH(
        (decoded.width - cropSize) / 2,
        (decoded.height - cropSize) / 2,
        cropSize,
        cropSize,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        decoded,
        sourceRect,
        ui.Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();
      normalized = await picture.toImage(outputSize, outputSize);
      final png = await normalized.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const FormatException('Profile image could not be encoded');
      }
      final dataUri =
          'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
      return AgentProfileAvatar.fromDataUri(dataUri);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Profile image could not be decoded');
    } finally {
      normalized?.dispose();
      picture?.dispose();
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static bool _isSupportedRaster(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
  }
}
