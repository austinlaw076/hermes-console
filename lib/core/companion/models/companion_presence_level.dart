/// Nivel de la presencia ambiental del Companion (feature 006).
///
/// - `off`: sin presencia ni reactividad (la mascota mini no aparece y el Home
///   no refleja la actividad de chat).
/// - `minimal`: presencia visible en Home, Mascotas y modo voz. Es el valor por
///   defecto y no invade el transcript de Chat ni otras superficies de trabajo.
/// - `full`: añade indicadores contextuales en Chat/Runs y texto de estado.
enum CompanionPresenceLevel { off, minimal, full }

extension CompanionPresenceLevelX on CompanionPresenceLevel {
  /// Identificador estable para persistencia (== nombre del enum).
  String get id => name;

  /// La presencia es visible (no `off`).
  bool get isVisible => this != CompanionPresenceLevel.off;

  /// La mascota puede sustituir indicadores funcionales fuera de
  /// Home/Mascotas. Solo el nivel completo tiene este alcance.
  bool get showsStatusPresence => this == CompanionPresenceLevel.full;

  /// Muestra texto de estado junto a la mascota.
  bool get showsLabel => this == CompanionPresenceLevel.full;

  /// Etiqueta legible para la UI de ajuste.
  String get label {
    switch (this) {
      case CompanionPresenceLevel.off:
        return 'Apagada';
      case CompanionPresenceLevel.minimal:
        return 'Mínima';
      case CompanionPresenceLevel.full:
        return 'Completa';
    }
  }
}

/// Parse **tolerante** con default seguro: id desconocido/nulo → [fallback]
/// (por defecto `minimal`).
CompanionPresenceLevel companionPresenceLevelFromId(
  String? id, {
  CompanionPresenceLevel fallback = CompanionPresenceLevel.minimal,
}) {
  final key = id?.trim();
  if (key == null || key.isEmpty) return fallback;
  for (final level in CompanionPresenceLevel.values) {
    if (level.name == key) return level;
  }
  return fallback;
}
