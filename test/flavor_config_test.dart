import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/config/flavor.dart';

void main() {
  group('flavor config', () {
    test('el flavor efectivo coincide con el define de compilación', () {
      const requestedFlavor = String.fromEnvironment(
        'HERMES_FLAVOR',
        defaultValue: 'full',
      );
      const localRequested = bool.fromEnvironment(
        'HERMES_LOCAL_AGENT',
        defaultValue: false,
      );

      expect(kHermesFlavor, requestedFlavor);
      expect(kLocalAgentEnabled, localRequested && requestedFlavor != 'play');
    });

    test('kLocalAgentEnabled exige opt-in y nunca se activa en play', () {
      // Contrato U-13: bool.fromEnvironment('HERMES_LOCAL_AGENT',
      // default false) && flavor != 'play'. Sin el define, es false en
      // TODOS los flavors; con el define, play sigue siendo false.
      const optIn = bool.fromEnvironment(
        'HERMES_LOCAL_AGENT',
        defaultValue: false,
      );
      expect(kLocalAgentEnabled, optIn && kHermesFlavor != 'play');
    });

    test('modo voz activo por defecto con rollback explícito', () {
      const disabled = bool.fromEnvironment(
        'HERMES_DISABLE_VOICE_MODE',
        defaultValue: false,
      );
      expect(kVoiceModeEnabled, !disabled);
      expect(kVoiceRuntimeEnabled, kVoiceModeEnabled || kVoiceQaHarnessEnabled);
    });
  });
}
