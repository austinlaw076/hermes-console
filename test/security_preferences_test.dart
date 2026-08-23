import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notifications/notification_service.dart';
import 'package:hermes_android/core/services/screen_security.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ocultación de notificaciones persiste y es opt-in', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = NotificationService(prefs);

    expect(notifications.hideSensitiveContent, isFalse);
    await notifications.setHideSensitiveContent(true);
    expect(notifications.hideSensitiveContent, isTrue);
  });

  test(
    'protección de capturas persiste y aplica FLAG_SECURE por canal',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final calls = <MethodCall>[];
      const channel = MethodChannel('hermes/security');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final security = ScreenSecurityService(prefs);
      expect(security.enabled, isFalse);
      await security.setEnabled(true);

      expect(security.enabled, isTrue);
      expect(calls.single.method, 'setSecureScreen');
      expect(calls.single.arguments, isTrue);
    },
  );
}
