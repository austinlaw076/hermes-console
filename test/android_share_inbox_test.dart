import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/services/android_share_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureValues = <String, String>{};
  late File sharedImage;

  setUp(() async {
    secureValues.clear();
    sharedImage = File(
      '${Directory.systemTemp.path}/hermes-share-'
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await sharedImage.writeAsBytes([1, 2, 3, 4]);

    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            switch (call.method) {
              case 'write':
                secureValues[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return secureValues[args['key'] as String];
              case 'delete':
                secureValues.remove(args['key'] as String);
                return null;
              case 'readAll':
                return Map<String, String>.from(secureValues);
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hermes/share'), null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    if (await sharedImage.exists()) await sharedImage.delete();
  });

  test('convierte ACTION_SEND en una bandeja cifrada y recuperable', () async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hermes/share'), (
          call,
        ) async {
          expect(call.method, 'takePendingShare');
          return {
            'id': 'share-1',
            'text': 'https://example.com/noticia',
            'attachments': [
              {
                'type': 'image',
                'name': 'captura.jpg',
                'mime_type': 'image/jpeg',
                'size_bytes': 4,
                'local_path': sharedImage.path,
              },
            ],
            'rejected_attachments': 0,
          };
        });

    final inbox = AndroidShareInbox();
    final pending = await inbox.initialize();

    expect(pending?.id, 'share-1');
    expect(pending?.text, 'https://example.com/noticia');
    expect(pending?.attachments.single.name, 'captura.jpg');
    expect(secureValues, hasLength(1));

    await inbox.acknowledge('share-1');
    expect(await inbox.peek(), isNull);
    expect(secureValues, isEmpty);
    await inbox.dispose();
  });

  test('descarta rutas revocadas sin perder el aviso de rechazo', () {
    final content = AndroidSharedContent.fromMap({
      'id': 'share-2',
      'text': '',
      'attachments': [
        {
          'type': 'image',
          'name': 'ya-no-existe.jpg',
          'mime_type': 'image/jpeg',
          'size_bytes': 4,
          'local_path': '${sharedImage.path}.missing',
        },
      ],
      'rejected_attachments': 1,
    });

    expect(content, isNotNull);
    expect(content?.attachments, isEmpty);
    expect(content?.rejectedAttachments, 1);
  });

  test(
    'manifest y MainActivity publican el contrato Android sin permisos extra',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
        'MainActivity.kt',
      ).readAsStringSync();

      expect(manifest, contains('android.intent.action.SEND'));
      expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
      expect(manifest, contains('android:mimeType="text/plain"'));
      expect(manifest, contains('android:mimeType="image/*"'));
      expect(
        activity,
        contains('private val shareChannelName = "hermes/share"'),
      );
      expect(activity, contains('File(cacheDir, "shared_intents")'));
      expect(activity, contains('MAX_SHARE_ITEM_BYTES'));
    },
  );
}
