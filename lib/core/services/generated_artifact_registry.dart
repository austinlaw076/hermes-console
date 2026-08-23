import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/generated_artifact.dart';
import '../utils/generated_artifact_detector.dart';

/// Fuente única, acotada y solo en memoria para artifacts generados.
///
/// El transcript sigue siendo la copia durable. La app reconstruye este
/// registro al hidratar mensajes y nunca guarda HTML/código en preferencias.
final class GeneratedArtifactRegistry extends ChangeNotifier {
  static const int maxArtifactsPerSession = 24;
  static const int maxVersionsPerArtifact = 20;
  static const int maxSessions = 40;

  /// Límites de memoria, medidos en unidades UTF-16 de [String.length]. Una
  /// versión que los supera se rechaza completa: nunca se guarda un prefijo
  /// que luego copiar/compartir pudiera presentar como el artifact original.
  static const int defaultMaxCharactersPerVersion = 1000000;
  static const int defaultMaxRetainedCharacters = 8000000;

  static final GeneratedArtifactRegistry shared = GeneratedArtifactRegistry();

  final DateTime Function() _clock;
  final int maxCharactersPerVersion;
  final int maxRetainedCharacters;
  Map<String, List<GeneratedArtifactRecord>> _records = const {};
  final Map<String, int> _versionSelection = {};

  GeneratedArtifactRegistry({
    DateTime Function()? clock,
    this.maxCharactersPerVersion = defaultMaxCharactersPerVersion,
    this.maxRetainedCharacters = defaultMaxRetainedCharacters,
  }) : _clock = clock ?? DateTime.now {
    if (maxCharactersPerVersion < 1) {
      throw ArgumentError.value(
        maxCharactersPerVersion,
        'maxCharactersPerVersion',
        'must be positive',
      );
    }
    if (maxRetainedCharacters < maxCharactersPerVersion) {
      throw ArgumentError.value(
        maxRetainedCharacters,
        'maxRetainedCharacters',
        'must be at least maxCharactersPerVersion',
      );
    }
  }

  int get sessionCount => _records.length;

  @visibleForTesting
  int get retainedCharacterCount =>
      _characterCount(_records.values.expand((records) => records));

  List<GeneratedArtifactRecord> artifactsForSession(String? sessionId) {
    final id = sessionId?.trim() ?? '';
    return id.isEmpty ? const [] : _records[id] ?? const [];
  }

  GeneratedArtifactRecord? getArtifact(String artifactId) {
    for (final records in _records.values) {
      for (final record in records) {
        if (record.id == artifactId) return record;
      }
    }
    return null;
  }

  GeneratedArtifactUpsertResult? upsert(
    String? sessionId,
    GeneratedArtifactDetection detection,
    String content,
  ) {
    final id = sessionId?.trim() ?? '';
    if (id.isEmpty ||
        content.isEmpty ||
        content.length > maxCharactersPerVersion) {
      return null;
    }
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > maxCharactersPerVersion) {
      return null;
    }

    final slug = GeneratedArtifactDetector.slug(detection);
    final hash = sha256.convert(utf8.encode(trimmed)).toString();
    final records = _records[id] ?? const <GeneratedArtifactRecord>[];
    final existing = records.where((record) => record.slug == slug).firstOrNull;
    final now = _clock();

    if (existing != null) {
      if (existing.versions.any((version) => version.sha256 == hash)) {
        return GeneratedArtifactUpsertResult(
          artifactId: existing.id,
          record: existing,
          versionAdded: false,
        );
      }
      final versions = <GeneratedArtifactVersion>[
        ...existing.versions,
        GeneratedArtifactVersion(
          content: trimmed,
          createdAt: now,
          sha256: hash,
        ),
      ];
      final retained = versions.length <= maxVersionsPerArtifact
          ? versions
          : versions.sublist(versions.length - maxVersionsPerArtifact);
      if (retained.length != versions.length) {
        _versionSelection.remove(existing.id);
      }
      final next = existing.copyWith(
        title: detection.title.isEmpty ? existing.title : detection.title,
        updatedAt: now,
        versions: retained,
      );
      _records = _prune({
        ..._records,
        id: List<GeneratedArtifactRecord>.unmodifiable(
          records.map((record) => record.id == existing.id ? next : record),
        ),
      });
      final authoritative = getArtifact(next.id) ?? next;
      notifyListeners();
      return GeneratedArtifactUpsertResult(
        artifactId: authoritative.id,
        record: authoritative,
        versionAdded: true,
      );
    }

    final record = GeneratedArtifactRecord(
      createdAt: now,
      id: '$id:$slug',
      kind: detection.kind,
      language: detection.language,
      sessionId: id,
      slug: slug,
      title: detection.title,
      updatedAt: now,
      versions: [
        GeneratedArtifactVersion(
          content: trimmed,
          createdAt: now,
          sha256: hash,
        ),
      ],
    );
    _records = _prune({
      ..._records,
      id: List<GeneratedArtifactRecord>.unmodifiable([...records, record]),
    });
    final authoritative = getArtifact(record.id) ?? record;
    notifyListeners();
    return GeneratedArtifactUpsertResult(
      artifactId: authoritative.id,
      record: authoritative,
      versionAdded: true,
    );
  }

  int selectedVersion(String artifactId) {
    final record = getArtifact(artifactId);
    if (record == null || record.versions.isEmpty) return 0;
    return (_versionSelection[artifactId] ?? record.versions.length - 1).clamp(
      0,
      record.versions.length - 1,
    );
  }

  /// Reconstruye una sesión desde el transcript terminal en orden cronológico.
  /// Se usa al abrir la biblioteca/Session Details, nunca por token. Corrige el
  /// orden aunque la virtualización haya montado antes mensajes más recientes.
  void replaceSession(
    String? sessionId,
    Iterable<GeneratedArtifactInput> chronologicalArtifacts,
  ) {
    final id = sessionId?.trim() ?? '';
    if (id.isEmpty) return;
    final staging = GeneratedArtifactRegistry(
      clock: _clock,
      maxCharactersPerVersion: maxCharactersPerVersion,
      maxRetainedCharacters: maxRetainedCharacters,
    );
    for (final artifact in chronologicalArtifacts) {
      staging.upsert(id, artifact.detection, artifact.content);
    }
    final next = staging.artifactsForSession(id);
    final current = _records[id] ?? const <GeneratedArtifactRecord>[];
    if (_sameRecords(current, next)) return;

    final source = <String, List<GeneratedArtifactRecord>>{..._records};
    if (next.isEmpty) {
      source.remove(id);
    } else {
      source[id] = next;
    }
    _records = _prune(source);
    final liveIds = next.map((record) => record.id).toSet();
    final previousIds = current.map((record) => record.id).toSet();
    _versionSelection.removeWhere(
      (artifactId, _) =>
          previousIds.contains(artifactId) && !liveIds.contains(artifactId),
    );
    notifyListeners();
  }

  void selectVersion(String artifactId, int index) {
    final record = getArtifact(artifactId);
    if (record == null || record.versions.isEmpty) return;
    final clamped = index.clamp(0, record.versions.length - 1);
    if (clamped == record.versions.length - 1) {
      if (_versionSelection.remove(artifactId) != null) notifyListeners();
      return;
    }
    if (_versionSelection[artifactId] == clamped) return;
    _versionSelection[artifactId] = clamped;
    notifyListeners();
  }

  void clear() {
    if (_records.isEmpty && _versionSelection.isEmpty) return;
    _records = const {};
    _versionSelection.clear();
    notifyListeners();
  }

  Map<String, List<GeneratedArtifactRecord>> _prune(
    Map<String, List<GeneratedArtifactRecord>> source,
  ) {
    final entries = <MapEntry<String, List<GeneratedArtifactRecord>>>[];
    for (final entry in source.entries) {
      final records = [...entry.value]
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final trimmed = records.take(maxArtifactsPerSession).toList()
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      if (trimmed.isNotEmpty) {
        entries.add(
          MapEntry(
            entry.key,
            List<GeneratedArtifactRecord>.unmodifiable(trimmed),
          ),
        );
      }
    }
    entries.sort((left, right) {
      DateTime latest(List<GeneratedArtifactRecord> records) => records
          .map((record) => record.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      return latest(right.value).compareTo(latest(left.value));
    });
    final retained = entries.take(maxSessions);
    final result = <String, List<GeneratedArtifactRecord>>{
      for (final entry in retained) entry.key: [...entry.value],
    };
    final resetSelectionIds = <String>{};
    _enforceCharacterBudget(result, resetSelectionIds);
    final liveIds = result.values
        .expand((records) => records)
        .map((record) => record.id)
        .toSet();
    _versionSelection.removeWhere(
      (id, _) => !liveIds.contains(id) || resetSelectionIds.contains(id),
    );
    return Map<String, List<GeneratedArtifactRecord>>.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<GeneratedArtifactRecord>.unmodifiable(entry.value),
    });
  }

  void _enforceCharacterBudget(
    Map<String, List<GeneratedArtifactRecord>> recordsBySession,
    Set<String> resetSelectionIds,
  ) {
    var retainedCharacters = _characterCount(
      recordsBySession.values.expand((records) => records),
    );
    if (retainedCharacters <= maxRetainedCharacters) return;

    final historicalVersions =
        <
          ({
            String sessionId,
            String artifactId,
            String sha256,
            DateTime createdAt,
          })
        >[];
    for (final entry in recordsBySession.entries) {
      for (final record in entry.value) {
        for (var index = 0; index < record.versions.length - 1; index++) {
          final version = record.versions[index];
          historicalVersions.add((
            sessionId: entry.key,
            artifactId: record.id,
            sha256: version.sha256,
            createdAt: version.createdAt,
          ));
        }
      }
    }
    historicalVersions.sort((left, right) {
      final byTime = left.createdAt.compareTo(right.createdAt);
      if (byTime != 0) return byTime;
      final byArtifact = left.artifactId.compareTo(right.artifactId);
      if (byArtifact != 0) return byArtifact;
      return left.sha256.compareTo(right.sha256);
    });

    for (final candidate in historicalVersions) {
      if (retainedCharacters <= maxRetainedCharacters) break;
      final records = recordsBySession[candidate.sessionId];
      if (records == null) continue;
      final recordIndex = records.indexWhere(
        (record) => record.id == candidate.artifactId,
      );
      if (recordIndex < 0) continue;
      final record = records[recordIndex];
      final versionIndex = record.versions.indexWhere(
        (version) => version.sha256 == candidate.sha256,
      );
      if (versionIndex < 0 || versionIndex == record.versions.length - 1) {
        continue;
      }
      final versions = [...record.versions];
      final removed = versions.removeAt(versionIndex);
      records[recordIndex] = record.copyWith(versions: versions);
      retainedCharacters -= removed.content.length;
      resetSelectionIds.add(record.id);
    }

    if (retainedCharacters <= maxRetainedCharacters) return;
    final artifacts =
        <
          ({
            String sessionId,
            String artifactId,
            DateTime updatedAt,
            DateTime createdAt,
          })
        >[];
    for (final entry in recordsBySession.entries) {
      for (final record in entry.value) {
        artifacts.add((
          sessionId: entry.key,
          artifactId: record.id,
          updatedAt: record.updatedAt,
          createdAt: record.createdAt,
        ));
      }
    }
    artifacts.sort((left, right) {
      final byUpdate = left.updatedAt.compareTo(right.updatedAt);
      if (byUpdate != 0) return byUpdate;
      final byCreation = left.createdAt.compareTo(right.createdAt);
      if (byCreation != 0) return byCreation;
      return left.artifactId.compareTo(right.artifactId);
    });

    for (final candidate in artifacts) {
      if (retainedCharacters <= maxRetainedCharacters) break;
      final records = recordsBySession[candidate.sessionId];
      if (records == null) continue;
      final recordIndex = records.indexWhere(
        (record) => record.id == candidate.artifactId,
      );
      if (recordIndex < 0) continue;
      final removed = records.removeAt(recordIndex);
      retainedCharacters -= _characterCount([removed]);
      resetSelectionIds.add(removed.id);
      if (records.isEmpty) recordsBySession.remove(candidate.sessionId);
    }
  }

  static int _characterCount(Iterable<GeneratedArtifactRecord> records) =>
      records.fold<int>(
        0,
        (total, record) =>
            total +
            record.versions.fold<int>(
              0,
              (subtotal, version) => subtotal + version.content.length,
            ),
      );

  static bool _sameRecords(
    List<GeneratedArtifactRecord> left,
    List<GeneratedArtifactRecord> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.kind != b.kind ||
          a.language != b.language ||
          a.title != b.title ||
          a.versions.length != b.versions.length) {
        return false;
      }
      for (var version = 0; version < a.versions.length; version++) {
        if (a.versions[version].sha256 != b.versions[version].sha256) {
          return false;
        }
      }
    }
    return true;
  }
}
