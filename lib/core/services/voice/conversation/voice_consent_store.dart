import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias no secretas que separan el aviso de primer uso de la decisión
/// de mantener una conversación activa con la pantalla bloqueada.
///
/// La continuidad parte siempre apagada. Guardar una preferencia desde Ajustes
/// no equivale por sí solo a aceptar el aviso: el consentimiento se confirma
/// únicamente mediante [acceptDisclosure].
class VoiceConsentStore extends ChangeNotifier {
  static const String disclosureAcceptedKey =
      'voice_conversation_disclosure_accepted_v1';
  static const String continueWhenLockedKey =
      'voice_conversation_continue_when_locked';
  static const String conversationEnabledKey = 'voice_conversation_enabled';

  final SharedPreferences _prefs;
  bool _disclosureAccepted;
  bool _continueWhenLocked;
  bool _conversationEnabled;

  VoiceConsentStore(this._prefs)
    : _disclosureAccepted = _prefs.getBool(disclosureAcceptedKey) ?? false,
      _continueWhenLocked = _prefs.getBool(continueWhenLockedKey) ?? false,
      _conversationEnabled = _prefs.getBool(conversationEnabledKey) ?? true;

  bool get disclosureAccepted => _disclosureAccepted;
  bool get continueWhenLocked => _continueWhenLocked;
  bool get conversationEnabled => _conversationEnabled;

  /// Persiste primero el alcance elegido y, solo después, marca el aviso como
  /// aceptado. Así un cierre entre ambas escrituras nunca deja consentimiento
  /// afirmativo sin una elección completa.
  Future<void> acceptDisclosure({required bool continueWhenLocked}) async {
    final changed =
        !_disclosureAccepted || _continueWhenLocked != continueWhenLocked;
    await _prefs.setBool(continueWhenLockedKey, continueWhenLocked);
    await _prefs.setBool(disclosureAcceptedKey, true);
    _continueWhenLocked = continueWhenLocked;
    _disclosureAccepted = true;
    if (changed) notifyListeners();
  }

  /// Cambia únicamente la continuidad. La UI sigue siendo responsable de
  /// mostrar y aceptar el aviso antes de activar el modo voz por primera vez.
  Future<void> setContinueWhenLocked(bool value) async {
    if (_continueWhenLocked == value) return;
    await _prefs.setBool(continueWhenLockedKey, value);
    _continueWhenLocked = value;
    notifyListeners();
  }

  /// Oculta/activa únicamente la conversación con orbe. Dictado, lectura de
  /// burbujas y TTS automático no consultan esta preferencia.
  Future<void> setConversationEnabled(bool value) async {
    if (_conversationEnabled == value) return;
    await _prefs.setBool(conversationEnabledKey, value);
    _conversationEnabled = value;
    notifyListeners();
  }
}
