import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/theme/theme_profile_codec.dart';
import 'package:hermes_android/main.dart';

void main() {
  test(
    'catálogo global ofrece fuentes locales curadas, únicas y exportables',
    () {
      final ids = AppFonts.all.map((font) => font.id).toList();
      final families = AppFonts.all
          .map((font) => font.family)
          .whereType<String>()
          .toSet();

      expect(ids.toSet(), hasLength(ids.length));
      expect(AppFonts.all, hasLength(5));
      expect(
        families,
        unorderedEquals({'Inter', 'Montserrat', 'Nunito', 'JetBrainsMono'}),
      );
      expect(ThemeProfileCodec.packagedFontFamilies, families);
      expect(
        AppTheme.presets.map((preset) => preset.fontFamily),
        everyElement(isIn(ThemeProfileCodec.packagedFontFamilies)),
      );
    },
  );

  test('cada id Fontshare guardado migra a su equivalente OFL', () {
    const expected = {
      'satoshi': 'inter',
      'general-sans': 'inter',
      'switzer': 'inter',
      'supreme': 'montserrat',
      'cabinet': 'montserrat',
      'clash': 'montserrat',
      'chillax': 'nunito',
      'sentient': 'montserrat',
      'zodiak': 'montserrat',
    };

    for (final entry in expected.entries) {
      expect(AppFonts.byId(entry.key).id, entry.value, reason: entry.key);
    }
    expect(AppFonts.byId('montserrat').id, 'montserrat');
    expect(AppFonts.byId('nunito').id, 'nunito');
    expect(AppFonts.byId('desconocida').id, AppFonts.defaultId);
  });

  test('la fuente elegida alcanza cuerpo, AppBar y System usa Roboto', () {
    final base = AppTheme.fromId('amber');
    final system = AppFonts.applyToTheme(base, AppFonts.byId('system'));
    final mono = AppFonts.applyToTheme(base, AppFonts.byId('jetbrains'));

    expect(system.textTheme.bodyMedium?.fontFamily, AppFonts.systemFamily);
    expect(
      system.appBarTheme.titleTextStyle?.fontFamily,
      AppFonts.systemFamily,
    );
    expect(mono.textTheme.bodyMedium?.fontFamily, 'JetBrainsMono');
    expect(mono.appBarTheme.titleTextStyle?.fontFamily, 'JetBrainsMono');
  });
}
