// Render fiel del JarvisReactorCore (widget real) para inspección visual sin
// depender del emulador. Genera goldens con: flutter test --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/voice_phase.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/jarvis_reactor_core.dart';
import 'package:hermes_android/core/widgets/jarvis_state_style.dart';

void main() {
  const colors = HermesThemeColors(
    background: Color(0xFF0D0D0D),
    surface: Color(0xFF161616),
    surfaceVariant: Color(0xFF222222),
    accent: Color(0xFFE8821C),
    accentHover: Color(0xFFF0A848),
    onAccent: Color(0xFF0D0D0D),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFAAAAAA),
    textDisabled: Color(0xFF555555),
    error: Color(0xFFFF4D5E),
    success: Color(0xFF35D07F),
    warning: Color(0xFFFFB300),
    divider: Color(0xFF333333),
  );

  Widget tile(String label, VoicePhase phase, double mic, {bool err = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 007-voice-jarvis-fluid: el reactor del modo voz se renderiza SIN
        // mascota dentro — solo la esfera Jarvis.
        JarvisReactorCore(
          style: JarvisStateStyle.forPhase(phase, colors, isError: err),
          micLevel: mic,
          size: 200,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
        ),
      ],
    );
  }

  testWidgets('reactor: render por fases', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 950));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: colors.background,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: GridView.count(
              crossAxisCount: 2,
              children: [
                tile('listening (mic 0.7)', VoicePhase.listening, 0.7),
                tile('thinking', VoicePhase.thinking, 0),
                tile('speaking', VoicePhase.speaking, 0),
                tile('error', VoicePhase.idle, 0, err: true),
              ],
            ),
          ),
        ),
      ),
    );
    // Avanza la animación a un fotograma concreto y estable.
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(GridView),
      matchesGoldenFile('goldens/jarvis_reactor_phases.png'),
    );
  });
}
