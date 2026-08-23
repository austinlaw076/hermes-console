import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';

Map<String, dynamic> _message(String role, String id, {bool pipeline = false}) {
  return <String, dynamic>{
    'role': role,
    'id': id,
    if (pipeline) '_pipeline': true,
  };
}

void main() {
  test('streaming replacements do not grow the assistant anchor cache', () {
    final anchors = Map<Map<String, dynamic>, Object>.identity();

    for (var index = 0; index < 500; index++) {
      final snapshot = _message('assistant', 'same-answer')
        ..['content'] = 'token snapshot $index';
      anchors[snapshot] = Object();
      pruneAssistantAnchorCache(anchors, [snapshot]);
      expect(anchors, hasLength(1));
      expect(anchors.containsKey(snapshot), isTrue);
    }
  });

  test('only current renderable assistant units retain anchors', () {
    final first = _message('assistant', 'first');
    final second = _message('assistant', 'second');
    final stale = _message('assistant', 'stale');
    final user = _message('user', 'user');
    final pipeline = _message('assistant', 'pipeline', pipeline: true);
    final anchors = Map<Map<String, dynamic>, Object>.identity()
      ..[first] = Object()
      ..[second] = Object()
      ..[stale] = Object()
      ..[user] = Object()
      ..[pipeline] = Object();

    pruneAssistantAnchorCache(anchors, [
      first,
      second,
      user,
      pipeline,
      Object(),
    ]);

    expect(anchors.keys, unorderedEquals([first, second]));
  });
}
