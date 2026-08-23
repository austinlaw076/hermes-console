/// Límites compartidos para los ajustes visuales del Companion.
///
/// Mantenerlos en un único lugar evita que la UI, la persistencia y el
/// renderer acepten rangos distintos.
abstract final class CompanionDisplaySettings {
  static const double minSizeMultiplier = 0.70;
  static const double maxSizeMultiplier = 1.40;
  static const double defaultSizeMultiplier = 1.0;

  static const double minAnimationSpeed = 0.50;
  static const double maxAnimationSpeed = 1.50;
  static const double defaultAnimationSpeed = 1.0;

  static double clampSizeMultiplier(num value) {
    return value
        .toDouble()
        .clamp(minSizeMultiplier, maxSizeMultiplier)
        .toDouble();
  }

  static double clampAnimationSpeed(num value) {
    return value
        .toDouble()
        .clamp(minAnimationSpeed, maxAnimationSpeed)
        .toDouble();
  }
}
