import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notifications/notification_service.dart';

/// Blinda las Reglas 1/2/6 de notificación: qué se muestra como notificación del
/// sistema según el primer plano y el chat que el usuario está mirando.
void main() {
  // Atajo legible sobre la decisión pura.
  bool show({
    required bool fg,
    bool bypass = false,
    bool even = false,
    String? target,
    String? visible,
  }) => NotificationService.shouldShowInForeground(
    appInForeground: fg,
    bypassForeground: bypass,
    evenInForeground: even,
    targetSessionId: target,
    visibleSessionId: visible,
  );

  group('App en segundo plano (Regla 3)', () {
    test('siempre se evalúa mostrar, aunque sea el chat visible', () {
      expect(show(fg: false, target: 's1', visible: 's1'), isTrue);
      expect(show(fg: false, target: 's2', visible: 's1'), isTrue);
      expect(show(fg: false), isTrue);
    });
  });

  group('App en primer plano, mismo chat visible (Regla 1/6)', () {
    test(
      'aprobación (bypass) NO duplica: se resuelve en la tarjeta inline',
      () {
        expect(
          show(fg: true, bypass: true, target: 's1', visible: 's1'),
          isFalse,
        );
      },
    );
    test('respuesta lista NO notifica: ya se ve en el chat', () {
      expect(show(fg: true, target: 's1', visible: 's1'), isFalse);
    });
    test('ni aun con avisos-en-primer-plano activados', () {
      expect(show(fg: true, even: true, target: 's1', visible: 's1'), isFalse);
    });
  });

  group('App en primer plano, OTRO chat (Regla 2)', () {
    test('aprobación de otro chat sí puede notificar (es accionable)', () {
      expect(show(fg: true, bypass: true, target: 's2', visible: 's1'), isTrue);
    });
    test('respuesta de otro chat no salta al sistema por defecto '
        '(el aviso in-app la cubre)', () {
      expect(show(fg: true, target: 's2', visible: 's1'), isFalse);
    });
    test('si el usuario activó avisos en primer plano, sí salta', () {
      expect(show(fg: true, even: true, target: 's2', visible: 's1'), isTrue);
    });
  });

  group('App en primer plano, sin chat en pantalla (home/ajustes)', () {
    test('mismo chat no aplica si no hay sesión visible', () {
      expect(show(fg: true, bypass: true, target: 's1', visible: null), isTrue);
      expect(show(fg: true, target: 's1', visible: null), isFalse);
    });
    test('target vacío no se confunde con visible vacío', () {
      expect(show(fg: true, target: '', visible: ''), isFalse);
    });
  });

  group('Conversación de voz activa', () {
    test('la respuesta de su propio chat no crea una segunda tarjeta', () {
      expect(
        NotificationService.shouldSuppressReplyForActiveVoice(
          activeVoiceSessionId: 'voice-chat',
          targetSessionId: 'voice-chat',
        ),
        isTrue,
      );
    });

    test('otras sesiones y destinos vacíos conservan la política normal', () {
      expect(
        NotificationService.shouldSuppressReplyForActiveVoice(
          activeVoiceSessionId: 'voice-chat',
          targetSessionId: 'other-chat',
        ),
        isFalse,
      );
      expect(
        NotificationService.shouldSuppressReplyForActiveVoice(
          activeVoiceSessionId: null,
          targetSessionId: 'voice-chat',
        ),
        isFalse,
      );
      expect(
        NotificationService.shouldSuppressReplyForActiveVoice(
          activeVoiceSessionId: 'voice-chat',
          targetSessionId: '',
        ),
        isFalse,
      );
    });
  });
}
