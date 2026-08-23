import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session_artifact.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';

void main() {
  test('stable message id wins over a stale ordinal after reconciliation', () {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'assistant',
        'content': 'newest',
        '_desktopMessageId': 'message-newest',
        '_desktopMessageOrdinal': 8,
      },
      {
        'role': 'assistant',
        'content': 'source',
        '_desktopMessageId': 'message-source',
        '_desktopMessageOrdinal': 7,
      },
    ];

    expect(
      messageIndexForArtifactSource(
        messages,
        const SessionArtifactSource(
          messageId: 'message-source',
          messageOrdinal: 0,
        ),
      ),
      1,
    );
  });

  test('stable message id never falls back to a now unrelated ordinal', () {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'assistant',
        'content': 'replacement',
        '_desktopMessageId': 'message-replacement',
        '_desktopMessageOrdinal': 0,
      },
    ];

    expect(
      messageIndexForArtifactSource(
        messages,
        const SessionArtifactSource(
          messageId: 'message-removed',
          messageOrdinal: 0,
        ),
      ),
      isNull,
    );
  });

  test(
    'server ordinal ignores synthetic steer, pipeline and inflight rows',
    () {
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': '', '_pipeline': true},
        {'role': 'user', 'content': 'steer', '_steer': true},
        {'role': 'assistant', 'content': 'second persisted'},
        {
          'role': 'user',
          'content': 'runtime-only',
          '_desktopSnapshotKind': 'inflight',
        },
        {'role': 'user', 'content': 'first persisted'},
      ];

      expect(
        messageIndexForArtifactSource(
          messages,
          const SessionArtifactSource(messageOrdinal: 1),
        ),
        2,
      );
    },
  );

  test('message anchor cache drops objects removed by a transcript rewind', () {
    final live = <String, dynamic>{'role': 'assistant', 'content': 'live'};
    final removed = <String, dynamic>{
      'role': 'assistant',
      'content': 'removed',
    };
    final anchors = Map<Map<String, dynamic>, Object>.identity()
      ..[live] = Object()
      ..[removed] = Object();

    pruneMessageAnchorCache(anchors, [live]);

    expect(anchors.keys, [same(live)]);
  });
}
