import 'companion_animation_state.dart';

/// Origen de una mascota (Fase B / US4 + Hatch).
///
/// - [base]: mascota empaquetada con la app (assets). **No borrable**.
/// - [imported]: mascota traída por el usuario desde un ZIP local. Vive en el
///   sandbox de la app; borrable.
/// - [generated]: mascota creada con "Hatch" (generación de imagen estática).
///   Vive en el sandbox como las importadas; es **estática** (solo `idle`,
///   1 frame) y borrable. Se etiqueta en UI como "Mascota estática generada".
enum CompanionOrigin { base, imported, generated, remote }

/// Convierte un identificador de origen (campo opcional `origin` de un
/// `pet.json` del sandbox) al enum, o `null` si no corresponde. Lo usa el
/// parser para distinguir una mascota `generated` (Hatch) de una `imported`
/// cuando ambas viven en el mismo directorio del sandbox.
CompanionOrigin? companionOriginFromId(String? id) {
  switch (id?.trim()) {
    case 'base':
      return CompanionOrigin.base;
    case 'imported':
      return CompanionOrigin.imported;
    case 'generated':
      return CompanionOrigin.generated;
    case 'remote':
      return CompanionOrigin.remote;
    default:
      return null;
  }
}

/// Especificación de una fila de animación dentro del spritesheet.
class RowSpec {
  /// Fila del grid (0-based).
  final int row;

  /// Número de frames de la animación (<= columnas del grid).
  final int frameCount;

  /// Si la animación cicla (idle/run/waiting) o se reproduce una vez.
  final bool loop;

  /// Nombre legible opcional para animaciones EXTRA (sin estado nombrado).
  /// Si el `pet.json` lo declara (`name`/`label`), el probador lo muestra; si
  /// no, el probador usa un genérico "Extra N".
  final String? label;

  const RowSpec({
    required this.row,
    required this.frameCount,
    required this.loop,
    this.label,
  });

  /// Copia con `loop` forzado (lo usa el probador para reproducir en bucle una
  /// animación que por defecto es one-shot, sin mutar la fila original).
  RowSpec copyWith({bool? loop}) => RowSpec(
    row: row,
    frameCount: frameCount,
    loop: loop ?? this.loop,
    label: label,
  );
}

/// Mascota cosmética "Companion" cargada desde un `pet.json` (formato Petdex).
///
/// Es una entidad puramente visual: no afecta a tokens, prompt caching ni al
/// comportamiento del agente (FR-010).
class Companion {
  final String slug;
  final String name;
  final String author;
  final String license;

  /// Ruta al spritesheet. Para mascotas [CompanionOrigin.base] es una clave de
  /// asset (p. ej. `assets/companions/<slug>/spritesheet.webp`); para
  /// [CompanionOrigin.imported] es una **ruta absoluta de fichero** en el
  /// almacenamiento de la app. El renderer elige `AssetImage`/`FileImage` según
  /// [isImported].
  final String spritesheetAsset;

  final int frameWidth;
  final int frameHeight;
  final int cols;
  final int rows;
  final double fps;

  final Map<CompanionAnimationState, RowSpec> states;

  /// Filas de animación ADICIONALES sin un estado nombrado (p. ej. las
  /// animaciones extra que traen las mascotas de Petdex más allá de
  /// idle/run/waiting/wave/failed). El mascota del Home no las usa, pero el
  /// probador de la pantalla Mascotas sí puede reproducirlas.
  final List<RowSpec> extraRows;

  /// Origen de la mascota. Las cargadas de assets son [CompanionOrigin.base]
  /// (default), por lo que están protegidas frente al borrado.
  final CompanionOrigin origin;

  const Companion({
    required this.slug,
    required this.name,
    required this.author,
    required this.license,
    required this.spritesheetAsset,
    required this.frameWidth,
    required this.frameHeight,
    required this.cols,
    required this.rows,
    required this.fps,
    required this.states,
    this.extraRows = const [],
    this.origin = CompanionOrigin.base,
  });

  /// Devuelve la [RowSpec] de un estado, con fallback a `idle` si ese estado no
  /// está definido en la mascota.
  RowSpec? rowFor(CompanionAnimationState state) =>
      states[state] ?? states[CompanionAnimationState.idle];

  /// Una mascota es válida si al menos define el estado `idle`.
  bool get isValid => states.containsKey(CompanionAnimationState.idle);

  /// Mascota protegida (no borrable). Las base nunca pueden eliminarse.
  bool get isProtected =>
      origin == CompanionOrigin.base || origin == CompanionOrigin.remote;

  /// Mascota importada por el usuario (su spritesheet vive en un fichero del
  /// sandbox de la app, no en assets).
  bool get isImported => origin == CompanionOrigin.imported;

  /// Mascota generada con "Hatch" (estática). También vive como fichero en el
  /// sandbox, igual que las importadas; el render usa `FileImage`.
  bool get isGenerated => origin == CompanionOrigin.generated;

  /// Mascota oficial materializada desde `pet.info`. Vive en caché privada,
  /// está scopeada por conexión/perfil/revisión y no es borrable desde la
  /// galería de importaciones del usuario.
  bool get isRemote => origin == CompanionOrigin.remote;

  /// Vive como fichero en el sandbox (no es asset empaquetado): importadas y
  /// generadas. Lo usan el render (FileImage) y el borrado de ficheros.
  bool get isFileBacked => isImported || isGenerated || isRemote;
}
