// Resolución de idioma de la app sin depender de gen-l10n ni de main.dart.
//
// Única fuente de verdad para residuales es/en/zh (notificaciones en isolate,
// voz, hardcodes de UI). Debe coincidir con [AppLocales.resolve] en main.dart.
import 'dart:ui' show Locale, PlatformDispatcher;

/// Misma clave que [AppLocales.prefKey] (`main.dart`). Duplicada a propósito
/// para módulos ligeros / tests sin importar el árbol de la app.
const String kAppLocalePrefKey = 'app_locale';

/// Idiomas con catálogo completo (UI ARB + residuales).
enum AppLocaleKind {
  es,
  en,
  zhHant,
}

/// Resolución de preferencia `app_locale` + locale de dispositivo.
class AppLocaleResolve {
  AppLocaleResolve._();

  static Locale get zhHantLocale =>
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

  /// Desde un [Locale] ya resuelto (p. ej. `Localizations.localeOf`).
  static AppLocaleKind fromLocale(Locale? locale) {
    if (locale == null) return AppLocaleKind.en;
    final lang = locale.languageCode.toLowerCase();
    if (lang == 'es') return AppLocaleKind.es;
    if (lang == 'en') return AppLocaleKind.en;
    if (lang == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final country = locale.countryCode?.toLowerCase();
      if (script == 'hans') return AppLocaleKind.en;
      if (country == 'cn' && script != 'hant') return AppLocaleKind.en;
      if (script == 'hant' ||
          country == 'hk' ||
          country == 'tw' ||
          country == 'mo') {
        return AppLocaleKind.zhHant;
      }
      return AppLocaleKind.en;
    }
    return AppLocaleKind.en;
  }

  /// Desde preferencia guardada (`system` / `es` / `en` / `zh_Hant`).
  static AppLocaleKind fromPrefId(
    String? id, {
    Locale? deviceLocale,
  }) {
    switch (id) {
      case 'es':
        return AppLocaleKind.es;
      case 'en':
        return AppLocaleKind.en;
      case 'zh_Hant':
        return AppLocaleKind.zhHant;
      case 'system':
      case null:
      case '':
        return fromLocale(
          deviceLocale ?? PlatformDispatcher.instance.locale,
        );
      default:
        // Valor desconocido = system.
        return fromLocale(
          deviceLocale ?? PlatformDispatcher.instance.locale,
        );
    }
  }

  static AppLocaleKind fromPrefs(
    // duck-typed: SharedPreferences sin importar el paquete aquí
    dynamic prefs, {
    Locale? deviceLocale,
  }) {
    final id = prefs?.getString(kAppLocalePrefKey) as String?;
    return fromPrefId(id, deviceLocale: deviceLocale);
  }

  static Locale toLocale(AppLocaleKind kind) {
    switch (kind) {
      case AppLocaleKind.es:
        return const Locale('es');
      case AppLocaleKind.en:
        return const Locale('en');
      case AppLocaleKind.zhHant:
        return zhHantLocale;
    }
  }

  /// Elige cadena residual. Si falta [zh], cae a [en] (nunca a es).
  static String pick(
    AppLocaleKind kind, {
    required String es,
    required String en,
    String? zh,
  }) {
    switch (kind) {
      case AppLocaleKind.es:
        return es;
      case AppLocaleKind.en:
        return en;
      case AppLocaleKind.zhHant:
        return zh ?? en;
    }
  }

  static bool isEnglish(Locale? locale) =>
      fromLocale(locale) == AppLocaleKind.en;

  static bool isSpanish(Locale? locale) =>
      fromLocale(locale) == AppLocaleKind.es;

  static bool isZhHant(Locale? locale) =>
      fromLocale(locale) == AppLocaleKind.zhHant;
}
