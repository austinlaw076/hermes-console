import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/main.dart';

void main() {
  group('AppLocales', () {
    test('public supported locales are exactly es, en, and zh_Hant', () {
      expect(AppLocales.supportedLocales, const [
        Locale('es'),
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]);
    });

    test('catalog includes zh_Hant with Hant script', () {
      final opt = AppLocales.byId('zh_Hant');
      expect(opt.id, 'zh_Hant');
      expect(opt.label, '繁體中文');
      expect(opt.locale?.languageCode, 'zh');
      expect(opt.locale?.scriptCode, 'Hant');
      expect(AppLocales.all.map((o) => o.id), contains('zh_Hant'));
    });

    test('resolve maps HK/TW/Hant to zh_Hant and Hans/CN to en', () {
      expect(AppLocales.resolve(const Locale('es')), const Locale('es'));
      expect(AppLocales.resolve(const Locale('en')), const Locale('en'));
      expect(
        AppLocales.resolve(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        AppLocales.zhHant,
      );
      expect(
        AppLocales.resolve(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'HK'),
        ),
        AppLocales.zhHant,
      );
      expect(
        AppLocales.resolve(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
        ),
        AppLocales.zhHant,
      );
      expect(
        AppLocales.resolve(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ),
        const Locale('en'),
      );
      expect(
        AppLocales.resolve(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        ),
        const Locale('en'),
      );
      expect(AppLocales.resolve(const Locale('fr')), const Locale('en'));
      expect(AppLocales.resolve(null), const Locale('en'));
    });
  });
}
