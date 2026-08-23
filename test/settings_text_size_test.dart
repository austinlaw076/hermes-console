import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  testWidgets('Ajustes no ofrece un control que rompa la densidad fija', (
    tester,
  ) async {
    final manager = await ConnectionManager.create(
      await SharedPreferences.getInstance(),
    );
    final connection = SavedConnection(
      id: 'text-size-qa',
      label: 'QA',
      host: '127.0.0.1',
      port: 8642,
      apiKey: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: AppTheme.fromId('dark'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: SettingsScreen(connection: connection, connManager: manager),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('text-size-slider')), findsNothing);
    expect(find.text('Tamaño de texto'), findsNothing);
  });
}
