import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/themes_screen.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';

Matcher _codecError(String code) => isA<ThemeProfileCodecException>().having(
  (error) => error.code,
  'code',
  code,
);

void main() {
  group('theme import file guard', () {
    test('rejects oversized metadata before opening the read stream', () async {
      var listened = false;
      final stream = Stream<List<int>>.multi((controller) {
        listened = true;
        controller.close();
      });
      final selected = PlatformFile(
        name: 'oversized.json',
        size: ThemeProfileCodec.maxBytes + 1,
        readStream: stream,
      );

      await expectLater(
        readThemeImportBytes(selected),
        throwsA(_codecError('payload_too_large')),
      );

      expect(listened, isFalse);
    });

    test('bounded stream fallback catches inaccurate small metadata', () async {
      var deliveredChunks = 0;
      Stream<List<int>> source() async* {
        deliveredChunks += 1;
        yield Uint8List(ThemeProfileCodec.maxBytes);
        deliveredChunks += 1;
        yield const [1];
        deliveredChunks += 1;
        yield const [2];
      }

      final selected = PlatformFile(
        name: 'misreported.json',
        size: 1,
        readStream: source(),
      );

      await expectLater(
        readThemeImportBytes(selected),
        throwsA(_codecError('payload_too_large')),
      );

      expect(deliveredChunks, 2);
    });

    test(
      'reads an unknown-size stream when it remains within the limit',
      () async {
        final expected = Uint8List.fromList(const [1, 2, 3, 4]);
        final selected = PlatformFile(
          name: 'theme.json',
          size: 0,
          readStream: Stream.value(expected),
        );

        final bytes = await readThemeImportBytes(selected);

        expect(bytes, orderedEquals(expected));
      },
    );
  });
}
