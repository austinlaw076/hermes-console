import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/litert_store_screen.dart';
import 'package:hermes_android/core/services/platform/android_apps.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets('LiteRT store renders English copy for the English locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: LitertStoreScreen(
          connection: SavedConnection(
            id: 'test',
            label: 'Test',
            host: '127.0.0.1',
            port: 8642,
            apiKey: '',
          ),
          deviceInfo: DeviceInfo.unknown,
          served: const [],
        ),
      ),
    );

    expect(find.text('GPU model store'), findsOneWidget);
    expect(find.text('Tienda de modelos GPU'), findsNothing);
    expect(find.text('Recommended for most phones'), findsOneWidget);
    expect(
      find.text('More capable; for high-end phones (12 GB+)'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Lightweight; starts on almost any phone'),
      300,
    );
    expect(
      find.text('Lightweight; starts on almost any phone'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Distilled reasoning model'),
      300,
    );
    expect(find.text('Distilled reasoning model'), findsOneWidget);
    expect(find.text('Recomendado para la mayoría de móviles'), findsNothing);
    expect(find.text('Más capaz, para gama alta (12 GB+)'), findsNothing);
    expect(
      find.text('Muy ligero, arranca en casi cualquier móvil'),
      findsNothing,
    );
    expect(find.text('Razonador destilado'), findsNothing);
  });
}
