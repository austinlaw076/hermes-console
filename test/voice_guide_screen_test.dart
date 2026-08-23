import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/voice_guide_screen.dart';
import 'package:hermes_android/core/screens/voice_settings_screen.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets('la pantalla principal no muestra un asistente redundante', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        home: const VoiceSettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Guía paso a paso'), findsNothing);
    expect(find.text('Modo de voz'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice_mode_phone_option')),
      findsOneWidget,
    );
    expect(find.text('Servidor Hermes'), findsNWidgets(2));
    expect(find.text('Dictado del chat'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('voice_reading_section'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('JSON'), findsNothing);
  });

  testWidgets('la guía local también está completa en inglés', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        home: const VoiceGuideScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Two settings, with no hidden steps'), findsOneWidget);
    expect(find.text('Speech to text'), findsOneWidget);
    expect(find.text('Text to speech'), findsOneWidget);
    expect(find.text('3. Test before saving'), findsNothing);
  });
}
