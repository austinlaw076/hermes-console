enum TranscriptDensity {
  inherit,
  comfortable,
  compact;

  static TranscriptDensity parse(Object? value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => TranscriptDensity.inherit,
  );
}

enum ChatPreferenceToggle {
  inherit,
  on,
  off;

  static ChatPreferenceToggle parse(Object? value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => ChatPreferenceToggle.inherit,
  );
}

/// Preferencias exclusivamente visuales/locales de una conversación lógica.
///
/// Modelo, reasoning, fast mode y permisos no viven aquí: su fuente de verdad
/// sigue siendo la configuración efectiva publicada por Hermes.
class ChatPreferences {
  static const schemaVersion = 1;

  final TranscriptDensity density;
  final ChatPreferenceToggle autoRead;
  final ChatPreferenceToggle notifications;

  const ChatPreferences({
    this.density = TranscriptDensity.inherit,
    this.autoRead = ChatPreferenceToggle.inherit,
    this.notifications = ChatPreferenceToggle.inherit,
  });

  bool get isDefault =>
      density == TranscriptDensity.inherit &&
      autoRead == ChatPreferenceToggle.inherit &&
      notifications == ChatPreferenceToggle.inherit;

  ChatPreferences copyWith({
    TranscriptDensity? density,
    ChatPreferenceToggle? autoRead,
    ChatPreferenceToggle? notifications,
  }) => ChatPreferences(
    density: density ?? this.density,
    autoRead: autoRead ?? this.autoRead,
    notifications: notifications ?? this.notifications,
  );

  Map<String, Object> toJson() => {
    'schema_version': schemaVersion,
    'density': density.name,
    'auto_read': autoRead.name,
    'notifications': notifications.name,
  };

  factory ChatPreferences.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != schemaVersion) {
      return const ChatPreferences();
    }
    return ChatPreferences(
      density: TranscriptDensity.parse(json['density']),
      autoRead: ChatPreferenceToggle.parse(json['auto_read']),
      notifications: ChatPreferenceToggle.parse(json['notifications']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatPreferences &&
      other.density == density &&
      other.autoRead == autoRead &&
      other.notifications == notifications;

  @override
  int get hashCode => Object.hash(density, autoRead, notifications);
}
