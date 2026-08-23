import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/navigation/instance_route_guard.dart';
import 'package:hermes_android/core/screens/appearance_screen.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final _connection = SavedConnection(
  id: 'appearance-guard-test',
  label: 'Hermes QA',
  host: '192.168.1.20',
  port: 8642,
  apiKey: 'test-only',
);

Widget _host({
  required SavedConnection? connection,
  required VoidCallback built,
}) {
  return MaterialApp(
    locale: const Locale('es'),
    theme: AppTheme.fromId('dark'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-gated-route'),
            onPressed: () {
              InstanceRouteGuard.push<void>(
                context,
                connection: connection,
                builder: (active) {
                  built();
                  return AppearanceScreen(connection: active);
                },
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sin instancia explica el bloqueo y no añade una ruta', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(_host(connection: null, built: () => builds += 1));

    await tester.tap(find.byKey(const ValueKey('open-gated-route')));
    await tester.pump();

    expect(builds, 0);
    expect(find.byType(AppearanceScreen), findsNothing);
    expect(find.text('Configura una instancia primero'), findsOneWidget);
  });

  testWidgets('con instancia pasa el objeto real a AppearanceScreen', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      _host(connection: _connection, built: () => builds += 1),
    );

    await tester.tap(find.byKey(const ValueKey('open-gated-route')));
    await tester.pumpAndSettle();

    expect(builds, 1);
    expect(find.byType(AppearanceScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appearance-current-preview')),
      findsOneWidget,
    );
    expect(find.textContaining('Hermes QA'), findsOneWidget);
    final screen = tester.widget<AppearanceScreen>(
      find.byType(AppearanceScreen),
    );
    expect(identical(screen.connection, _connection), isTrue);
  });
}
