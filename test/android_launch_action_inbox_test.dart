import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/new_session_launch_action.dart';
import 'package:hermes_android/core/services/android_launch_action_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidLaunchActionInbox.channelName);

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('takes and validates the cold-start action once', () async {
    var takes = 0;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'takePendingLaunchAction');
          takes += 1;
          return <String, Object?>{
            'contract_version': 1,
            'kind': 'new_session',
            'source': 'shortcut',
            'native_event_id': 'cold-1',
            'received_elapsed_ms': 100,
          };
        });

    final inbox = AndroidLaunchActionInbox();
    final initial = await inbox.initialize();
    final second = await inbox.initialize();

    expect(initial?.source, NewSessionLaunchSource.shortcut);
    expect(initial?.nativeEventId, 'cold-1');
    expect(second, isNull);
    expect(takes, 1);
    await inbox.dispose();
  });

  test('fails closed when the native contract version is unknown', () async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'contract_version': 99,
            'kind': 'new_session',
            'source': 'widget',
            'native_event_id': 'future-1',
            'received_elapsed_ms': 100,
          };
        });

    final inbox = AndroidLaunchActionInbox();
    expect(await inbox.initialize(), isNull);
    await inbox.dispose();
  });
}
