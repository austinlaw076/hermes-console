import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/voice_phase.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/jarvis_reactor_core.dart';
import 'package:hermes_android/core/widgets/jarvis_state_style.dart';

void main() {
  const colors = HermesThemeColors(
    background: Color(0xFF000000),
    surface: Color(0xFF111111),
    surfaceVariant: Color(0xFF222222),
    accent: Color(0xFFE8821C),
    accentHover: Color(0xFFF0A848),
    onAccent: Color(0xFF0D0D0D),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFAAAAAA),
    textDisabled: Color(0xFF555555),
    error: Color(0xFFFF4D5E),
    success: Color(0xFF2ECC71),
    warning: Color(0xFFFFB300),
    divider: Color(0xFF333333),
  );

  Widget host(VoicePhase phase, double mic) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: JarvisReactorCore(
          style: JarvisStateStyle.forPhase(phase, colors),
          micLevel: mic,
          child: const Text('spark'),
        ),
      ),
    ),
  );

  testWidgets('renderiza el hijo central y se anima sin lanzar', (
    tester,
  ) async {
    await tester.pumpWidget(host(VoicePhase.listening, 0.6));
    expect(find.text('spark'), findsOneWidget);
    // Avanza varios frames de la animación: no debe lanzar.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar de fase reconstruye sin lanzar', (tester) async {
    await tester.pumpWidget(host(VoicePhase.thinking, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(host(VoicePhase.speaking, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('spark'), findsOneWidget);
  });
}
