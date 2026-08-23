import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/new_session_factory.dart';

void main() {
  test('creates an unpersisted local mobile draft', () {
    final factory = NewSessionFactory(
      generateId: () => 'mob-test',
      now: () => DateTime.fromMillisecondsSinceEpoch(1234000),
    );

    final session = factory.create(title: 'Nueva conversación');

    expect(session.id, 'mob-test');
    expect(session.title, 'Nueva conversación');
    expect(session.model, 'hermes-agent');
    expect(session.source, 'mobile');
    expect(session.messageCount, 0);
    expect(session.preview, isEmpty);
    expect(session.isActive, isTrue);
    expect(session.startedAt, 1234);
    expect(session.isUnpersistedMobileDraft, isTrue);
  });
}
