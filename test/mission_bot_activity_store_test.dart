import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/mission_bot_activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MissionBotActivityStore> store() async {
    SharedPreferences.setMockInitialValues({});
    return MissionBotActivityStore(await SharedPreferences.getInstance());
  }

  group('MissionBotActivityStore', () {
    test('scopes watermarks by connection and profile', () async {
      final activity = await store();

      await activity.markRead(
        connectionId: 'lan',
        profile: 'builder',
        activityAtMs: 1200,
      );
      await activity.markRead(
        connectionId: 'tailscale',
        profile: 'builder',
        activityAtMs: 800,
      );

      expect(activity.watermark('lan', 'builder'), 1200);
      expect(activity.watermark('tailscale', 'builder'), 800);
      expect(activity.watermark('lan', 'reviewer'), 0);
    });

    test('unread is strictly newer and markRead is monotonic', () async {
      final activity = await store();

      expect(activity.isUnread('conn', 'kimi', 1), isTrue);
      await activity.markRead(
        connectionId: 'conn',
        profile: 'kimi',
        activityAtMs: 500,
      );

      expect(activity.isUnread('conn', 'kimi', 500), isFalse);
      expect(activity.isUnread('conn', 'kimi', 501), isTrue);

      await activity.markRead(
        connectionId: 'conn',
        profile: 'kimi',
        activityAtMs: 200,
      );
      expect(activity.watermark('conn', 'kimi'), 500);
    });

    test(
      'prune keeps only current valid profiles without storing content',
      () async {
        final activity = await store();
        await activity.markRead(
          connectionId: 'conn',
          profile: 'manager',
          activityAtMs: 100,
        );
        await activity.markRead(
          connectionId: 'conn',
          profile: 'retired',
          activityAtMs: 200,
        );

        await activity.prune('conn', const {'manager'});

        expect(activity.watermarks('conn'), {'manager': 100});
      },
    );

    test('corrupt persisted data degrades to an empty watermark map', () async {
      SharedPreferences.setMockInitialValues({
        'mission_control.bot_activity.v1.Y29ubg': '{broken',
      });
      final activity = MissionBotActivityStore(
        await SharedPreferences.getInstance(),
      );

      expect(activity.watermarks('conn'), isEmpty);
      expect(activity.isUnread('conn', 'manager', 10), isTrue);
    });

    test('rejects invalid profile names and negative timestamps', () async {
      final activity = await store();

      await expectLater(
        activity.markRead(
          connectionId: 'conn',
          profile: '../escape',
          activityAtMs: 1,
        ),
        throwsFormatException,
      );
      await expectLater(
        activity.markRead(
          connectionId: 'conn',
          profile: 'manager',
          activityAtMs: -1,
        ),
        throwsFormatException,
      );
    });
  });
}
