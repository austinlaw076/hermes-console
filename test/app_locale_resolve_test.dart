import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/app_locale_resolve.dart';

void main() {
  group('AppLocaleResolve', () {
    test('fromLocale maps es/en/zh variants', () {
      expect(AppLocaleResolve.fromLocale(const Locale('es')), AppLocaleKind.es);
      expect(AppLocaleResolve.fromLocale(const Locale('en')), AppLocaleKind.en);
      expect(
        AppLocaleResolve.fromLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        AppLocaleKind.zhHant,
      );
      expect(
        AppLocaleResolve.fromLocale(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'HK'),
        ),
        AppLocaleKind.zhHant,
      );
      expect(
        AppLocaleResolve.fromLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ),
        AppLocaleKind.en,
      );
      expect(AppLocaleResolve.fromLocale(const Locale('fr')), AppLocaleKind.en);
    });

    test('fromPrefId honors explicit ids', () {
      expect(AppLocaleResolve.fromPrefId('zh_Hant'), AppLocaleKind.zhHant);
      expect(
        AppLocaleResolve.fromPrefId('system', deviceLocale: const Locale('es')),
        AppLocaleKind.es,
      );
      expect(
        AppLocaleResolve.fromPrefId('system', deviceLocale: const Locale('fr')),
        AppLocaleKind.en,
      );
    });

    test('pick prefers zh then en', () {
      expect(
        AppLocaleResolve.pick(
          AppLocaleKind.zhHant,
          es: 'es',
          en: 'en',
          zh: 'zh',
        ),
        'zh',
      );
      expect(
        AppLocaleResolve.pick(AppLocaleKind.zhHant, es: 'es', en: 'en'),
        'en',
      );
    });
  });
}
