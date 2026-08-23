enum GeneratedArtifactKind { code, html, svg }

final class GeneratedArtifactDetection {
  final GeneratedArtifactKind kind;
  final String language;
  final String title;

  const GeneratedArtifactDetection({
    required this.kind,
    required this.language,
    required this.title,
  });
}

final class GeneratedArtifactInput {
  final GeneratedArtifactDetection detection;
  final String content;

  const GeneratedArtifactInput({
    required this.detection,
    required this.content,
  });
}

final class GeneratedArtifactVersion {
  final String content;
  final DateTime createdAt;
  final String sha256;

  const GeneratedArtifactVersion({
    required this.content,
    required this.createdAt,
    required this.sha256,
  });

  @override
  String toString() =>
      'GeneratedArtifactVersion(${content.length} chars, $sha256)';
}

final class GeneratedArtifactRecord {
  final DateTime createdAt;
  final String id;
  final GeneratedArtifactKind kind;
  final String language;
  final String sessionId;
  final String slug;
  final String title;
  final DateTime updatedAt;
  final List<GeneratedArtifactVersion> versions;

  GeneratedArtifactRecord({
    required this.createdAt,
    required this.id,
    required this.kind,
    required this.language,
    required this.sessionId,
    required this.slug,
    required this.title,
    required this.updatedAt,
    required List<GeneratedArtifactVersion> versions,
  }) : versions = List<GeneratedArtifactVersion>.unmodifiable(versions);

  GeneratedArtifactRecord copyWith({
    String? title,
    DateTime? updatedAt,
    List<GeneratedArtifactVersion>? versions,
  }) => GeneratedArtifactRecord(
    createdAt: createdAt,
    id: id,
    kind: kind,
    language: language,
    sessionId: sessionId,
    slug: slug,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    versions: versions ?? this.versions,
  );

  @override
  String toString() =>
      'GeneratedArtifactRecord(${kind.name}, versions: ${versions.length})';
}

final class GeneratedArtifactUpsertResult {
  final String artifactId;
  final GeneratedArtifactRecord record;
  final bool versionAdded;

  const GeneratedArtifactUpsertResult({
    required this.artifactId,
    required this.record,
    required this.versionAdded,
  });
}
