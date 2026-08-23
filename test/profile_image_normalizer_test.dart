import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/profile_image_normalizer.dart';

Future<Uint8List> _widePng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 400, 200),
    ui.Paint()..color = const ui.Color(0xffff0000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(100, 0, 200, 200),
    ui.Paint()..color = const ui.Color(0xff00ff00),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('center-crops and normalizes profile images to PNG 256', (
    tester,
  ) async {
    final avatar = (await tester.runAsync(
      () async => ProfileImageNormalizer.normalize(await _widePng()),
    ))!;

    expect(avatar.mimeType, 'image/png');
    expect(avatar.width, ProfileImageNormalizer.outputSize);
    expect(avatar.height, ProfileImageNormalizer.outputSize);

    final decoded = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(avatar.bytes);
      final image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (codec, image, rgba!);
    }))!;
    final (codec, image, rgba) = decoded;
    final center = ((128 * 256) + 128) * 4;
    expect(rgba.getUint8(center), lessThan(8));
    expect(rgba.getUint8(center + 1), greaterThan(247));
    expect(rgba.getUint8(center + 2), lessThan(8));
    image.dispose();
    codec.dispose();
  });

  testWidgets('rejects unsupported and oversized picker inputs', (
    tester,
  ) async {
    await expectLater(
      ProfileImageNormalizer.normalize(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    await expectLater(
      ProfileImageNormalizer.normalize(
        Uint8List(ProfileImageNormalizer.maxInputBytes + 1),
      ),
      throwsFormatException,
    );
  });
}
