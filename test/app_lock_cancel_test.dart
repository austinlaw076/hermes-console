import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/lock_screen.dart';
import 'package:hermes_android/core/services/app_lock.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'cancelar la verificación de App Lock devuelve false sin crashear',
    (tester) async {
      // Bloqueo activo (sin biometría) para que verify() presente la pantalla.
      SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
      final prefs = await SharedPreferences.getInstance();
      final lock = AppLockService(prefs);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromMode(AppThemeMode.dark),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
          locale: const Locale('es'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await LockScreen.verify(
                      context,
                      lock,
                      reason: 'test',
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // La pantalla de bloqueo está visible con el campo PIN enfocado.
      expect(find.text('Cancelar'), findsOneWidget);

      // Cancelar con el campo enfocado: no debe lanzar _dependents.isEmpty.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
