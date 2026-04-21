import 'package:locus/src/shared/models/json_map.dart';

/// Immutable snapshot of the native SyncManager's pause state.
///
/// Emitted by the native side on every pause transition (explicit
/// `Locus.dataSync.pause()`, 401/403 auto-pause, `resume()` clears, and the
/// initial replay when a Dart listener first attaches). Consumers can observe
/// changes via `Locus.dataSync.pauseChanges` or read the most recent value
/// synchronously via `Locus.dataSync.isPaused` / `Locus.dataSync.pauseReason`.
///
/// [reason] is one of:
///   * `null` — sync is active.
///   * `"app"` — explicit `Locus.dataSync.pause()` call (in-memory only).
///   * `"http_401"` — backend returned 401; persists across process restarts
///     until `resume()` is called or a subsequent 2xx is seen.
///   * `"http_403"` — backend returned 403; same persistence semantics as 401.
class SyncPauseState {
  const SyncPauseState({required this.isPaused, this.reason});

  factory SyncPauseState.fromMap(JsonMap map) {
    return SyncPauseState(
      isPaused: map['isPaused'] as bool? ?? false,
      reason: map['reason'] as String?,
    );
  }

  /// Whether the native SyncManager will currently dispatch HTTP requests.
  final bool isPaused;

  /// Null when unpaused; otherwise `"app"` / `"http_401"` / `"http_403"`.
  final String? reason;

  bool get isAuthFailure => reason == 'http_401' || reason == 'http_403';

  JsonMap toMap() => <String, dynamic>{
        'isPaused': isPaused,
        if (reason != null) 'reason': reason,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncPauseState &&
          other.isPaused == isPaused &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(isPaused, reason);

  @override
  String toString() => 'SyncPauseState(isPaused: $isPaused, reason: $reason)';
}
