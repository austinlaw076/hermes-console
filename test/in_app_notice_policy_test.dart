import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/services/notifications/notification_service.dart';
import 'package:hermes_android/main.dart';

void main() {
  test('approval notice is persistent and keeps priority', () {
    expect(inAppNoticeAutoDismissDelay(NotificationKind.approval), isNull);
    expect(
      shouldReplaceInAppNotice(
        NotificationKind.approval,
        NotificationKind.reply,
      ),
      isFalse,
    );
    expect(
      shouldReplaceInAppNotice(NotificationKind.approval, NotificationKind.run),
      isFalse,
    );
    expect(
      shouldReplaceInAppNotice(
        NotificationKind.reply,
        NotificationKind.approval,
      ),
      isTrue,
    );
  });

  test('informational notice closes after a short delay', () {
    expect(
      inAppNoticeAutoDismissDelay(NotificationKind.reply),
      const Duration(seconds: 7),
    );
    expect(
      shouldReplaceInAppNotice(NotificationKind.reply, NotificationKind.run),
      isTrue,
    );
  });
}
