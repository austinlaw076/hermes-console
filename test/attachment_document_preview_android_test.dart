import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el contrato PDF usa PdfRenderer sobre la raíz privada verificada', () {
    final handler = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesDocumentPreviewHandler.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'MainActivity.kt',
    ).readAsStringSync();
    final dartPreview = File(
      'lib/core/widgets/attachment_history_preview.dart',
    ).readAsStringSync();

    expect(handler, contains('android.graphics.pdf.PdfRenderer'));
    expect(handler, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
    expect(handler, contains('SENT_ATTACHMENTS_DIRECTORY'));
    expect(handler, contains('canonicalFile'));
    expect(handler, contains('expectedSha256 == storageKey'));
    expect(handler, contains('file.sha256() == expectedSha256'));
    expect(handler, isNot(contains('startActivity')));
    expect(handler, isNot(contains('Intent(')));
    expect(handler, isNot(contains('requestPermissions')));

    expect(activity, contains('"hermes/document_preview"'));
    expect(
      activity,
      contains('HermesDocumentPreviewHandler(applicationContext)'),
    );
    expect(dartPreview, contains("'hermes/document_preview'"));
    expect(dartPreview, contains("'renderPdfPage'"));
    expect(dartPreview, isNot(contains("'path': widget.file.path")));
  });
}
