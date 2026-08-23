import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/platform_setup_commands.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('el emparejado ofrece Unix y PowerShell por separado', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const PlatformSetupCommands(pairing: true)));

    expect(find.text('Linux / Termux / macOS'), findsOneWidget);
    expect(find.text('Windows / WSL2 PowerShell'), findsOneWidget);
    expect(find.textContaining('hermes-pair.sh'), findsOneWidget);
    expect(find.textContaining('hermes-pair.ps1'), findsOneWidget);
    expect(find.textContaining('hermes-mobile-setup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la instalación ofrece ambos artefactos de setup', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const PlatformSetupCommands()));

    expect(find.textContaining('hermes-mobile-setup.sh'), findsOneWidget);
    expect(find.textContaining('hermes-mobile-setup.ps1'), findsOneWidget);
    expect(find.textContaining('hermes-pair'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
