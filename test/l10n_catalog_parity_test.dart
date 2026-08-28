import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _readCatalog(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> _messageKeys(Map<String, Object?> catalog) =>
    catalog.keys.where((key) => !key.startsWith('@')).toSet();

Set<String> _placeholders(Object? message) => RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)\s*(?:\}|,)',
).allMatches(message as String).map((match) => match.group(1)!).toSet();

void main() {
  test(
    'los catálogos español e inglés tienen las mismas claves y variables',
    () {
      final es = _readCatalog('lib/l10n/app_es.arb');
      final en = _readCatalog('lib/l10n/app_en.arb');

      // app_es.arb es la plantilla de gen-l10n y por eso conserva más entradas
      // @metadata. El contrato traducible son las claves de mensaje sin @.
      expect(_messageKeys(en), _messageKeys(es));

      for (final key in _messageKeys(es)) {
        expect(
          _placeholders(en[key]),
          _placeholders(es[key]),
          reason: 'Los placeholders de $key deben coincidir en ES/EN',
        );
      }
    },
  );

  test('el catálogo zh_Hant mantiene claves y placeholders con EN/ES', () {
    final zhPath = File('lib/l10n/app_zh_Hant.arb');
    expect(zhPath.existsSync(), isTrue, reason: 'falta app_zh_Hant.arb');
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');
    final zh = _readCatalog(zhPath.path);

    expect(zh['@@locale'], 'zh_Hant');
    expect(_messageKeys(zh), _messageKeys(en));
    expect(_messageKeys(zh), _messageKeys(es));

    for (final key in _messageKeys(en)) {
      expect(
        _placeholders(zh[key]),
        _placeholders(en[key]),
        reason: 'Los placeholders de $key deben coincidir en ZH/EN',
      );
    }

    expect(zh['languageTraditionalChinese'], '繁體中文');
    expect(zh['setLanguage'], '語言');
    expect(zh['setLanguageSystem'], '系統');
  });

  test(
    'el fallback técnico app_zh mantiene claves y placeholders con EN/ES',
    () {
      // app_zh.arb existe solo porque gen-l10n lo requiere para zh_Hant. No es
      // un locale público: AppLocales resuelve zh sin Hant, zh_Hans y zh_CN a
      // inglés. Debe conservar paridad para que la generación siga siendo
      // válida, sin ampliar el contrato de idiomas de la UI.
      final zhPath = File('lib/l10n/app_zh.arb');
      expect(zhPath.existsSync(), isTrue, reason: 'falta app_zh.arb');
      final es = _readCatalog('lib/l10n/app_es.arb');
      final en = _readCatalog('lib/l10n/app_en.arb');
      final zh = _readCatalog(zhPath.path);

      expect(zh['@@locale'], 'zh');
      expect(_messageKeys(zh), _messageKeys(es));
      expect(_messageKeys(zh), _messageKeys(en));

      for (final key in _messageKeys(en)) {
        expect(
          _placeholders(zh[key]),
          _placeholders(en[key]),
          reason: 'Los placeholders de $key deben coincidir en fallback ZH/EN',
        );
      }
    },
  );

  test('app_zh is derived deterministically from app_zh_Hant except @@locale', () {
    final zhHant = _readCatalog('lib/l10n/app_zh_Hant.arb');
    final zh = _readCatalog('lib/l10n/app_zh.arb');

    expect(zh['@@locale'], 'zh');
    expect(zhHant['@@locale'], 'zh_Hant');

    final zhHantValues = Map<String, dynamic>.fromEntries(
      zhHant.entries.where((e) => !e.key.startsWith('@') && !e.key.startsWith('_')),
    );
    final zhValues = Map<String, dynamic>.fromEntries(
      zh.entries.where((e) => !e.key.startsWith('@') && !e.key.startsWith('_')),
    );

    expect(zhValues.keys, unorderedEquals(zhHantValues.keys));
    for (final entry in zhHantValues.entries) {
      expect(
        zhValues[entry.key],
        entry.value,
        reason: 'app_zh["${entry.key}"] must match app_zh_Hant',
      );
    }
  });

  test(
    'Notificaciones conserva la misma mayúscula inicial que cada pantalla',
    () {
      final es = _readCatalog('lib/l10n/app_es.arb');
      final en = _readCatalog('lib/l10n/app_en.arb');

      expect(es['notifTitle'], 'Notificaciones');
      expect(en['notifTitle'], 'Notifications');
    },
  );

  test('el hint de voz explica barge-in sin pedir que Hermes termine', () {
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');

    expect(es['chaVoiceCanInterruptHint'], contains('interrumpir hablando'));
    expect(es['chaVoiceCanInterruptHint'], isNot(contains('Espera')));
    expect(en['chaVoiceCanInterruptHint'], contains('interrupt by speaking'));
    expect(en['chaVoiceCanInterruptHint'], isNot(contains('Wait')));
  });

  test('Servidor Hermes nunca promete cambiar a la voz local', () {
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');

    expect(es['voiceModeServerSub'], contains('no cambia al móvil'));
    expect(
      es['nativeVoiceConsentBody'],
      contains('no cambiará a la voz local'),
    );
    expect(
      es['voiceServerFallbackNote'],
      contains('No activa automáticamente'),
    );

    expect(en['voiceModeServerSub'], contains('never switches'));
    expect(
      en['nativeVoiceConsentBody'],
      contains('will not switch to local voice'),
    );
    expect(en['voiceServerFallbackNote'], contains('does not automatically'));
  });
}
