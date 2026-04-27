/// SDK-internal counter surface backing `Locus.metrics`.
///
/// Counters are read-only from the public API. The SDK's internal write
/// paths (insertion, sync success/failure, eviction, quarantine) increment
/// them via the registry in `locus_reliability_registry.dart`.
library;

/// Immutable snapshot of the SDK's reliability counters.
///
/// All counters are cumulative since the SDK was installed (or since the last
/// call to [LocusMetrics.reset]) except [pointsQuarantinedNow], which reports
/// the *current* quarantine row count rather than the lifetime total.
final class LocusMetricsSnapshot {
  const LocusMetricsSnapshot({
    required this.pointsCaptured,
    required this.pointsSent,
    required this.pointsDropped,
    required this.pointsQuarantinedNow,
    required this.syncAttemptsTotal,
    required this.syncAttemptsFailed,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  /// Locations recorded by the SDK (before any filtering or eviction).
  final int pointsCaptured;

  /// Locations the backend acknowledged with a 2xx response.
  final int pointsSent;

  /// Locations dropped by the SDK due to age or queue overflow.
  final int pointsDropped;

  /// Current count of locations sitting in quarantine, awaiting validator
  /// resolution or auto-purge.
  final int pointsQuarantinedNow;

  /// Number of sync attempts (successful + failed).
  final int syncAttemptsTotal;

  /// Number of failed sync attempts (HTTP non-2xx or transport error).
  final int syncAttemptsFailed;

  /// Timestamp of the last successful sync, if any.
  final DateTime? lastSuccessAt;

  /// Timestamp of the last failed sync attempt, if any.
  final DateTime? lastFailureAt;

  /// JSON-encodable representation. Useful for diagnostics dumps.
  Map<String, Object?> toJson() => <String, Object?>{
        'points_captured': pointsCaptured,
        'points_sent': pointsSent,
        'points_dropped': pointsDropped,
        'points_quarantined_now': pointsQuarantinedNow,
        'sync_attempts_total': syncAttemptsTotal,
        'sync_attempts_failed': syncAttemptsFailed,
        'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
        'last_failure_at': lastFailureAt?.toUtc().toIso8601String(),
      };

  @override
  String toString() => 'LocusMetricsSnapshot(${toJson()})';
}

/// Read-only view of the SDK's reliability counters.
///
/// Returned by `Locus.metrics`. Embedders can periodically `snapshot()` it,
/// e.g. inside a tracking heartbeat, and forward the values to dashboards.
abstract class LocusMetrics {
  /// Returns a point-in-time snapshot of the counters.
  Future<LocusMetricsSnapshot> snapshot();

  /// Resets all counters to zero. Intended for tests and manual recovery
  /// (e.g. after an SDK reinstall when stale counters would mislead alerts).
  Future<void> reset();
}
