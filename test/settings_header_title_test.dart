import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/app_header_title.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  tearDown(() {
    headerTitleNotifier.value = kDefaultHeaderTitle;
  });

  testWidgets('Ajustes y la cabecera comparten siempre el mismo título', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kHeaderTitlePrefKey: 'HERMES CONSOLE Q',
    });
    final prefs = await SharedPreferences.getInstance();
    final manager = await ConnectionManager.create(prefs);
    final connection = SavedConnection(
      id: 'qa',
      label: 'QA',
      host: '192.168.1.20',
      port: 8642,
      apiKey: '',
      dashboardUrl: 'http://192.168.1.20:9119',
    );
    loadHeaderTitle(prefs);

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

    await tester.scrollUntilVisible(
      find.text('HERMES CONSOLE Q'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('HERMES CONSOLE Q'), findsOneWidget);

    await setHeaderTitle(prefs, 'SERVER');
    await tester.pump();

    expect(find.text('SERVER'), findsOneWidget);
    expect(find.text('HERMES CONSOLE Q'), findsNothing);
  });
}
