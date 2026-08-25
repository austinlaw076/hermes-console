// Matriz de derivación del idioma de voz efectivo.
// El locale del dispositivo se inyecta con `deviceLocale:` para no depender del host.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/voice/voice_lang.dart';
import 'package:hermes_android/main.dart' show AppLocales;

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  const en = Locale('en', 'US');
  const es = Locale('es', 'ES');
  const fr = Locale('fr', 'FR');
  final zhHant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  final zhHk = Locale.fromSubtags(languageCode: 'zh', countryCode: 'HK');

  group('effectiveVoiceLang', () {
    test('es/en/zh_Hant explícitos mandan', () async {
      final prefsEs = await _prefs({kAppLocalePrefKey: 'es'});
      expect(effectiveVoiceLang(prefsEs, deviceLocale: en), 'es');
      expect(effectiveVoiceLang(prefsEs, deviceLocale: fr), 'es');

      final prefsEn = await _prefs({kAppLocalePrefKey: 'en'});
      expect(effectiveVoiceLang(prefsEn, deviceLocale: es), 'en');
      expect(effectiveVoiceLang(prefsEn, deviceLocale: fr), 'en');

      final prefsZh = await _prefs({kAppLocalePrefKey: 'zh_Hant'});
      expect(effectiveVoiceLang(prefsZh, deviceLocale: en), 'zh');
      expect(effectiveVoiceLang(prefsZh, deviceLocale: es), 'zh');
    });

    test('system sigue al dispositivo: en/es/zh', () async {
      final prefs = await _prefs({kAppLocalePrefKey: 'system'});
      expect(effectiveVoiceLang(prefs, deviceLocale: en), 'en');
      expect(effectiveVoiceLang(prefs, deviceLocale: es), 'es');
      expect(effectiveVoiceLang(prefs, deviceLocale: zhHant), 'zh');
      expect(effectiveVoiceLang(prefs, deviceLocale: zhHk), 'zh');
      expect(
        effectiveVoiceLang(prefs, deviceLocale: const Locale('en', 'GB')),
        'en',
      );
    });

    test('system con idioma no soportado cae a inglés (como la UI)', () async {
      final prefs = await _prefs({kAppLocalePrefKey: 'system'});
      expect(effectiveVoiceLang(prefs, deviceLocale: fr), 'en');
      expect(
        effectiveVoiceLang(prefs, deviceLocale: const Locale('de', 'DE')),
        'en',
      );
    });

    test('clave ausente o valor desconocido se tratan como system', () async {
      final ausente = await _prefs({});
      expect(effectiveVoiceLang(ausente, deviceLocale: en), 'en');
      expect(effectiveVoiceLang(ausente, deviceLocale: fr), 'en');

      final raro = await _prefs({kAppLocalePrefKey: 'xx'});
      expect(effectiveVoiceLang(raro, deviceLocale: en), 'en');
      expect(effectiveVoiceLang(raro, deviceLocale: es), 'es');
    });

    test('la clave duplicada no diverge de AppLocales.prefKey', () {
      expect(kAppLocalePrefKey, AppLocales.prefKey);
    });
  });
}
