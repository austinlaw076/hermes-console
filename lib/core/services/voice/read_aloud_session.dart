import 'package:flutter/foundation.dart';

import 'speech_renderer.dart';

enum ReadAloudPhase {
  idle,
  preparing,
  playing,
  waitingBoundary,
  paused,
  failed,
}

enum ReadAloudOrigin { manual, automatic }

class ReadAloudChunk {
  final String text;
  final NarrationPause pauseAfter;

  const ReadAloudChunk(this.text, this.pauseAfter);
}

class ReadAloudSnapshot {
  final ReadAloudPhase phase;
  final String? messageKey;
  final String? revision;
  final List<ReadAloudChunk> chunks;
  final int cursor;
  final int epoch;
  final ReadAloudOrigin? origin;
  final Object? error;

  const ReadAloudSnapshot({
    required this.phase,
    required this.messageKey,
    required this.revision,
    required this.chunks,
    required this.cursor,
    required this.epoch,
    required this.origin,
    this.error,
  });

  const ReadAloudSnapshot.idle({int epoch = 0})
    : this(
        phase: ReadAloudPhase.idle,
        messageKey: null,
        revision: null,
        chunks: const [],
        cursor: 0,
        epoch: epoch,
        origin: null,
      );

  bool get isActive =>
      phase == ReadAloudPhase.preparing ||
      phase == ReadAloudPhase.playing ||
      phase == ReadAloudPhase.waitingBoundary;

  bool get isResumable =>
      phase == ReadAloudPhase.paused || phase == ReadAloudPhase.failed;

  bool owns(String key) => messageKey == key;

  ReadAloudSnapshot copyWith({
    ReadAloudPhase? phase,
    String? messageKey,
    String? revision,
    List<ReadAloudChunk>? chunks,
    int? cursor,
    int? epoch,
    ReadAloudOrigin? origin,
    Object? error,
    bool clearError = false,
  }) => ReadAloudSnapshot(
    phase: phase ?? this.phase,
    messageKey: messageKey ?? this.messageKey,
    revision: revision ?? this.revision,
    chunks: chunks ?? this.chunks,
    cursor: cursor ?? this.cursor,
    epoch: epoch ?? this.epoch,
    origin: origin ?? this.origin,
    error: clearError ? null : error ?? this.error,
  );
}

/// Reducer síncrono de una única lectura global. Las operaciones asíncronas
/// conservan la epoch que recibieron; cualquier toque posterior la invalida y
/// sus completions tardíos pasan a ser no-ops.
class ReadAloudSession {
  final ValueNotifier<ReadAloudSnapshot> state = ValueNotifier(
    const ReadAloudSnapshot.idle(),
  );
  int _epoch = 0;

  ReadAloudSnapshot get snapshot => state.value;

  ReadAloudChunk? get currentChunk {
    final current = snapshot;
    if (current.cursor < 0 || current.cursor >= current.chunks.length) {
      return null;
    }
    return current.chunks[current.cursor];
  }

  int begin({
    required String messageKey,
    required String revision,
    required List<ReadAloudChunk> chunks,
    required ReadAloudOrigin origin,
  }) {
    final epoch = ++_epoch;
    state.value = ReadAloudSnapshot(
      phase: ReadAloudPhase.preparing,
      messageKey: messageKey,
      revision: revision,
      chunks: List.unmodifiable(chunks),
      cursor: 0,
      epoch: epoch,
      origin: origin,
    );
    return epoch;
  }

  int resume() {
    final current = snapshot;
    if (!current.isResumable || current.cursor >= current.chunks.length) {
      return current.epoch;
    }
    final epoch = ++_epoch;
    state.value = current.copyWith(
      phase: ReadAloudPhase.preparing,
      epoch: epoch,
      clearError: true,
    );
    return epoch;
  }

  void markPlaying(int epoch) {
    if (!isCurrent(epoch)) return;
    state.value = snapshot.copyWith(phase: ReadAloudPhase.playing);
  }

  void markWaitingBoundary(int epoch) {
    if (!isCurrent(epoch)) return;
    state.value = snapshot.copyWith(phase: ReadAloudPhase.waitingBoundary);
  }

  /// Avanza el cursor únicamente cuando el motor confirmó el chunk vigente.
  /// Devuelve true si la lectura terminó por completo.
  bool completeChunk(int epoch) {
    if (!isCurrent(epoch)) return false;
    final next = snapshot.cursor + 1;
    if (next >= snapshot.chunks.length) {
      state.value = ReadAloudSnapshot.idle(epoch: epoch);
      return true;
    }
    state.value = snapshot.copyWith(cursor: next);
    return false;
  }

  void fail(int epoch, Object error) {
    if (!isCurrent(epoch)) return;
    state.value = snapshot.copyWith(phase: ReadAloudPhase.failed, error: error);
  }

  /// Invalida primero la epoch. Con [discard] false conserva el cursor; con
  /// true elimina toda la sesión para que el siguiente toque empiece en cero.
  void pause({required bool discard}) {
    final current = snapshot;
    final epoch = ++_epoch;
    if (discard || current.phase == ReadAloudPhase.idle) {
      state.value = ReadAloudSnapshot.idle(epoch: epoch);
      return;
    }
    state.value = current.copyWith(
      phase: ReadAloudPhase.paused,
      epoch: epoch,
      clearError: true,
    );
  }

  void discard() => pause(discard: true);

  bool isCurrent(int epoch) =>
      snapshot.epoch == epoch && snapshot.phase != ReadAloudPhase.idle;

  void dispose() => state.dispose();
}

List<ReadAloudChunk> chunkNarrationSegments(
  List<NarrationSegment> segments, {
  int maxChars = 160,
}) {
  assert(maxChars > 0);
  final result = <ReadAloudChunk>[];
  for (final segment in segments) {
    final sentences = segment.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(RegExp(r'(?<=[.!?…])\s+'))
        .where((part) => part.trim().isNotEmpty);
    final derived = <String>[];
    for (final sentence in sentences) {
      derived.addAll(_splitAtWordBoundaries(sentence.trim(), maxChars));
    }
    for (var index = 0; index < derived.length; index++) {
      result.add(
        ReadAloudChunk(
          derived[index],
          index == derived.length - 1
              ? segment.pauseAfter
              : NarrationPause.none,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

List<String> _splitAtWordBoundaries(String text, int maxChars) {
  if (text.length <= maxChars) return [text];
  final result = <String>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (word.length > maxChars) {
      if (current.isNotEmpty) {
        result.add(current);
        current = '';
      }
      result.addAll(_splitLongToken(word, maxChars));
      continue;
    }
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= maxChars) {
      current = '$current $word';
    } else {
      result.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) result.add(current);
  return result;
}

List<String> _splitLongToken(String token, int maxChars) {
  final result = <String>[];
  final buffer = StringBuffer();
  var codeUnits = 0;
  for (final rune in token.runes) {
    final runeText = String.fromCharCode(rune);
    if (codeUnits + runeText.length > maxChars && buffer.isNotEmpty) {
      result.add(buffer.toString());
      buffer.clear();
      codeUnits = 0;
    }
    buffer.write(runeText);
    codeUnits += runeText.length;
  }
  if (buffer.isNotEmpty) result.add(buffer.toString());
  return result;
}
