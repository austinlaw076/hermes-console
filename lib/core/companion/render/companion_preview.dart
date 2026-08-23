import 'package:flutter/material.dart';

import '../../widgets/hermes_spark_mascot.dart';
import '../models/companion.dart';
import '../models/companion_animation_state.dart';
import 'spritesheet_renderer.dart';

/// Render estático de una mascota **concreta** (en estado `idle`), independiente
/// del [CompanionController] y de si la mascota está activada.
///
/// Se usa en la UI de selección (Settings → Apariencia): cada fila muestra SU
/// propia mascota, y `null` representa la opción "Por defecto (Spark)".
class CompanionPreview extends StatelessWidget {
  /// Mascota a previsualizar; `null` → `HermesSparkMascot` (opción por defecto).
  final Companion? companion;
  final double size;
  final Color? accent;

  const CompanionPreview({
    super.key,
    required this.companion,
    this.size = 40,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final companion = this.companion;
    if (companion == null) {
      return HermesSparkMascot(
        mood: HermesSparkMood.idle,
        size: size,
        accent: accent,
      );
    }
    return SpritesheetRenderer(
      companion: companion,
      state: CompanionAnimationState.idle,
      size: size,
      // Un selector puede montar muchas filas. Su contrato es una miniatura
      // estática, no una cuadrícula de timers en segundo plano.
      animate: false,
    );
  }
}
