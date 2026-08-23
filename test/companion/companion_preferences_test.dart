import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionPreferences', () {
    test(
      'valores por defecto: enabled=true, Inicio visible y paseo=false',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await CompanionPreferences.load();
        expect(prefs.enabled, isTrue);
        expect(prefs.selectedSlug, isNull);
        expect(prefs.roamingEnabled, isFalse);
        expect(prefs.showOnHome, isTrue);
      },
    );

    test('round-trip de slug y enabled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await CompanionPreferences.load();

      await prefs.setSelectedSlug('boba');
      await prefs.setEnabled(false);

      expect(prefs.selectedSlug, 'boba');
      expect(prefs.enabled, isFalse);
    });

    test('setSelectedSlug(null) borra la preferencia', () async {
      SharedPreferences.setMockInitialValues({
        CompanionPreferences.slugKey: 'boba',
      });
      final prefs = await CompanionPreferences.load();
      expect(prefs.selectedSlug, 'boba');

      await prefs.setSelectedSlug(null);
      expect(prefs.selectedSlug, isNull);
    });

    test('persiste entre instancias (misma store mock)', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await CompanionPreferences.load();
      await a.setSelectedSlug('nova');
      await a.setEnabled(false);
      await a.setRoamingEnabled(true);
      await a.setShowOnHome(false);

      final b = await CompanionPreferences.load();
      expect(b.selectedSlug, 'nova');
      expect(b.enabled, isFalse);
      expect(b.roamingEnabled, isTrue);
      expect(b.showOnHome, isFalse);
    });

    test('migra el tamaño continuo desde el preset S/M/L anterior', () async {
      SharedPreferences.setMockInitialValues({
        CompanionPreferences.scaleKey: 'large',
      });
      final prefs = await CompanionPreferences.load();

      expect(prefs.sizeMultiplier, 1.25);

      await prefs.setSizeMultiplier(1.37);
      final reloaded = await CompanionPreferences.load();
      expect(reloaded.sizeMultiplier, closeTo(1.37, 0.001));
    });

    test('la velocidad se conserva por slug y queda acotada', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await CompanionPreferences.load();

      await prefs.setAnimationSpeed('jinx', 0.55);
      await prefs.setAnimationSpeed('luffy', 99);

      expect(prefs.animationSpeedFor('jinx'), closeTo(0.55, 0.001));
      expect(prefs.animationSpeedFor('luffy'), 1.5);
      expect(prefs.animationSpeedFor(null), 1);
    });
  });
}
