// Auditoría de contraste/legibilidad de TODOS los temas. Evita la inconsistencia
// típica de "botón con texto que contrasta mal con su fondo" y texto ilegible
// sobre las superficies. Umbrales basados en WCAG 2.1 (ratio de contraste).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';

// Ratio de contraste WCAG entre dos colores opacos (1..21).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('contraste y combinación de los temas', () {
    test('el texto del botón (onAccent) es legible sobre el acento', () {
      // AA para texto grande/UI; los botones suelen llevar texto en negrita.
      const min = 3.0;
      final fails = <String>[];
      for (final p in AppTheme.presets) {
        final r = _contrast(p.colors.onAccent, p.colors.accent);
        if (r < min) fails.add('${p.id}: ${r.toStringAsFixed(2)}');
      }
      expect(fails, isEmpty, reason: 'onAccent vs accent flojo en: $fails');
    });

    test('el texto principal es legible sobre fondo y superficies', () {
      const min = 4.5; // AA texto normal
      final fails = <String>[];
      for (final p in AppTheme.presets) {
        final c = p.colors;
        final checks = {
          'background': _contrast(c.textPrimary, c.background),
          'surface': _contrast(c.textPrimary, c.surface),
          'surfaceVariant': _contrast(c.textPrimary, c.surfaceVariant),
        };
        checks.forEach((surf, r) {
          if (r < min) fails.add('${p.id}/$surf: ${r.toStringAsFixed(2)}');
        });
      }
      expect(fails, isEmpty, reason: 'textPrimary flojo en: $fails');
    });

    test('el texto secundario sigue siendo legible sobre el fondo', () {
      const min = 3.0; // texto atenuado: umbral más laxo pero aún legible
      final fails = <String>[];
      for (final p in AppTheme.presets) {
        final r = _contrast(p.colors.textSecondary, p.colors.background);
        if (r < min) fails.add('${p.id}: ${r.toStringAsFixed(2)}');
      }
      expect(fails, isEmpty, reason: 'textSecondary flojo en: $fails');
    });

    test('el acento destaca sobre el fondo (iconos/enlaces)', () {
      const min = 3.0;
      final fails = <String>[];
      for (final p in AppTheme.presets) {
        final r = _contrast(p.colors.accent, p.colors.background);
        if (r < min) fails.add('${p.id}: ${r.toStringAsFixed(2)}');
      }
      expect(fails, isEmpty, reason: 'accent vs background flojo en: $fails');
    });

    test('el color de contraste (secondary) destaca sobre el fondo', () {
      const min = 3.0;
      final fails = <String>[];
      for (final p in AppTheme.presets) {
        final sec = p.secondary;
        if (sec == null) continue;
        final r = _contrast(sec, p.colors.background);
        if (r < min) fails.add('${p.id}: ${r.toStringAsFixed(2)}');
      }
      expect(
        fails,
        isEmpty,
        reason: 'secondary vs background flojo en: $fails',
      );
    });

    // Auditoría 2026-07-02, hallazgo C5c: `accentText` es el token pensado
    // para pintar TEXTO con el acento (no fondos), así que exige el umbral
    // de texto normal (4.5:1), más estricto que el 3.0 de "accent destaca".
    // Solo se cubren los dos temas claros a los que esta pasada les declaró
    // un `accentText` propio (el resto de temas, oscuros o claros sin tocar,
    // quedan fuera de este hallazgo y se abordarán en pasadas posteriores).
    test(
      'accentText es legible como texto normal en los temas claros corregidos',
      () {
        const min = 4.5;
        final checks = <String, HermesThemeColors>{
          'amber-light (hermesRedLight)': AppTheme.hermesRedLight
              .extension<HermesThemeColors>()!,
          'claude-light': AppTheme.presets
              .firstWhere((p) => p.id == 'claude-light')
              .colors,
        };
        final fails = <String>[];
        checks.forEach((name, c) {
          final r = _contrast(c.accentText, c.background);
          if (r < min) fails.add('$name: ${r.toStringAsFixed(2)}');
        });
        expect(fails, isEmpty, reason: 'accentText flojo en: $fails');
      },
    );
  });
}
