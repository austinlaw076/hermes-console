import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AttachmentType { image, document, unknown }

enum AttachmentUploadState { pending, uploading, error, attached, removed }

enum AttachmentRemoteTransport { desktop, rest, bridgeLocal }

enum AttachmentErrorKind {
  missingFile,
  invalidFile,
  tooLarge,
  unsupportedType,
  persistence,
  interrupted,
  transport,
}

const _unsetAttachmentValue = Object();

class AttachmentDraft {
  /// Identidad estable del chip. Los constructores legacy pueden omitirla para
  /// seguir siendo `const`; al deserializar se deriva una identidad estable.
  final String localId;
  final AttachmentType type;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String localPath;
  final AttachmentUploadState uploadState;
  final int attempt;
  final AttachmentErrorKind? errorKind;

  /// Referencia devuelta por `image.attach_bytes`/`file.attach`.
  final String? remoteRef;

  /// Runtime Desktop propietario de [remoteRef]. Una referencia nunca se
  /// reutiliza al reanudar sobre otro runtime.
  final String? remoteSessionId;
  final AttachmentRemoteTransport? remoteTransport;

  const AttachmentDraft({
    this.localId = '',
    required this.type,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.localPath,
    this.uploadState = AttachmentUploadState.pending,
    this.attempt = 0,
    this.errorKind,
    this.remoteRef,
    this.remoteSessionId,
    this.remoteTransport,
  });

  Map<String, dynamic> toJson() => {
    'local_id': localId,
    'type': type.name,
    'name': name,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'local_path': localPath,
    'upload_state': uploadState.name,
    'attempt': attempt,
    if (errorKind != null) 'error_kind': errorKind!.name,
    if (remoteRef != null) 'remote_ref': remoteRef,
    if (remoteSessionId != null) 'remote_session_id': remoteSessionId,
    if (remoteTransport != null) 'remote_transport': remoteTransport!.name,
  };

  factory AttachmentDraft.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString();
    final type = AttachmentType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => AttachmentType.unknown,
    );
    final name = (json['name'] ?? '').toString();
    final mimeType = (json['mime_type'] ?? '').toString();
    final sizeBytes = (json['size_bytes'] as num?)?.toInt() ?? 0;
    final localPath = (json['local_path'] ?? '').toString();
    final persistedId = (json['local_id'] ?? '').toString();
    final rawState = (json['upload_state'] ?? '').toString();
    final rawError = (json['error_kind'] ?? '').toString();
    final rawRemoteTransport = (json['remote_transport'] ?? '').toString();
    return AttachmentDraft(
      localId: persistedId.isNotEmpty
          ? persistedId
          : _legacyAttachmentId(
              type: type,
              name: name,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
              localPath: localPath,
            ),
      type: type,
      name: name,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      localPath: localPath,
      uploadState: AttachmentUploadState.values.firstWhere(
        (value) => value.name == rawState,
        orElse: () => AttachmentUploadState.pending,
      ),
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      errorKind: rawError.isEmpty
          ? null
          : AttachmentErrorKind.values.firstWhere(
              (value) => value.name == rawError,
              orElse: () => AttachmentErrorKind.transport,
            ),
      remoteRef: _nullableString(json['remote_ref']),
      remoteSessionId: _nullableString(json['remote_session_id']),
      remoteTransport: rawRemoteTransport.isEmpty
          ? null
          : AttachmentRemoteTransport.values.firstWhere(
              (value) => value.name == rawRemoteTransport,
              orElse: () => AttachmentRemoteTransport.desktop,
            ),
    );
  }

  AttachmentDraft copyWith({
    String? localId,
    AttachmentType? type,
    String? name,
    String? mimeType,
    int? sizeBytes,
    String? localPath,
    AttachmentUploadState? uploadState,
    int? attempt,
    Object? errorKind = _unsetAttachmentValue,
    Object? remoteRef = _unsetAttachmentValue,
    Object? remoteSessionId = _unsetAttachmentValue,
    Object? remoteTransport = _unsetAttachmentValue,
  }) => AttachmentDraft(
    localId: localId ?? this.localId,
    type: type ?? this.type,
    name: name ?? this.name,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    localPath: localPath ?? this.localPath,
    uploadState: uploadState ?? this.uploadState,
    attempt: attempt ?? this.attempt,
    errorKind: identical(errorKind, _unsetAttachmentValue)
        ? this.errorKind
        : errorKind as AttachmentErrorKind?,
    remoteRef: identical(remoteRef, _unsetAttachmentValue)
        ? this.remoteRef
        : remoteRef as String?,
    remoteSessionId: identical(remoteSessionId, _unsetAttachmentValue)
        ? this.remoteSessionId
        : remoteSessionId as String?,
    remoteTransport: identical(remoteTransport, _unsetAttachmentValue)
        ? this.remoteTransport
        : remoteTransport as AttachmentRemoteTransport?,
  );

  /// Compara solo la identidad inmutable del fichero, no el progreso de upload.
  bool sameSourceAs(AttachmentDraft other) {
    if (localId.isNotEmpty && other.localId.isNotEmpty) {
      return localId == other.localId;
    }
    return type == other.type &&
        name == other.name &&
        mimeType == other.mimeType &&
        sizeBytes == other.sizeBytes &&
        localPath == other.localPath;
  }

  bool acceptsCallback({required String localId, required int attempt}) =>
      uploadState == AttachmentUploadState.uploading &&
      this.localId == localId &&
      this.attempt == attempt;

  bool isAttachedTo(
    String runtimeSessionId, {
    AttachmentRemoteTransport transport = AttachmentRemoteTransport.desktop,
  }) =>
      uploadState == AttachmentUploadState.attached &&
      remoteRef?.isNotEmpty == true &&
      remoteSessionId == runtimeSessionId &&
      remoteTransport == transport;

  AttachmentDraft resetForRemoteOwner({
    required String remoteSessionId,
    required AttachmentRemoteTransport transport,
  }) {
    if (uploadState != AttachmentUploadState.attached ||
        isAttachedTo(remoteSessionId, transport: transport)) {
      return this;
    }
    return copyWith(
      uploadState: AttachmentUploadState.pending,
      errorKind: null,
      remoteRef: null,
      remoteSessionId: null,
      remoteTransport: null,
    );
  }

  bool canTransitionTo(AttachmentUploadState next) {
    if (next == uploadState) return true;
    if (uploadState == AttachmentUploadState.removed) return false;
    if (next == AttachmentUploadState.removed) return true;
    return switch (uploadState) {
      AttachmentUploadState.pending => next == AttachmentUploadState.uploading,
      AttachmentUploadState.uploading =>
        next == AttachmentUploadState.attached ||
            next == AttachmentUploadState.error,
      AttachmentUploadState.error =>
        next == AttachmentUploadState.pending ||
            next == AttachmentUploadState.uploading,
      AttachmentUploadState.attached =>
        next == AttachmentUploadState.pending ||
            next == AttachmentUploadState.uploading,
      AttachmentUploadState.removed => false,
    };
  }

  bool get isImage => type == AttachmentType.image;

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1048576) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';
  }

  String get messageLabel =>
      formattedSize.isEmpty ? name : '$name · $formattedSize';
}

String? _nullableString(Object? value) {
  final normalized = (value ?? '').toString();
  return normalized.isEmpty ? null : normalized;
}

String _legacyAttachmentId({
  required AttachmentType type,
  required String name,
  required String mimeType,
  required int sizeBytes,
  required String localPath,
}) {
  final input =
      '$type\u0000$name\u0000$mimeType\u0000$sizeBytes\u0000$localPath';
  return 'legacy-${sha256.convert(utf8.encode(input))}';
}
