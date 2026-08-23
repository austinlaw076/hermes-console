import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/profile_chat_mode.dart';

void main() {
  group('isValidProfileName', () {
    test('acepta nombres válidos (minúsculas/dígitos/guion/guion_bajo)', () {
      for (final n in [
        'demo',
        'work-bot',
        'agent_2',
        'a',
        'default',
        'x1-y_2',
      ]) {
        expect(isValidProfileName(n), isTrue, reason: n);
      }
    });

    test(
      'rechaza vacío, traversal, separadores y caracteres no permitidos',
      () {
        for (final n in [
          '',
          '   ',
          '..',
          '../etc',
          'a/b',
          'a\\b',
          'Demo', // mayúscula
          'demo profile', // espacio
          'demo!', // símbolo
          '-leading', // primer char no alfanumérico
          '_leading',
        ]) {
          expect(isValidProfileName(n), isFalse, reason: '"$n"');
        }
      },
    );

    test('rechaza nombres demasiado largos (>64)', () {
      expect(isValidProfileName('a' * 64), isTrue);
      expect(isValidProfileName('a' * 65), isFalse);
    });
  });

  group('profileRoutes', () {
    test('vacío y default no enrutan; un perfil válido sí', () {
      expect(profileRoutes(''), isFalse);
      expect(profileRoutes('default'), isFalse);
      expect(profileRoutes('demo'), isTrue);
    });
    test('nombre inválido no enruta (degrada a none)', () {
      expect(profileRoutes('../x'), isFalse);
    });
  });

  group('resolveProfileChatMode', () {
    test('default/vacío → none (camino actual)', () {
      expect(
        resolveProfileChatMode(
          profile: '',
          bridgeAvailable: true,
          bridgeSupportsProfile: true,
          soulAvailable: true,
        ),
        ProfileChatMode.none,
      );
      expect(
        resolveProfileChatMode(
          profile: 'default',
          bridgeAvailable: true,
          bridgeSupportsProfile: true,
          soulAvailable: true,
        ),
        ProfileChatMode.none,
      );
    });

    test('bridge con soporte → full', () {
      expect(
        resolveProfileChatMode(
          profile: 'demo',
          bridgeAvailable: true,
          bridgeSupportsProfile: true,
          soulAvailable: true,
        ),
        ProfileChatMode.full,
      );
    });

    test('sin bridge pero SOUL legible → personality', () {
      expect(
        resolveProfileChatMode(
          profile: 'demo',
          bridgeAvailable: false,
          bridgeSupportsProfile: false,
          soulAvailable: true,
        ),
        ProfileChatMode.personality,
      );
    });

    test('bridge antiguo (sin soporte) cae a personality si hay SOUL', () {
      expect(
        resolveProfileChatMode(
          profile: 'demo',
          bridgeAvailable: true,
          bridgeSupportsProfile: false,
          soulAvailable: true,
        ),
        ProfileChatMode.personality,
      );
    });

    test('sin bridge y sin SOUL → none (nunca rompe)', () {
      expect(
        resolveProfileChatMode(
          profile: 'demo',
          bridgeAvailable: false,
          bridgeSupportsProfile: false,
          soulAvailable: false,
        ),
        ProfileChatMode.none,
      );
    });

    test('perfil con nombre inválido → none aunque haya capacidad', () {
      expect(
        resolveProfileChatMode(
          profile: '../evil',
          bridgeAvailable: true,
          bridgeSupportsProfile: true,
          soulAvailable: true,
        ),
        ProfileChatMode.none,
      );
    });
  });
}
