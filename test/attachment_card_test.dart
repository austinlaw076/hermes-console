import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/attachment_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    theme: AppTheme.hermesRedDark,
    home: Scaffold(body: child),
  );

  testWidgets('adjunto en subida muestra progreso y permite quitarlo', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'captura.jpg',
          mimeType: 'image/jpeg',
          sizeLabel: '2 MB',
          showUploadState: true,
          uploadState: AttachmentUploadState.uploading,
          onRemove: () {},
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.textContaining('Subiendo'), findsOneWidget);
  });

  testWidgets('quitar adjunto tiene etiqueta y target de 48 dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'documento.pdf',
          mimeType: 'application/pdf',
          sizeLabel: '20 KB',
          onRemove: () {},
        ),
      ),
    );

    final target = find
        .ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(tester.getSize(target), const Size(48, 48));
    expect(find.bySemanticsLabel('Quitar adjunto'), findsOneWidget);
  });

  testWidgets('error de imagen ofrece retry y remove independientes de 48 dp', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'attachment-card-image-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final image = File('${directory.path}/pixel.png');
    image.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    var retries = 0;
    var removes = 0;

    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'captura.png',
          mimeType: 'image/png',
          sizeLabel: '1 KB',
          thumbnailFile: image,
          showUploadState: true,
          uploadState: AttachmentUploadState.error,
          onRetry: () => retries++,
          onRemove: () => removes++,
        ),
      ),
    );

    expect(find.text('Error al subir'), findsOneWidget);
    expect(find.bySemanticsLabel('Reintentar adjunto'), findsOneWidget);
    expect(find.bySemanticsLabel('Quitar adjunto'), findsOneWidget);
    for (final icon in [Icons.refresh_rounded, Icons.close]) {
      final target = find
          .ancestor(
            of: find.byIcon(icon),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.getSize(target), const Size(48, 48));
    }

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.tap(find.byIcon(Icons.close));
    expect(retries, 1);
    expect(removes, 1);
  });
}
