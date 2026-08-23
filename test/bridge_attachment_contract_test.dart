import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('assets/bridge/hermes_bridge.py').readAsStringSync();

  group('POST /bridge/attachments', () {
    test('está versionado y registrado en el bridge empaquetado', () {
      expect(src, contains('VERSION = "1.18.0"'));
      expect(src, contains('async def attachment_upload(request):'));
      expect(
        src,
        contains(
          'app.router.add_post("/bridge/attachments", attachment_upload)',
        ),
      );
    });

    test('exige command, respeta read-only y bloquea ejecutables', () {
      final handler = _handlerBody(src);
      expect(handler, contains('_check_auth(request, "command")'));
      expect(handler, contains('if READ_ONLY:'));
      expect(src, contains('".apk", ".exe", ".sh"'));
      expect(handler, contains('_ATTACHMENT_NAME_RE.match(name)'));
    });

    test('transmite en chunks con límite y escritura atómica', () {
      final handler = _handlerBody(src);
      expect(handler, contains('iter_chunked(64 * 1024)'));
      expect(handler, contains('total > MAX_ATTACHMENT_BYTES'));
      expect(handler, contains('partial.open("xb")'));
      expect(handler, contains('os.replace(partial, target)'));
      expect(handler, contains('partial.unlink(missing_ok=True)'));
    });

    test('el almacén está confinado y tiene GC por edad y cuota', () {
      expect(
        src,
        contains(
          'ATTACHMENTS_DIR = (HERMES_HOME / "uploads" / "mobile").resolve()',
        ),
      );
      expect(src, contains('MAX_ATTACHMENT_STORE_BYTES = 100 * 1024 * 1024'));
      expect(src, contains('ATTACHMENT_MAX_AGE_SECONDS = 7 * 24 * 60 * 60'));
      expect(src, contains('_gc_mobile_attachments(keep=target)'));
    });
  });
}

String _handlerBody(String src) {
  final start = src.indexOf('async def attachment_upload(request):');
  expect(start, greaterThanOrEqualTo(0));
  final rest = src.substring(start);
  final end = rest.indexOf('\nasync def ', 1);
  return end > 0 ? rest.substring(0, end) : rest;
}
