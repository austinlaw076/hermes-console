import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attachment_draft.dart';
import '../models/session.dart';
import 'attachment_uploader.dart';

enum MissionRoomTaskPhase { prepared, submitting, outcomeUnknown }

class ChatDraft {
  final String text;
  final List<AttachmentDraft> attachments;
  final String? missionRoomIntentId;
  final String? missionRoomWorkerProfile;
  final String? missionRoomBoardId;
  final String? missionRoomBoardQuery;
  final MissionRoomTaskPhase? missionRoomTaskPhase;

  const ChatDraft({
    required this.text,
    required this.attachments,
    this.missionRoomIntentId,
    this.missionRoomWorkerProfile,
    this.missionRoomBoardId,
    this.missionRoomBoardQuery,
    this.missionRoomTaskPhase,
  });

  bool get missionRoomOutcomeUnknown =>
      missionRoomTaskPhase == MissionRoomTaskPhase.outcomeUnknown;

  bool get hasMissionRoomOperation =>
      missionRoomIntentId != null ||
      missionRoomWorkerProfile != null ||
      missionRoomBoardId != null ||
      missionRoomBoardQuery != null ||
      missionRoomTaskPhase != null;
}

/// Entrada recuperable de un chat que todavía no existe en el servidor.
///
/// El índice se deriva directamente de las claves cifradas del Keystore: no se
/// duplica texto, nombres de archivo ni previews sensibles en SharedPreferences.
class ChatDraftEntry {
  final String sessionId;
  final String profile;
  final DateTime savedAt;
  final ChatDraft draft;

  const ChatDraftEntry({
    required this.sessionId,
    this.profile = 'default',
    required this.savedAt,
    required this.draft,
  });

  Session toSession({required String fallbackTitle}) {
    final textTitle = Session.titleFromText(draft.text);
    final attachmentTitle = draft.attachments.isEmpty
        ? ''
        : draft.attachments.first.name.trim();
    final title = textTitle.isNotEmpty
        ? textTitle
        : attachmentTitle.isNotEmpty
        ? attachmentTitle
        : fallbackTitle;
    return Session(
      id: sessionId,
      title: title,
      model: 'hermes-agent',
      source: 'mobile-draft',
      messageCount: 0,
      isActive: false,
      preview: draft.text,
      startedAt: savedAt.millisecondsSinceEpoch / 1000,
      updatedAt: savedAt.millisecondsSinceEpoch / 1000,
      profile: profile,
      hasLocalDraft: true,
    );
  }
}

/// Borrador local cifrado por instancia y sesión. El texto puede contener datos
/// sensibles aunque no sea una credencial, por eso vive en el Keystore y no en
/// SharedPreferences. Las rutas SAF/caché se validan al restaurar porque Android
/// puede revocarlas o borrarlas.
class ChatDraftStore {
  // Secure storage operations are asynchronous and Android may complete an
  // older write after a newer delete. Serialize mutations by the exact
  // connection/profile/session key so an autosave can never resurrect a draft
  // that an acknowledged send already cleared. Static scope also covers the
  // short window where two widget lifecycles construct separate store objects.
  static final Map<String, Future<void>> _mutationTails = {};

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final Future<bool> Function(AttachmentDraft) _deletePrivateCopy;

  ChatDraftStore(
    this._prefs, {
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    Future<bool> Function(AttachmentDraft)? deletePrivateCopy,
  }) : _secure = secureStorage,
       _deletePrivateCopy =
           deletePrivateCopy ?? AttachmentUploader.deletePrivateDraftCopy;

  static String _scope(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static String _unScope(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64Url.decode(padded));
  }

  static bool _isDedicatedSurfaceScope(String value) =>
      value.startsWith('mob-bot-') || value.startsWith('mob-room-');

  static bool _belongsToDedicatedSurface(String sessionId, String owner) =>
      _isDedicatedSurfaceScope(sessionId) ||
      _isDedicatedSurfaceScope(owner);

  String _key(String connectionId, String sessionId, String profile) =>
      'chat_draft_v3.${_scope(connectionId)}.${_scope(profile)}.${_scope(sessionId)}';
  String _unscopedV2Key(String connectionId, String sessionId) =>
      'chat_draft_v2_${connectionId}_$sessionId';
  String _legacyKey(String connectionId, String sessionId) =>
      'chat_draft_v1_${connectionId}_$sessionId';

  static Future<T> _serializeMutation<T>(
    String scope,
    Future<T> Function() action,
  ) async {
    final previous = _mutationTails[scope];
    final gate = Completer<void>();
    final tail = gate.future;
    _mutationTails[scope] = tail;
    if (previous != null) {
      await previous;
    }
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_mutationTails[scope], tail)) {
        _mutationTails.remove(scope);
      }
    }
  }

  static String keyForTesting(
    String connectionId,
    String sessionId, {
    String profile = 'default',
  }) =>
      'chat_draft_v3.${_scope(connectionId)}.${_scope(profile)}.${_scope(sessionId)}';

  static const Duration maxAge = Duration(days: 30);

  ChatDraftEntry? _decodeEntry(String sessionId, String profile, String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        (data['savedAt'] as num?)?.toInt() ?? 0,
      );
      final roomTaskPhase = _taskPhase(data['missionRoomTaskPhase']);
      final unresolvedRoomWrite =
          roomTaskPhase == MissionRoomTaskPhase.submitting ||
          roomTaskPhase == MissionRoomTaskPhase.outcomeUnknown;
      if (savedAt.millisecondsSinceEpoch <= 0 ||
          (!unresolvedRoomWrite &&
              DateTime.now().difference(savedAt) > maxAge)) {
        return null;
      }
      final attachments = <AttachmentDraft>[];
      for (final item in (data['attachments'] as List? ?? const [])) {
        if (item is! Map) continue;
        final draft = AttachmentDraft.fromJson(Map<String, dynamic>.from(item));
        if (draft.uploadState == AttachmentUploadState.removed) continue;
        final hasLocalCopy =
            draft.localPath.isNotEmpty && File(draft.localPath).existsSync();
        final hasReusableRemote =
            draft.uploadState == AttachmentUploadState.attached &&
            draft.remoteRef?.isNotEmpty == true &&
            draft.remoteSessionId?.isNotEmpty == true;
        if (hasLocalCopy || hasReusableRemote) {
          attachments.add(draft);
        }
      }
      final draft = ChatDraft(
        text: (data['text'] ?? '').toString(),
        attachments: attachments,
        missionRoomIntentId: _safeMetadata(
          data['missionRoomIntentId'],
          maxLength: 128,
        ),
        missionRoomWorkerProfile: _safeMetadata(
          data['missionRoomWorkerProfile'],
          maxLength: 64,
          pattern: RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$'),
        ),
        missionRoomBoardId: _safeMetadata(
          data['missionRoomBoardId'],
          maxLength: 128,
        ),
        missionRoomBoardQuery: _safeMetadata(
          data['missionRoomBoardQuery'],
          maxLength: 128,
        ),
        missionRoomTaskPhase: roomTaskPhase,
      );
      if (draft.text.isEmpty && draft.attachments.isEmpty) return null;
      return ChatDraftEntry(
        sessionId: sessionId,
        profile: profile,
        savedAt: savedAt,
        draft: draft,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ChatDraft> load(
    String connectionId,
    String sessionId, {
    String profile = 'default',
    bool claimUnscopedLegacy = false,
  }) async {
    final owner = profile.trim().isEmpty ? 'default' : profile.trim();
    final key = _key(connectionId, sessionId, owner);
    final pendingMutation = _mutationTails[key];
    if (pendingMutation != null) await pendingMutation;
    var raw = await _secure.read(key: key);
    final ownsUnscopedLegacy =
        owner == 'default' ||
        claimUnscopedLegacy ||
        sessionId.startsWith('mob-room-') ||
        sessionId.startsWith('mob-bot-');
    if ((raw == null || raw.isEmpty) && ownsUnscopedLegacy) {
      final unscopedKey = _unscopedV2Key(connectionId, sessionId);
      final unscoped = await _secure.read(key: unscopedKey);
      if (unscoped != null && unscoped.isNotEmpty) {
        await _secure.write(key: key, value: unscoped);
        await _secure.delete(key: unscopedKey);
        raw = unscoped;
      }
    }
    if (raw == null || raw.isEmpty) {
      // Migración única de versiones que guardaban el borrador en claro.
      final legacyKey = _legacyKey(connectionId, sessionId);
      final legacy = _prefs.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          final decoded = jsonDecode(legacy) as Map<String, dynamic>;
          decoded['savedAt'] = DateTime.now().millisecondsSinceEpoch;
          raw = jsonEncode(decoded);
          await _secure.write(key: key, value: raw);
        } catch (_) {
          raw = null;
        } finally {
          // Incluso un legacy corrupto no debe permanecer indefinidamente en
          // claro; si la migración falla, el llamador lo tratará como vacío.
          await _prefs.remove(legacyKey);
        }
      }
    }
    if (raw == null || raw.isEmpty) {
      return const ChatDraft(text: '', attachments: []);
    }
    final entry = _decodeEntry(sessionId, owner, raw);
    if (entry == null) {
      await clear(connectionId, sessionId, profile: owner);
      return const ChatDraft(text: '', attachments: []);
    }
    return entry.draft;
  }

  /// Lista borradores vivos de una conexión para que Inicio/Conversaciones
  /// puedan reabrir chats aún no materializados en Hermes.
  Future<List<ChatDraftEntry>> listForConnection(String connectionId) async {
    final prefix = 'chat_draft_v3.${_scope(connectionId)}.';
    final unscopedPrefix = 'chat_draft_v2_${connectionId}_';
    final entries = <ChatDraftEntry>[];
    final secureEntries = await _secure.readAll();
    for (final item in secureEntries.entries) {
      if (!item.key.startsWith(prefix)) continue;
      final suffix = item.key.substring(prefix.length).split('.');
      if (suffix.length != 2) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      late final String profile;
      late final String sessionId;
      try {
        profile = _unScope(suffix[0]);
        sessionId = _unScope(suffix[1]);
      } catch (_) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      if (profile.isEmpty || sessionId.isEmpty) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      // Bot Chat y Room usan ids/owners móviles estables para rehidratar su
      // propio compositor. Siguen cifrados y cargables por load(owner), pero
      // no son conversaciones genéricas recuperables desde Inicio/Listas.
      // No decodificar ni limpiar aquí: la superficie propietaria conserva la
      // autoridad para validar su edad, FSM y adjuntos cuando vuelva a abrirse.
      if (_belongsToDedicatedSurface(sessionId, profile)) continue;
      final decoded = _decodeEntry(sessionId, profile, item.value);
      if (decoded == null) {
        await _deleteSecureDraft(item.key, item.value);
      } else {
        entries.add(decoded);
      }
    }
    // V2 no tenía owner. Solo el listado genérico del perfil default puede
    // reclamar esas claves; Rooms/Bots y perfiles no-default las migran desde
    // su superficie autoritativa mediante load(... claimUnscopedLegacy: true).
    // Así una actualización no oculta borradores normales ni adivina el dueño
    // de un workstream aislado.
    for (final item in secureEntries.entries) {
      if (!item.key.startsWith(unscopedPrefix)) continue;
      final sessionId = item.key.substring(unscopedPrefix.length);
      if (sessionId.isEmpty) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      if (sessionId.startsWith('mob-room-') ||
          sessionId.startsWith('mob-bot-')) {
        // These stable mobile surface ids are claimed with the authoritative
        // manager/profile owner when that Room/Bot is opened. Migrating them
        // here to `default` makes the owner-specific load miss the draft.
        continue;
      }
      final canonicalKey = _key(connectionId, sessionId, 'default');
      if (secureEntries.containsKey(canonicalKey)) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      final decoded = _decodeEntry(sessionId, 'default', item.value);
      if (decoded == null) {
        await _deleteSecureDraft(item.key, item.value);
        continue;
      }
      await _secure.write(key: canonicalKey, value: item.value);
      await _secure.delete(key: item.key);
      entries.add(decoded);
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  Future<void> save(
    String connectionId,
    String sessionId,
    String text,
    List<AttachmentDraft> attachments, {
    String profile = 'default',
    String? missionRoomIntentId,
    String? missionRoomWorkerProfile,
    String? missionRoomBoardId,
    String? missionRoomBoardQuery,
    MissionRoomTaskPhase? missionRoomTaskPhase,
  }) async {
    final normalizedAttachments = attachments
        .where((item) => item.uploadState != AttachmentUploadState.removed)
        .map(
          (item) => item.localId.isEmpty
              ? AttachmentDraft.fromJson(item.toJson())
              : item,
        )
        .toList(growable: false);
    final owner = profile.trim().isEmpty ? 'default' : profile.trim();
    final key = _key(connectionId, sessionId, owner);
    await _serializeMutation(key, () async {
      if (text.isEmpty && normalizedAttachments.isEmpty) {
        await _clearUnlocked(
          connectionId,
          sessionId,
          owner: owner,
          includeUnscoped: false,
        );
        return;
      }
      final previous = await _secure.read(key: key);
      final removesUnscoped =
          owner == 'default' ||
          sessionId.startsWith('mob-room-') ||
          sessionId.startsWith('mob-bot-');
      final unscopedKey = _unscopedV2Key(connectionId, sessionId);
      final unscopedPrevious = removesUnscoped
          ? await _secure.read(key: unscopedKey)
          : null;
      final legacyKey = _legacyKey(connectionId, sessionId);
      final legacyPrevious = _prefs.getString(legacyKey);
      final safeIntentId = _safeMetadata(missionRoomIntentId, maxLength: 128);
      final safeWorker = _safeMetadata(
        missionRoomWorkerProfile,
        maxLength: 64,
        pattern: RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$'),
      );
      final safeBoardId = _safeMetadata(missionRoomBoardId, maxLength: 128);
      final safeBoardQuery = _safeMetadata(
        missionRoomBoardQuery,
        maxLength: 128,
      );
      final safePhase = safeIntentId != null && safeWorker != null
          ? missionRoomTaskPhase
          : null;
      await _secure.write(
        key: key,
        value: jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'text': text,
          'missionRoomIntentId': ?safeIntentId,
          'missionRoomWorkerProfile': ?safeWorker,
          'missionRoomBoardId': ?safeBoardId,
          'missionRoomBoardQuery': ?safeBoardQuery,
          'missionRoomTaskPhase': ?safePhase?.name,
          'attachments': normalizedAttachments
              .map((item) => item.toJson())
              .toList(),
        }),
      );
      if (removesUnscoped) {
        await _secure.delete(key: unscopedKey);
      }
      await _prefs.remove(legacyKey);
      await _cleanupUnowned([
        if (previous != null) ..._attachmentsFromRaw(previous),
        if (unscopedPrevious != null) ..._attachmentsFromRaw(unscopedPrevious),
        if (legacyPrevious != null) ..._attachmentsFromRaw(legacyPrevious),
      ]);
    });
  }

  static String? _safeMetadata(
    Object? value, {
    required int maxLength,
    RegExp? pattern,
  }) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maxLength ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
        (pattern != null && !pattern.hasMatch(normalized))) {
      return null;
    }
    return normalized;
  }

  static MissionRoomTaskPhase? _taskPhase(Object? value) {
    if (value is! String) return null;
    for (final phase in MissionRoomTaskPhase.values) {
      if (phase.name == value) return phase;
    }
    return null;
  }

  Future<void> clear(
    String connectionId,
    String sessionId, {
    String profile = 'default',
    bool includeUnscoped = false,
  }) async {
    final owner = profile.trim().isEmpty ? 'default' : profile.trim();
    final key = _key(connectionId, sessionId, owner);
    await _serializeMutation(
      key,
      () => _clearUnlocked(
        connectionId,
        sessionId,
        owner: owner,
        includeUnscoped: includeUnscoped,
      ),
    );
  }

  Future<void> _clearUnlocked(
    String connectionId,
    String sessionId, {
    required String owner,
    required bool includeUnscoped,
  }) async {
    final key = _key(connectionId, sessionId, owner);
    final raw = await _secure.read(key: key);
    await _secure.delete(key: key);
    String? unscoped;
    if (includeUnscoped ||
        owner == 'default' ||
        sessionId.startsWith('mob-room-') ||
        sessionId.startsWith('mob-bot-')) {
      final unscopedKey = _unscopedV2Key(connectionId, sessionId);
      unscoped = await _secure.read(key: unscopedKey);
      await _secure.delete(key: unscopedKey);
    }
    final legacyKey = _legacyKey(connectionId, sessionId);
    final legacy = _prefs.getString(legacyKey);
    await _prefs.remove(legacyKey);
    await _cleanupUnowned([
      if (raw != null) ..._attachmentsFromRaw(raw),
      if (unscoped != null) ..._attachmentsFromRaw(unscoped),
      if (legacy != null) ..._attachmentsFromRaw(legacy),
    ]);
  }

  /// Elimina el borrador de una sesión en todos sus owners conocidos.
  ///
  /// El endpoint de borrado histórico recibe solo el id opaco de sesión. Un
  /// borrador v3, en cambio, también está sellado por perfil; limitar la
  /// limpieza a `default` permite que otro owner reaparezca después de que el
  /// servidor ya confirmó el borrado. La coincidencia sigue siendo exacta por
  /// conexión y sesión, sin tocar borradores vecinos.
  Future<void> clearForSession(String connectionId, String sessionId) async {
    final securePrefix = 'chat_draft_v3.${_scope(connectionId)}.';
    final secureSuffix = '.${_scope(sessionId)}';
    final secureEntries = await _secure.readAll();
    final matchingKeys = secureEntries.keys
        .where(
          (key) => key.startsWith(securePrefix) && key.endsWith(secureSuffix),
        )
        .toList(growable: false);
    final removedAttachments = <AttachmentDraft>[];
    for (final key in matchingKeys) {
      removedAttachments.addAll(_attachmentsFromRaw(secureEntries[key] ?? ''));
      await _secure.delete(key: key);
    }
    final unscopedKey = _unscopedV2Key(connectionId, sessionId);
    final unscoped = secureEntries[unscopedKey];
    if (unscoped != null) {
      removedAttachments.addAll(_attachmentsFromRaw(unscoped));
    }
    await _secure.delete(key: unscopedKey);
    final legacyKey = _legacyKey(connectionId, sessionId);
    final legacy = _prefs.getString(legacyKey);
    if (legacy != null) {
      removedAttachments.addAll(_attachmentsFromRaw(legacy));
    }
    await _prefs.remove(legacyKey);
    await _cleanupUnowned(removedAttachments);
  }

  /// Elimina únicamente borradores pertenecientes a una conexión retirada.
  /// `readAll` nunca se copia a prefs/logs y las demás entradas del Keystore se
  /// conservan intactas.
  Future<int> deleteForConnection(String connectionId) async {
    final securePrefix = 'chat_draft_v3.${_scope(connectionId)}.';
    final unscopedPrefix = 'chat_draft_v2_${connectionId}_';
    final legacyPrefix = 'chat_draft_v1_${connectionId}_';
    var removed = 0;
    final removedAttachments = <AttachmentDraft>[];
    final secureEntries = await _secure.readAll();
    for (final key in secureEntries.keys.where(
      (key) => key.startsWith(securePrefix) || key.startsWith(unscopedPrefix),
    )) {
      removedAttachments.addAll(_attachmentsFromRaw(secureEntries[key] ?? ''));
      await _secure.delete(key: key);
      removed++;
    }
    for (final key in _prefs.getKeys().where(
      (key) => key.startsWith(legacyPrefix),
    )) {
      removedAttachments.addAll(
        _attachmentsFromRaw(_prefs.getString(key) ?? ''),
      );
      await _prefs.remove(key);
      removed++;
    }
    await _cleanupUnowned(removedAttachments);
    return removed;
  }

  Future<void> _deleteSecureDraft(String key, String raw) async {
    await _secure.delete(key: key);
    await _cleanupUnowned(_attachmentsFromRaw(raw));
  }

  Future<void> _cleanupUnowned(List<AttachmentDraft> candidates) async {
    if (candidates.isEmpty) return;
    late final Map<String, String> remaining;
    try {
      remaining = await _secure.readAll();
    } catch (_) {
      // Si no podemos demostrar que no queda otro owner, no borramos nada.
      return;
    }
    final decoded = <Object?>[];
    for (final raw in remaining.values) {
      try {
        decoded.add(jsonDecode(raw));
      } catch (_) {}
    }
    final visitedPaths = <String>{};
    for (final candidate in candidates) {
      if (candidate.localPath.isEmpty ||
          !visitedPaths.add(candidate.localPath) ||
          decoded.any((value) => _referencesAttachment(value, candidate))) {
        continue;
      }
      await _deletePrivateCopy(candidate);
    }
  }
}

List<AttachmentDraft> _attachmentsFromRaw(String raw) {
  try {
    final decoded = jsonDecode(raw);
    final result = <AttachmentDraft>[];
    void visit(Object? value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('local_path') && map.containsKey('type')) {
        result.add(AttachmentDraft.fromJson(map));
        return;
      }
      for (final nested in map.values) {
        visit(nested);
      }
    }

    visit(decoded);
    return result;
  } catch (_) {
    return const [];
  }
}

bool _referencesAttachment(Object? value, AttachmentDraft target) {
  if (value is List) {
    return value.any((item) => _referencesAttachment(item, target));
  }
  if (value is! Map) return false;
  final map = Map<String, dynamic>.from(value);
  if ((map['upload_state'] ?? '').toString() ==
      AttachmentUploadState.removed.name) {
    return false;
  }
  if ((map['local_path'] ?? '').toString() == target.localPath) {
    final storedId = (map['local_id'] ?? '').toString();
    if (storedId.isEmpty ||
        target.localId.isEmpty ||
        storedId == target.localId) {
      return true;
    }
  }
  return map.values.any((nested) => _referencesAttachment(nested, target));
}
