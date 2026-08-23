import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/admin_integrations.dart';

void main() {
  test('A2A uses only the official server platform row', () {
    final capability = A2aServerCapability.tryFromPlatformsJson({
      'env_path': '/private/server/.env',
      'platforms': [
        {'id': 'telegram', 'enabled': true},
        {
          'id': 'a2a',
          'enabled': true,
          'configured': true,
          'gateway_running': false,
          'state': 'pending_restart',
          'env_vars': [
            {'key': 'A2A_SECRET', 'redacted_value': '***'},
          ],
        },
      ],
    });

    expect(capability, isNotNull);
    expect(capability!.enabled, isTrue);
    expect(capability.configured, isTrue);
    expect(capability.gatewayRunning, isFalse);
    expect(capability.state, 'pending_restart');
    expect('$capability', isNot(contains('A2A_SECRET')));
    expect('$capability', isNot(contains('/private/server')));
  });

  test('missing or malformed A2A is unknown, never inferred', () {
    expect(
      A2aServerCapability.tryFromPlatformsJson({
        'platforms': [
          {'id': 'telegram', 'enabled': true},
        ],
      }),
      isNull,
    );
    expect(
      A2aServerCapability.tryFromPlatformsJson({'platforms': 'invalid'}),
      isNull,
    );
    expect(
      A2aServerCapability.tryFromPlatformsJson({
        'platforms': [
          {'id': 'a2a', 'state': '/private/server/error'},
        ],
      })?.state,
      'unknown',
    );
  });

  test('official transient A2A states are preserved', () {
    for (final state in const ['connecting', 'retrying']) {
      final capability = A2aServerCapability.tryFromPlatformsJson({
        'platforms': [
          {
            'id': 'a2a',
            'enabled': true,
            'configured': true,
            'gateway_running': true,
            'state': state,
          },
        ],
      });

      expect(capability?.state, state);
    }
  });
}
