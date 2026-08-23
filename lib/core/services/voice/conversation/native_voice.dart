// Modo de voz nativo Desktop (spec 048/US5): capacidad por conexión,
// consentimiento por identidad y ruta autoritativa durante la sesión.
// Contrato público y límites en docs/UPSTREAM_CONTRACT.md.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Estado del consentimiento para enviar el audio de voz al PROPIO servidor.
enum NativeVoiceConsent {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected');

  const NativeVoiceConsent(this.storageKey);
  final String storageKey;

  static NativeVoiceConsent fromStorage(String? value) =>
      NativeVoiceConsent.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => NativeVoiceConsent.pending,
      );
}

/// Motor de conversación elegido explícitamente para una identidad Hermes.
///
/// Esta elección es deliberadamente independiente del consentimiento. Una
/// aceptación antigua solo significa que el usuario permitió enviar audio a
/// ese servidor en su momento; no puede cambiar por sí sola el motor activo.
enum NativeVoiceMode {
  phone('phone'),
  server('server');

  const NativeVoiceMode(this.storageKey);
  final String storageKey;

  static NativeVoiceMode fromStorage(String? value) =>
      NativeVoiceMode.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => NativeVoiceMode.phone,
      );
}

/// Clave estable para aislar Voz por servidor y perfil Hermes efectivo.
///
/// El perfil por defecto conserva la identidad histórica del Dashboard para no
/// invalidar una elección existente. Cualquier perfil nombrado usa un scope
/// propio: aceptar audio o seleccionar servidor en un bot no autoriza a otro.
String nativeVoicePreferenceIdentity(
  String dashboardIdentity, {
  String? profile,
}) {
  final identity = dashboardIdentity.trim();
  final normalizedProfile = profile?.trim() ?? '';
  if (normalizedProfile.isEmpty || normalizedProfile == 'default') {
    return identity;
  }
  return '$identity::profile=${Uri.encodeComponent(normalizedProfile)}';
}

/// Selección versionada por identidad del Dashboard. La ausencia de esta clave
/// nueva siempre cae a [NativeVoiceMode.phone], incluso si existe un
/// `native_voice_consent::* = accepted` de versiones anteriores.
class NativeVoiceModeStore {
  NativeVoiceModeStore(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String identity) => 'native_voice_mode_v1::$identity';

  NativeVoiceMode read(String identity) =>
      NativeVoiceMode.fromStorage(_prefs.getString(_key(identity)));

  Future<void> write(String identity, NativeVoiceMode value) =>
      _prefs.setString(_key(identity), value.storageKey);
}

/// Consentimiento por IDENTIDAD de servidor (URL base del Dashboard). Cambiar
/// host/puerto/esquema produce otra clave, así que el consentimiento no
/// sobrevive a un cambio de servidor (FR-013). Sin `accepted`, ningún byte de
/// audio sale del dispositivo (FR-009).
class NativeVoiceConsentStore {
  NativeVoiceConsentStore(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String identity) => 'native_voice_consent::$identity';

  NativeVoiceConsent read(String identity) =>
      NativeVoiceConsent.fromStorage(_prefs.getString(_key(identity)));

  Future<void> write(String identity, NativeVoiceConsent value) =>
      _prefs.setString(_key(identity), value.storageKey);
}

/// Resultado de la sonda sin efectos sobre `/api/audio/*`.
class NativeVoiceCapability {
  const NativeVoiceCapability({
    required this.transcribe,
    required this.speak,
    required this.checkedAtMs,
    required this.conclusive,
  });

  final bool transcribe;
  final bool speak;
  final int checkedAtMs;

  /// Solo las respuestas que distinguen de verdad existencia (422/400/200 ⇒
  /// existe; 405/404 ⇒ no existe) son concluyentes y cacheables. Un 401 con la
  /// sesión mal, un 5xx o un fallo de red NO deben cachearse como "el servidor
  /// no tiene voz": la siguiente entrada a voz vuelve a sondear.
  final bool conclusive;

  /// Versión del método de sonda. Cambiarla invalida el caché anterior (p.ej.
  /// v1 sondeaba por GET y el catch-all del frontend daba falsos 404).
  static const int probeVersion = 2;

  bool get ok => transcribe && speak;

  Map<String, dynamic> toJson() => {
    'transcribe': transcribe,
    'speak': speak,
    'checked_at_ms': checkedAtMs,
    'conclusive': conclusive,
    'probe_v': probeVersion,
  };

  static NativeVoiceCapability? fromJson(Map<String, dynamic> json) {
    final checked = json['checked_at_ms'];
    if (checked is! int) return null;
    return NativeVoiceCapability(
      transcribe: json['transcribe'] == true,
      speak: json['speak'] == true,
      checkedAtMs: checked,
      // Entradas de versiones de sonda anteriores (o sin campo) se tratan
      // como no concluyentes y se re-sondean (auto-migración del caché).
      conclusive: json['conclusive'] == true && json['probe_v'] == probeVersion,
    );
  }
}

/// Caché por identidad del resultado de la sonda, para no sondear en cada
/// entrada al modo voz. Se refresca cuando caduca ([maxAge]) o al re-detectar
/// capacidades de la conexión.
class NativeVoiceCapabilityStore {
  NativeVoiceCapabilityStore(this._prefs);

  final SharedPreferences _prefs;

  static const Duration maxAge = Duration(hours: 24);

  static String _key(String identity) => 'native_voice_capability::$identity';

  NativeVoiceCapability? read(String identity) {
    final raw = _prefs.getString(_key(identity));
    if (raw == null) return null;
    try {
      return NativeVoiceCapability.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool isFresh(NativeVoiceCapability capability, {DateTime? now}) {
    if (!capability.conclusive) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(capability.checkedAtMs);
    return (now ?? DateTime.now()).difference(at) < maxAge;
  }

  Future<void> write(String identity, NativeVoiceCapability capability) =>
      _prefs.setString(_key(identity), jsonEncode(capability.toJson()));
}

/// Sonda por POST con cuerpo vacío (v2): la validación del endpoint responde
/// 422/400 si la ruta existe (sin efectos) y el router 405/404 si no. El GET
/// estilo Allow no vale aquí: el web server tiene un catch-all GET para el
/// frontend que devuelve 404 para cualquier ruta desconocida. Cualquier error
/// de red o estado inesperado cuenta como "no disponible" sin lanzar jamás.
Future<NativeVoiceCapability> probeNativeVoiceCapability({
  required Future<int> Function(String endpoint) statusOf,
  DateTime Function()? now,
}) async {
  Future<int> status(String endpoint) async {
    try {
      return await statusOf(endpoint);
    } catch (_) {
      return -1;
    }
  }

  bool exists(int code) => code == 422 || code == 400 || code == 200;
  bool definitive(int code) => exists(code) || code == 404 || code == 405;

  final speakStatus = await status('speak');
  // Sin síntesis no hay modo nativo completo; ahorra la segunda petición.
  final transcribeStatus = exists(speakStatus)
      ? await status('transcribe')
      : speakStatus;
  return NativeVoiceCapability(
    transcribe: exists(transcribeStatus),
    speak: exists(speakStatus),
    checkedAtMs: (now?.call() ?? DateTime.now()).millisecondsSinceEpoch,
    conclusive: definitive(speakStatus) && definitive(transcribeStatus),
  );
}

/// Sonda únicamente el contrato de Dictado oficial. A diferencia de Modo Voz,
/// no requiere `/api/audio/speak`: elegir voz local y dictado Hermes es una
/// combinación válida e independiente.
Future<bool> probeHermesTranscription({
  required Future<int> Function(String endpoint) statusOf,
}) async {
  try {
    final code = await statusOf('transcribe');
    return code == 200 || code == 400 || code == 422;
  } catch (_) {
    return false;
  }
}

/// Estado efímero de una sesión de voz en Hermes.
///
/// La selección de ruta es autoritativa: un fallo del servidor se contabiliza
/// para diagnóstico, pero nunca cambia por sí solo a los motores del teléfono.
/// Solo una elección explícita del usuario o el cierre de la sesión desactiva
/// esta ruta.
class NativeVoiceSession {
  int _failures = 0;

  bool get active => true;

  int get consecutiveFailures => _failures;

  void noteSuccess() => _failures = 0;

  void noteFailure() => _failures++;
}
