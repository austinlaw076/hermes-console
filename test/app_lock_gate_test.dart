import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/lock_screen.dart';
import 'package:hermes_android/core/services/app_lock.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproducción + regresión del crash `_dependents.isEmpty` del App Lock gate.
///
/// El gate presenta la LockScreen (con un TextField) al bloquear y la retira al
/// desbloquear. Si la presentación usa un Overlay frágil que se desmonta con el
/// EditableText aún registrado como dependiente, salta
/// `InheritedElement.debugDeactivated: _dependents.isEmpty`. Este test monta el
/// gate bloqueado y lo desbloquea: NO debe lanzar excepción.
void main() {
  Future<Widget> buildApp(AppLockService lock) async {
    final navKey = GlobalKey<NavigatorState>();
    return MaterialApp(
      navigatorKey: navKey,
      theme: AppTheme.fromMode(AppThemeMode.dark),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      builder: (context, child) =>
          AppLockGate(lock: lock, navigatorKey: navKey, child: child!),
      home: const Scaffold(body: Center(child: Text('home-content'))),
    );
  }

  testWidgets('desbloquear el gate no lanza _dependents.isEmpty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final prefs = await SharedPreferences.getInstance();
    final lock = AppLockService(prefs);
    expect(lock.locked.value, isTrue);

    await tester.pumpWidget(await buildApp(lock));
    await tester.pumpAndSettle();

    // La pantalla de bloqueo cubre el contenido.
    expect(find.text('HERMES'), findsOneWidget);

    // Desbloquear: el gate debe retirar la pantalla sin crashear.
    lock.unlock();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('HERMES'), findsNothing);
  });

  testWidgets('re-bloquear y desbloquear repetidas veces no rompe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final prefs = await SharedPreferences.getInstance();
    final lock = AppLockService(prefs);

    await tester.pumpWidget(await buildApp(lock));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      lock.unlock();
      await tester.pumpAndSettle();
      lock.lockNow();
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });
}
