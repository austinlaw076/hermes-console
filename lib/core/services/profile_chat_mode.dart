// Decisión de CÓMO se aplica un perfil de agente en el chat, según la capacidad
// de la instancia. Lógica PURA (sin I/O) para poder testearla a fondo; la
// obtención de los flags (presencia/versión del bridge, SOUL legible) vive en la
// capa de servicio que la invoca.
//
// Principio: nunca romper. Si nada aplica, `none` = comportamiento actual del
// chat (camino default por gateway/bridge sin aislamiento).

/// Cómo se aplica el perfil activo a un turno de chat.
///
///  • [full]        — aislamiento completo: el turno corre en el home del perfil
///                    (SOUL+skills+memoria+modelo). Requiere bridge con soporte
///                    de perfil (`hermes --profile`).
///  • [personality] — degradación: se inyecta el SOUL del perfil como contexto
///                    de sistema; skills/memoria siguen siendo del default.
///  • [none]        — sin aislamiento: camino actual idéntico (perfil default,
///                    nombre inválido, o ninguna capacidad disponible).
enum ProfileChatMode { full, personality, none }

/// Valida el NOMBRE de un perfil antes de usarlo en cualquier ruta/ejecución.
/// Lista blanca estricta (coincide con la validación de la UI de creación):
/// minúsculas, dígitos, guion y guion bajo; primer carácter alfanumérico; hasta
/// 64 chars. Rechaza vacío, rutas (`/`, `\`), `..` y cualquier intento de path
/// traversal. `default` es un nombre válido (aunque no requiera routing especial).
bool isValidProfileName(String name) {
  final n = name.trim();
  if (n.isEmpty || n.length > 64) return false;
  // Defensa explícita anti path-traversal además de la lista blanca.
  if (n.contains('..') || n.contains('/') || n.contains('\\')) return false;
  return RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(n);
}

/// ¿El perfil indica un agente NO-default que merece routing especial?
/// Vacío o `default` → no (camino actual).
bool profileRoutes(String profile) {
  final p = profile.trim();
  return p.isNotEmpty && p != 'default' && isValidProfileName(p);
}

/// Decide el modo de aplicación del perfil a partir de la capacidad observada.
///
/// - [profile]: perfil activo de contexto (vacío/`default` = sin perfil).
/// - [bridgeAvailable]: hay un Mobile Bridge alcanzable en la instancia.
/// - [bridgeSupportsProfile]: la versión del bridge entiende el campo `profile`
///   (ejecuta `hermes --profile`). Un bridge antiguo → false.
/// - [soulAvailable]: el SOUL del perfil es legible (para el modo personalidad).
ProfileChatMode resolveProfileChatMode({
  required String profile,
  required bool bridgeAvailable,
  required bool bridgeSupportsProfile,
  required bool soulAvailable,
}) {
  if (!profileRoutes(profile)) return ProfileChatMode.none;
  if (bridgeAvailable && bridgeSupportsProfile) return ProfileChatMode.full;
  if (soulAvailable) return ProfileChatMode.personality;
  return ProfileChatMode.none;
}
