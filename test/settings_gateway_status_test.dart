import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  test('muestra únicamente el canal API usado por Hermes Console', () {
    final states = currentGatewayPlatformStates(<String, dynamic>{
      'gateway_updated_at': '2026-07-14T11:01:38.717051+00:00',
      'gateway_platforms': <String, dynamic>{
        'telegram': <String, dynamic>{
          'state': 'disconnected',
          'updated_at': '2026-07-14T11:01:28.631572+00:00',
        },
        'api_server': <String, dynamic>{
          'state': 'connected',
          'updated_at': '2026-07-14T11:01:38.715309+00:00',
        },
        'whatsapp': <String, dynamic>{
          'state': 'error',
          'updated_at': '2026-07-14T11:01:40Z',
        },
      },
    });

    expect(states, {'api_server': 'connected'});
  });

  test('no muestra conectores de terceros aunque su fallo sea actual', () {
    final states = currentGatewayPlatformStates(<String, dynamic>{
      'gateway_updated_at': '2026-07-14T11:01:38Z',
      'gateway_platforms': <String, dynamic>{
        'telegram': <String, dynamic>{
          'state': 'disconnected',
          'updated_at': '2026-07-14T11:01:40Z',
        },
        'slack': 'error',
      },
    });

    expect(states, isEmpty);
  });

  test('el contador se explica como actividad reciente, no chats abiertos', () {
    final s = lookupStrings(const Locale('es'));

    expect(s.setActiveSessions, 'Hermes ahora');
    expect(s.setActiveSessionsIdle, 'en reposo');
    expect(s.setActiveSessionsRunning(1), '1 sesión reciente');
    expect(s.setActiveSessionsNote, contains('últimos 5 minutos'));
  });
}
