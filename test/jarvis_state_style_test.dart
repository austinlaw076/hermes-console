import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/voice_phase.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/jarvis_state_style.dart';

void main() {
  // Tokens de prueba con colores bien distintos para verificar el mapeo sin
  // depender del tema real.
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

  group('JarvisStateStyle.forPhase', () {
    test('escucha usa el acento y reacciona al micrófono', () {
      final s = JarvisStateStyle.forPhase(VoicePhase.listening, colors);
      expect(s.color, colors.accent);
      expect(s.reactsToMic, isTrue);
      expect(s.reactsToSpeech, isFalse);
      expect(s.pulse, greaterThan(0));
    });

    test('hablar usa success y reacciona al habla', () {
      final s = JarvisStateStyle.forPhase(VoicePhase.speaking, colors);
      expect(s.color, colors.success);
      expect(s.reactsToSpeech, isTrue);
      expect(s.reactsToMic, isFalse);
    });

    test('herramienta y espera de permiso usan el color de aviso', () {
      expect(
        JarvisStateStyle.forPhase(VoicePhase.toolCall, colors).color,
        colors.warning,
      );
      expect(
        JarvisStateStyle.forPhase(VoicePhase.waitingPermission, colors).color,
        colors.warning,
      );
    });

    test('idle es tenue, sin pulso ni reactividad', () {
      final s = JarvisStateStyle.forPhase(VoicePhase.idle, colors);
      expect(s.color, colors.textDisabled);
      expect(s.pulse, 0);
      expect(s.reactsToMic, isFalse);
      expect(s.reactsToSpeech, isFalse);
    });

    test('isError prima el rojo de error sobre el color de la fase', () {
      // Incluso en una fase que normalmente es ámbar, el aviso fuerza rojo.
      final s = JarvisStateStyle.forPhase(
        VoicePhase.thinking,
        colors,
        isError: true,
      );
      expect(s.color, colors.error);
      expect(s.pulse, 0);
    });

    test('la velocidad del anillo crece de pensar a herramienta', () {
      final thinking = JarvisStateStyle.forPhase(VoicePhase.thinking, colors);
      final tool = JarvisStateStyle.forPhase(VoicePhase.toolCall, colors);
      expect(tool.ringSpeed, greaterThan(thinking.ringSpeed));
    });

    test('cubre todas las fases sin lanzar', () {
      for (final p in VoicePhase.values) {
        expect(() => JarvisStateStyle.forPhase(p, colors), returnsNormally);
      }
    });
  });
}
