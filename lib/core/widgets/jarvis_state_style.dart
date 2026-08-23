// Estilo visual del núcleo "reactor" del modo voz Jarvis, por fase.
//
// Inspirado en la tabla STATE_STYLE del HUD de Jarvis (eadmin2/jarvis_ai:
// server/hud/index.html), que define por estado: velocidad de giro del anillo,
// color, intensidad de glow y pulso. Aquí lo adaptamos a Hermes Console: los
// colores salen SIEMPRE de los tokens del tema (HermesThemeColors), nunca del
// cian hardcodeado de Jarvis, para integrarse con la estética ámbar y respetar
// todos los temas. Es una capa de PRESENTACIÓN pura sobre [VoicePhase]: no toca
// el motor de voz.
import 'package:flutter/widgets.dart';

import '../services/voice/voice_phase.dart';
import '../theme/app_theme.dart';

/// Parámetros visuales del reactor para una fase concreta del modo voz. Inmutable
/// y puro (derivado de tokens): testeable sin construir UI.
@immutable
class JarvisStateStyle {
  /// Color dominante del anillo y del halo.
  final Color color;

  /// Velocidad de rotación del anillo, en revoluciones por segundo (0 = quieto).
  final double ringSpeed;

  /// Intensidad del halo/glow alrededor del núcleo (0..1).
  final double glow;

  /// Amplitud del pulso del núcleo (0 = estable, 1 = pulso marcado).
  final double pulse;

  /// El núcleo late con el nivel de micrófono (fase de escucha).
  final bool reactsToMic;

  /// El núcleo ondea con el habla del TTS (fase de respuesta hablada).
  final bool reactsToSpeech;

  const JarvisStateStyle({
    required this.color,
    required this.ringSpeed,
    required this.glow,
    required this.pulse,
    this.reactsToMic = false,
    this.reactsToSpeech = false,
  });

  /// Estilo para [phase] con los [colors] del tema activo. Si [isError] (hay un
  /// aviso honesto en el overlay, p.ej. "no te he oído" o fallo de motor), prima
  /// el rojo semántico de error sobre el color de la fase: el usuario debe verlo.
  factory JarvisStateStyle.forPhase(
    VoicePhase phase,
    HermesThemeColors colors, {
    bool isError = false,
  }) {
    if (isError) {
      return JarvisStateStyle(
        color: colors.error,
        ringSpeed: 0.05,
        glow: 0.30,
        pulse: 0,
      );
    }
    switch (phase) {
      case VoicePhase.idle:
        return JarvisStateStyle(
          color: colors.textDisabled,
          ringSpeed: 0.10,
          glow: 0.12,
          pulse: 0,
        );
      case VoicePhase.listening:
        return JarvisStateStyle(
          color: colors.accent,
          ringSpeed: 0.40,
          glow: 0.50,
          pulse: 0.80,
          reactsToMic: true,
        );
      case VoicePhase.transcribing:
        return JarvisStateStyle(
          color: colors.accent,
          ringSpeed: 0.90,
          glow: 0.35,
          pulse: 0.40,
        );
      case VoicePhase.thinking:
        return JarvisStateStyle(
          color: colors.accent,
          ringSpeed: 1.60,
          glow: 0.40,
          pulse: 0.40,
        );
      case VoicePhase.toolCall:
        return JarvisStateStyle(
          color: colors.warning,
          ringSpeed: 2.40,
          glow: 0.50,
          pulse: 0.60,
        );
      case VoicePhase.waitingPermission:
        return JarvisStateStyle(
          color: colors.warning,
          ringSpeed: 0.15,
          glow: 0.30,
          pulse: 0,
        );
      case VoicePhase.speaking:
        return JarvisStateStyle(
          color: colors.success,
          ringSpeed: 0.80,
          glow: 0.45,
          pulse: 0.50,
          reactsToSpeech: true,
        );
    }
  }
}
