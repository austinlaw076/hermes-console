import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/models/companion_presence_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionPresenceLevel (006 US4)', () {
    test('parse tolerante con default minimal', () {
      expect(companionPresenceLevelFromId('off'), CompanionPresenceLevel.off);
      expect(companionPresenceLevelFromId('full'), CompanionPresenceLevel.full);
      expect(
        companionPresenceLevelFromId('minimal'),
        CompanionPresenceLevel.minimal,
      );
      expect(
        companionPresenceLevelFromId('desconocido'),
        CompanionPresenceLevel.minimal,
      );
      expect(
        companionPresenceLevelFromId(null),
        CompanionPresenceLevel.minimal,
      );
      expect(companionPresenceLevelFromId(''), CompanionPresenceLevel.minimal);
    });

    test('isVisible / showsLabel', () {
      expect(CompanionPresenceLevel.off.isVisible, false);
      expect(CompanionPresenceLevel.minimal.isVisible, true);
      expect(CompanionPresenceLevel.full.isVisible, true);
      expect(CompanionPresenceLevel.off.showsStatusPresence, false);
      expect(CompanionPresenceLevel.minimal.showsStatusPresence, false);
      expect(CompanionPresenceLevel.full.showsStatusPresence, true);
      expect(CompanionPresenceLevel.minimal.showsLabel, false);
      expect(CompanionPresenceLevel.full.showsLabel, true);
    });

    test('preferences round-trip (default minimal)', () async {
      SharedPreferences.setMockInitialValues({});
      final p = CompanionPreferences(await SharedPreferences.getInstance());
      expect(p.presenceLevel, CompanionPresenceLevel.minimal);
      await p.setPresenceLevel(CompanionPresenceLevel.full);
      expect(p.presenceLevel, CompanionPresenceLevel.full);
      await p.setPresenceLevel(CompanionPresenceLevel.off);
      expect(p.presenceLevel, CompanionPresenceLevel.off);
    });
  });
}
