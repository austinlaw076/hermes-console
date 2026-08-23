import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/desktop_gateway_capabilities.dart';

void main() {
  test('capability cache caduca y vuelve a unknown', () {
    var now = DateTime.utc(2026, 7, 21, 10);
    final cache = DesktopGatewayCapabilityCache(
      ttl: const Duration(minutes: 2),
      now: () => now,
    );

    cache.mark(
      DesktopGatewayCapability.sessionActiveList,
      DesktopGatewayCapabilityState.unsupported,
    );
    expect(
      cache.state(DesktopGatewayCapability.sessionActiveList),
      DesktopGatewayCapabilityState.unsupported,
    );
    expect(
      cache.canAttempt(DesktopGatewayCapability.sessionActiveList),
      isFalse,
    );

    now = now.add(const Duration(minutes: 2));
    expect(
      cache.state(DesktopGatewayCapability.sessionActiveList),
      DesktopGatewayCapabilityState.unknown,
    );
    expect(
      cache.canAttempt(DesktopGatewayCapability.sessionActiveList),
      isTrue,
    );
  });

  test('reconnect invalida cualquier conocimiento anterior', () {
    final cache = DesktopGatewayCapabilityCache();
    cache.mark(
      DesktopGatewayCapability.sessionActivate,
      DesktopGatewayCapabilityState.supported,
    );
    cache.mark(
      DesktopGatewayCapability.modelOptions,
      DesktopGatewayCapabilityState.invalid,
    );

    cache.resetForReconnect();

    expect(
      cache.state(DesktopGatewayCapability.sessionActivate),
      DesktopGatewayCapabilityState.unknown,
    );
    expect(
      cache.state(DesktopGatewayCapability.modelOptions),
      DesktopGatewayCapabilityState.unknown,
    );
  });
}
