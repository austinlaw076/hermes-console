import 'dart:math' as math;

final class MissionRoom {
  static const maxPurposeLabelRunes = 160;
  static final RegExp _profileName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  /// A Room may be saved before its manager chat exists, but it must never
  /// persist the client-side `mob-*` draft id as if Hermes had confirmed it.
  /// The canonical TUI lifecycle replaces that draft with an opaque stored id
  /// after `session.create`; until then the empty value is the honest state.
  static bool isDurableManagerSessionId(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        normalized.length <= 256 &&
        !normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) &&
        !normalized.startsWith('mob-');
  }

  static String _normalizedManagerSessionId(String value) {
    final normalized = value.trim();
    return normalized.startsWith('mob-') ? '' : normalized;
  }

  final String id;
  final String connectionId;
  final String? organizationId;
  final String name;
  final String purposeLabel;
  final String managerProfile;
  final Set<String> memberProfiles;
  final String managerSessionId;
  final List<MissionRoomTaskLink> linkedTasks;
  final int createdAtMs;
  final int updatedAtMs;

  factory MissionRoom({
    required String id,
    required String connectionId,
    String? organizationId,
    required String name,
    String purposeLabel = '',
    required String managerProfile,
    required Iterable<String> memberProfiles,
    required String managerSessionId,
    Iterable<MissionRoomTaskLink> linkedTasks = const [],
    @Deprecated('Use linkedTasks with an explicit board locator')
    Iterable<String> linkedTaskIds = const [],
    required int createdAtMs,
    required int updatedAtMs,
  }) {
    final manager = managerProfile.trim();
    final members = <String>{
      ...memberProfiles
          .map((value) => value.trim())
          .where(_profileName.hasMatch)
          .take(100),
    };
    if (_profileName.hasMatch(manager)) {
      if (members.length >= 100 && !members.contains(manager)) {
        members.remove(members.last);
      }
      members.add(manager);
    }
    return MissionRoom._(
      id: id.trim(),
      connectionId: connectionId.trim(),
      organizationId: _safeText(organizationId, 128),
      name: name.trim(),
      purposeLabel: _safeText(purposeLabel, maxPurposeLabelRunes) ?? '',
      managerProfile: manager,
      memberProfiles: Set.unmodifiable(members),
      managerSessionId: _normalizedManagerSessionId(managerSessionId),
      linkedTasks: List.unmodifiable(
        <MissionRoomTaskLink>{
          ...linkedTasks.where((link) => link.isValid),
          ...linkedTaskIds.map(
            (taskId) => MissionRoomTaskLink(
              boardId: MissionRoomTaskLink.legacyCurrentBoard,
              taskId: taskId,
            ),
          ),
        }.take(500),
      ),
      createdAtMs: math.max(0, createdAtMs),
      updatedAtMs: math.max(0, updatedAtMs),
    );
  }

  const MissionRoom._({
    required this.id,
    required this.connectionId,
    this.organizationId,
    required this.name,
    required this.purposeLabel,
    required this.managerProfile,
    required this.memberProfiles,
    required this.managerSessionId,
    required this.linkedTasks,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get isValid =>
      id.isNotEmpty &&
      id.length <= 128 &&
      connectionId.isNotEmpty &&
      connectionId.length <= 256 &&
      name.isNotEmpty &&
      name.runes.length <= 64 &&
      purposeLabel.runes.length <= maxPurposeLabelRunes &&
      _profileName.hasMatch(managerProfile) &&
      memberProfiles.contains(managerProfile) &&
      (managerSessionId.isEmpty || isDurableManagerSessionId(managerSessionId));

  bool get hasDurableManagerSession =>
      isDurableManagerSessionId(managerSessionId);

  List<String> get linkedTaskIds =>
      List.unmodifiable(linkedTasks.map((link) => link.taskId));

  MissionRoom copyWith({
    String? organizationId,
    bool clearOrganization = false,
    String? name,
    String? purposeLabel,
    String? managerProfile,
    Iterable<String>? memberProfiles,
    String? managerSessionId,
    Iterable<MissionRoomTaskLink>? linkedTasks,
    int? updatedAtMs,
  }) => MissionRoom(
    id: id,
    connectionId: connectionId,
    organizationId: clearOrganization
        ? null
        : organizationId ?? this.organizationId,
    name: name ?? this.name,
    purposeLabel: purposeLabel ?? this.purposeLabel,
    managerProfile: managerProfile ?? this.managerProfile,
    memberProfiles: memberProfiles ?? this.memberProfiles,
    managerSessionId: managerSessionId ?? this.managerSessionId,
    linkedTasks: linkedTasks ?? this.linkedTasks,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  MissionRoom withLinkedTask(
    String taskId, {
    required String boardId,
    required int updatedAtMs,
  }) {
    final link = MissionRoomTaskLink(boardId: boardId, taskId: taskId);
    if (!link.isValid || linkedTasks.contains(link)) {
      return this;
    }
    return copyWith(
      linkedTasks: [
        ...linkedTasks,
        link,
      ].skip(math.max(0, linkedTasks.length + 1 - 500)),
      updatedAtMs: updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'connection_id': connectionId,
    if (organizationId != null) 'organization_id': organizationId,
    'name': name,
    if (purposeLabel.isNotEmpty) 'purpose_label': purposeLabel,
    'manager_profile': managerProfile,
    'member_profiles': memberProfiles.toList()..sort(),
    'manager_session_id': managerSessionId,
    'linked_tasks': linkedTasks.map((link) => link.toJson()).toList(),
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  static MissionRoom? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _safeText(raw['id'], 128);
    final connectionId = _safeText(raw['connection_id'], 256);
    final name = _safeText(raw['name'], 64);
    final manager = _safeText(raw['manager_profile'], 64);
    final rawSessionId = raw['manager_session_id'];
    final sessionId = rawSessionId is String ? rawSessionId.trim() : '';
    if (id == null ||
        connectionId == null ||
        name == null ||
        manager == null ||
        sessionId.length > 256) {
      return null;
    }
    final rawMembers = raw['member_profiles'];
    final rawLinks = raw['linked_tasks'];
    final rawTaskIds = raw['linked_task_ids'];
    final room = MissionRoom(
      id: id,
      connectionId: connectionId,
      organizationId: _safeText(raw['organization_id'], 128),
      name: name,
      purposeLabel: _safeText(raw['purpose_label'], maxPurposeLabelRunes) ?? '',
      managerProfile: manager,
      memberProfiles: rawMembers is List
          ? rawMembers.whereType<String>()
          : const <String>[],
      managerSessionId: sessionId,
      linkedTasks: rawLinks is List
          ? rawLinks.map(MissionRoomTaskLink.tryParse).whereType()
          : const <MissionRoomTaskLink>[],
      linkedTaskIds: rawTaskIds is List
          ? rawTaskIds.whereType<String>()
          : const <String>[],
      createdAtMs: _safeInt(raw['created_at_ms']) ?? 0,
      updatedAtMs: _safeInt(raw['updated_at_ms']) ?? 0,
    );
    return room.isValid ? room : null;
  }
}

final class MissionRoomTaskLink {
  static const legacyCurrentBoard = 'legacy-current';

  final String boardId;
  final String taskId;

  factory MissionRoomTaskLink({
    required String boardId,
    required String taskId,
  }) => MissionRoomTaskLink._(boardId.trim(), taskId.trim());

  const MissionRoomTaskLink._(this.boardId, this.taskId);

  bool get isValid =>
      boardId.isNotEmpty &&
      boardId.length <= 128 &&
      taskId.isNotEmpty &&
      taskId.length <= 256;

  Map<String, dynamic> toJson() => {'board_id': boardId, 'task_id': taskId};

  static MissionRoomTaskLink? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final boardId = _safeText(raw['board_id'], 128);
    final taskId = _safeText(raw['task_id'], 256);
    if (boardId == null || taskId == null) return null;
    final link = MissionRoomTaskLink(boardId: boardId, taskId: taskId);
    return link.isValid ? link : null;
  }

  @override
  bool operator ==(Object other) =>
      other is MissionRoomTaskLink &&
      other.boardId == boardId &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(boardId, taskId);
}

final class MissionMentionIntent {
  final String id;
  final String roomId;
  final String rawText;
  final String workerProfile;
  final String taskTitle;

  const MissionMentionIntent({
    required this.id,
    required this.roomId,
    required this.rawText,
    required this.workerProfile,
    required this.taskTitle,
  });

  String get idempotencyKey => 'room:$roomId:mention:$id:$workerProfile';
}

final class MissionMentionParseResult {
  final bool managerMentioned;
  final Set<String> selectedWorkers;
  final Set<String> unresolvedTypedHandles;
  final Set<String> invalidSelections;
  final MissionMentionIntent? intent;

  const MissionMentionParseResult({
    this.managerMentioned = false,
    this.selectedWorkers = const {},
    this.unresolvedTypedHandles = const {},
    this.invalidSelections = const {},
    this.intent,
  });

  bool get hasMultipleWorkers => selectedWorkers.length > 1;
  bool get canDispatch =>
      intent != null &&
      !hasMultipleWorkers &&
      invalidSelections.isEmpty &&
      unresolvedTypedHandles.isEmpty;
}

abstract final class MissionMentionParser {
  static final RegExp _typedHandle = RegExp(
    r'(^|\s)@([a-z0-9][a-z0-9_-]{0,63})(?=\s|$|[.,;:!?])',
    multiLine: true,
  );

  static MissionMentionParseResult parse({
    required MissionRoom room,
    required String text,
    Iterable<String> selectedProfiles = const [],
    required String intentId,
  }) {
    final raw = text.trim();
    final typed = _typedHandle
        .allMatches(raw)
        .map((match) => match.group(2)!)
        .toSet();
    final selected = selectedProfiles
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final validSelections = selected
        .where(room.memberProfiles.contains)
        .where(typed.contains)
        .toSet();
    final invalidSelections = selected.difference(validSelections);
    final unresolved = typed.difference(validSelections);
    final managerMentioned = validSelections.contains(room.managerProfile);
    final workers = validSelections.difference({room.managerProfile});
    MissionMentionIntent? intent;
    if (raw.isNotEmpty &&
        workers.length == 1 &&
        unresolved.isEmpty &&
        invalidSelections.isEmpty) {
      final worker = workers.single;
      intent = MissionMentionIntent(
        id: intentId,
        roomId: room.id,
        rawText: raw,
        workerProfile: worker,
        taskTitle: _taskTitle(raw, validSelections),
      );
    }
    return MissionMentionParseResult(
      managerMentioned: managerMentioned,
      selectedWorkers: Set.unmodifiable(workers),
      unresolvedTypedHandles: Set.unmodifiable(unresolved),
      invalidSelections: Set.unmodifiable(invalidSelections),
      intent: intent,
    );
  }

  static String _taskTitle(String text, Set<String> selected) {
    var title = text;
    for (final profile in selected) {
      title = title.replaceAll(RegExp('\\@$profile\\b'), ' ');
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) title = 'Room request';
    final runes = title.runes.toList(growable: false);
    if (runes.length <= 120) return title;
    return '${String.fromCharCodes(runes.take(119))}…';
  }
}

String? _safeText(Object? raw, int maxRunes) {
  if (raw is! String) return null;
  final value = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ').trim();
  if (value.isEmpty || value.runes.length > maxRunes) return null;
  return value;
}

int? _safeInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite) return raw.toInt();
  return null;
}
