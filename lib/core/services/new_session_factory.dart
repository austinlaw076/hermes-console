import 'connection_manager.dart';

/// Single source of truth for blank chats created by Home, drawer, shortcuts
/// and widgets. The draft remains local until the first user submission.
class NewSessionFactory {
  final String Function() _generateId;
  final DateTime Function() _now;

  NewSessionFactory({String Function()? generateId, DateTime Function()? now})
    : _generateId = generateId ?? GatewayChatClient.generateSessionId,
      _now = now ?? DateTime.now;

  Session create({required String title}) {
    return Session(
      id: _generateId(),
      title: title,
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: _now().millisecondsSinceEpoch / 1000,
    );
  }
}
