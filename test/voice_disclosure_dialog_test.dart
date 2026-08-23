import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/conversation/voice_consent_store.dart';
import 'package:hermes_android/core/widgets/voice_disclosure_dialog.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<VoiceConsentStore> pumpHost(
    WidgetTester tester, {
    Locale locale = const Locale('es'),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = VoiceConsentStore(prefs);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const ValueKey('open_voice_disclosure'),
              onPressed: () async {
                final choice = await showVoiceDisclosureDialog(context);
                if (choice == null) return;
                await store.acceptDisclosure(
                  continueWhenLocked:
                      choice == VoiceDisclosureChoice.continueWhenLocked,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    return store;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open_voice_disclosure')));
    await tester.pumpAndSettle();
    expect(find.text('Antes de usar el modo voz'), findsOneWidget);
  }

  testWidgets('volver atrás no acepta ni activa continuidad', (tester) async {
    final store = await pumpHost(tester);
    await openDialog(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(store.disclosureAccepted, isFalse);
    expect(store.continueWhenLocked, isFalse);
  });

  testWidgets('solo con la app abierta persiste consentimiento sin bloqueo', (
    tester,
  ) async {
    final store = await pumpHost(tester);
    await openDialog(tester);

    await tester.tap(find.text('Solo con la app abierta'));
    await tester.pumpAndSettle();

    expect(store.disclosureAccepted, isTrue);
    expect(store.continueWhenLocked, isFalse);
  });

  testWidgets('seguir bloqueada persiste el opt-in explícito', (tester) async {
    final store = await pumpHost(tester);
    await openDialog(tester);

    await tester.tap(find.text('Seguir con pantalla bloqueada'));
    await tester.pumpAndSettle();

    expect(store.disclosureAccepted, isTrue);
    expect(store.continueWhenLocked, isTrue);
  });

  testWidgets('el aviso y sus dos elecciones están localizados en inglés', (
    tester,
  ) async {
    final store = await pumpHost(tester, locale: const Locale('en'));

    await tester.tap(find.byKey(const ValueKey('open_voice_disclosure')));
    await tester.pumpAndSettle();

    expect(find.text('Before using voice mode'), findsOneWidget);
    expect(find.text('Only while the app is open'), findsOneWidget);
    expect(find.text('Continue while screen is locked'), findsOneWidget);
    expect(find.text('Antes de usar el modo voz'), findsNothing);

    await tester.tap(find.text('Only while the app is open'));
    await tester.pumpAndSettle();

    expect(store.disclosureAccepted, isTrue);
    expect(store.continueWhenLocked, isFalse);
  });
}
