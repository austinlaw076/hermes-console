// Idioma de voz efectivo (spec 031): único punto de verdad que decide en qué
// idioma trabajan dictado (Whisper/reconocedor del sistema), lectura en voz
// alta y defaults de voz. Deriva SIEMPRE del ajuste de idioma de la app
// (`app_locale`) — no existe un selector de idioma de voz separado.
//
// Replica la resolución de la UI ([AppLocaleResolve]): es/en/zh_Hant
// explícitos se respetan; system sigue al dispositivo; no soportado → en.
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_locale_resolve.dart';

export '../../l10n/app_locale_resolve.dart' show kAppLocalePrefKey;

/// Idioma de voz efectivo: `'es'`, `'en'` o `'zh'` (繁中 UI → motor zh).
///
/// - `app_locale == 'es' | 'en' | 'zh_Hant'` → código de motor correspondiente.
/// - `'system'`, clave ausente o valor desconocido → según dispositivo
///   (misma matriz que [AppLocaleResolve.fromLocale]).
///
/// [deviceLocale] existe solo para tests; en producción se usa el locale real.
String effectiveVoiceLang(SharedPreferences prefs, {Locale? deviceLocale}) {
  final kind = AppLocaleResolve.fromPrefId(
    prefs.getString(kAppLocalePrefKey),
    deviceLocale: deviceLocale ?? PlatformDispatcher.instance.locale,
  );
  switch (kind) {
    case AppLocaleKind.es:
      return 'es';
    case AppLocaleKind.en:
      return 'en';
    case AppLocaleKind.zhHant:
      return 'zh';
  }
}
