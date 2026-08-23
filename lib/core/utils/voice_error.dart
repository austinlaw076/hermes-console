import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../services/connection_manager.dart';
import '../services/voice/tts_engine.dart';

/// Traduce errores conocidos de voz sin exponer `toString()` técnico ni copy
/// fijado dentro de servicios.
String localizedVoiceError(Strings strings, Object error) {
  if (error is TimeoutException) return strings.voiceErrorPreviewTimeout;
  if (error is TtsUserException) {
    return switch (error.code) {
      TtsUserError.invalidKokoroAddress =>
        strings.voiceErrorInvalidKokoroAddress,
      TtsUserError.invalidKokoroPort => strings.voiceErrorInvalidKokoroPort,
      TtsUserError.kokoroUnavailable => strings.voiceErrorKokoroUnavailable,
      TtsUserError.kokoroNoVoices => strings.voiceErrorKokoroNoVoices,
      TtsUserError.invalidAudio => strings.voiceErrorInvalidAudio,
      TtsUserError.invalidCustomConfiguration =>
        strings.voiceCustomInvalidConfiguration,
      TtsUserError.customResponseMissingAudio =>
        strings.voiceErrorCustomResponseMissingAudio,
      TtsUserError.customHttpFailure => strings.voiceErrorCustomHttpFailure(
        error.statusCode?.toString() ?? '—',
      ),
    };
  }
  if (error is DashboardAuthException &&
      error.code == DashboardAuthFailureCode.loginRequired) {
    return strings.voiceErrorDashboardLogin;
  }
  if (error is StateError) return strings.voiceErrorUnavailable;
  return strings.voiceErrorUnexpected;
}
