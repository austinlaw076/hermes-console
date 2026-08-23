/// Modelos del contrato nativo de mascotas por perfil de Hermes Agent
/// (RPCs `pet.*` del Gateway; referencia upstream:
/// `tui_gateway/methods_session.py`). Las mascotas viven en la config del
/// perfil (`display.pet.*`) y se instalan bajo el `pets/` de ese perfil.
library;

/// Mascota activa de un perfil según el Gateway (`pet.info`).
///
/// Upstream es fail-open: ante cualquier problema interno devuelve
/// `{enabled: false}` en vez de un error, así que el parse es tolerante y
/// cualquier respuesta sin `enabled: true` + slug se trata como "sin mascota".
class ProfilePetInfo {
  final bool enabled;
  final String slug;
  final String displayName;
  final String mime;
  final String? spritesheetBase64;
  final String spritesheetRevision;
  final bool spritesheetUnchanged;
  final int? frameW;
  final int? frameH;
  final int? framesPerState;
  final Map<String, int> framesByState;
  final Map<String, int> framesByRow;
  final int? loopMs;
  final double? scale;
  final List<String> stateRows;

  const ProfilePetInfo({
    required this.enabled,
    this.slug = '',
    this.displayName = '',
    this.mime = '',
    this.spritesheetBase64,
    this.spritesheetRevision = '',
    this.spritesheetUnchanged = false,
    this.frameW,
    this.frameH,
    this.framesPerState,
    this.framesByState = const {},
    this.framesByRow = const {},
    this.loopMs,
    this.scale,
    this.stateRows = const [],
  });

  static const ProfilePetInfo disabled = ProfilePetInfo(enabled: false);

  /// `true` solo cuando el perfil tiene una mascota activa en el servidor.
  bool get hasPet => enabled && slug.isNotEmpty;

  bool get usesCachedSpritesheet =>
      spritesheetUnchanged && spritesheetRevision.isNotEmpty;

  bool get hasSpritesheetPayload =>
      spritesheetBase64 != null &&
      spritesheetBase64!.isNotEmpty &&
      spritesheetRevision.isNotEmpty;

  factory ProfilePetInfo.fromJson(Map<String, dynamic> json) {
    if (json['enabled'] != true) return disabled;
    final slug = (json['slug'] ?? '').toString().trim();
    if (slug.isEmpty) return disabled;
    return ProfilePetInfo(
      enabled: true,
      slug: slug,
      displayName: (json['displayName'] ?? '').toString(),
      mime: _string(json['mime']),
      spritesheetBase64: json['spritesheetBase64'] is String
          ? json['spritesheetBase64'] as String
          : null,
      spritesheetRevision: _string(json['spritesheetRevision']),
      spritesheetUnchanged: json['spritesheetUnchanged'] == true,
      frameW: _positiveInt(json['frameW']),
      frameH: _positiveInt(json['frameH']),
      framesPerState: _positiveInt(json['framesPerState']),
      framesByState: _intMap(json['framesByState']),
      framesByRow: _intMap(json['framesByRow']),
      loopMs: _positiveInt(json['loopMs']),
      scale: (json['scale'] as num?)?.toDouble(),
      stateRows: _stringList(json['stateRows']),
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static int? _positiveInt(Object? value) {
    if (value is! num) return null;
    final parsed = value.toInt();
    return parsed > 0 ? parsed : null;
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    final parsed = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final count = _positiveInt(entry.value);
      if (key.isNotEmpty && count != null) parsed[key] = count;
    }
    return Map.unmodifiable(parsed);
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return List.unmodifiable(
      value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }
}

/// Entrada de la galería de mascotas de un perfil (`pet.gallery`).
class ProfilePetGalleryEntry {
  final String slug;
  final String displayName;
  final bool installed;
  final bool generated;
  final String spritesheetUrl;

  const ProfilePetGalleryEntry({
    required this.slug,
    required this.displayName,
    this.installed = false,
    this.generated = false,
    this.spritesheetUrl = '',
  });

  /// Entradas malformadas se descartan (devuelve `null`), igual que el parser
  /// del manifest Petdex: no rompen la lista.
  static ProfilePetGalleryEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = (raw['slug'] ?? '').toString().trim();
    if (slug.isEmpty) return null;
    return ProfilePetGalleryEntry(
      slug: slug,
      displayName: (raw['displayName'] ?? '').toString(),
      installed: raw['installed'] == true,
      generated: raw['generated'] == true,
      spritesheetUrl: (raw['spritesheetUrl'] ?? '').toString(),
    );
  }
}

/// Galería de mascotas adoptables de un perfil (`pet.gallery`): estado de la
/// config (`enabled`/`active`) más la lista mezclada petdex + instaladas.
class ProfilePetGallery {
  final bool enabled;

  /// Slug activo en la config del perfil ('' si no hay ninguna).
  final String active;
  final List<ProfilePetGalleryEntry> pets;

  const ProfilePetGallery({
    required this.enabled,
    required this.active,
    required this.pets,
  });

  factory ProfilePetGallery.fromJson(Map<String, dynamic> json) {
    final rawPets = json['pets'];
    final pets = <ProfilePetGalleryEntry>[
      if (rawPets is List)
        for (final raw in rawPets) ?ProfilePetGalleryEntry.tryFromJson(raw),
    ];
    return ProfilePetGallery(
      enabled: json['enabled'] == true,
      active: (json['active'] ?? '').toString(),
      pets: List.unmodifiable(pets),
    );
  }
}

/// Confirmación de una adopción (`pet.select`).
class ProfilePetSelection {
  final String slug;
  final String displayName;

  const ProfilePetSelection({required this.slug, this.displayName = ''});
}
