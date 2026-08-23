import 'dart:async';

/// Serializes read-modify-write operations across the Console-local Mission
/// stores. SharedPreferences writes are atomic per key, but a load followed by
/// a write is not; without this queue concurrent UI callbacks could overwrite
/// a Room link, organization or Bot Chat pin written by the other callback.
abstract final class MissionStoreMutationQueue {
  static Future<void>? _tail;

  static Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_tail, release.future)) _tail = null;
      release.complete();
    }
  }
}
