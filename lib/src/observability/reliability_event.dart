/// Reliability events expose anything that affects the answer to "did our
/// captured locations actually reach the backend?". Subscribe via
/// `Locus.reliability` and forward into your app's telemetry pipeline.
///
/// Every event carries the wall-clock timestamp at which it was raised, plus
/// fields specific to the situation. The hierarchy is sealed so embedders can
/// pattern-match exhaustively.
library;

/// Base class for all reliability events emitted by the SDK.
sealed class LocusReliabilityEvent {
  LocusReliabilityEvent({DateTime? occurredAt})
      : occurredAt = occurredAt ?? DateTime.now().toUtc();

  /// Wall-clock UTC timestamp at which the event was raised.
  final DateTime occurredAt;
}

/// Why a queued location was discarded by the SDK.
enum EvictionReason {
  /// The location was older than the configured retention window.
  ageLimit,

  /// The on-device queue exceeded the configured maximum row count.
  countLimit,
}

/// Emitted when the SDK drops queued locations to keep storage bounded.
final class PointsEvicted extends LocusReliabilityEvent {
  PointsEvicted({
    required this.count,
    required this.reason,
    super.occurredAt,
  }) : assert(count > 0, 'PointsEvicted count must be positive');

  /// Number of rows deleted in this eviction round.
  final int count;

  /// Whether eviction was driven by retention age or by row count.
  final EvictionReason reason;

  @override
  String toString() => 'PointsEvicted(count: $count, reason: ${reason.name})';
}

/// Emitted when the quarantine row count grows. Quarantined locations are
/// records that the pre-sync validator rejected — they sit in storage but
/// will not be sent until the validator's blocker is cleared (e.g. missing
/// owner id is filled in) or until the SDK's quarantine janitor purges them.
final class QuarantineGrew extends LocusReliabilityEvent {
  QuarantineGrew({
    required this.totalQuarantined,
    this.reasonHint,
    super.occurredAt,
  });

  /// Current quarantine size after the event was raised.
  final int totalQuarantined;

  /// Optional short reason hint, e.g. `missing_owner_id`, `invalid_coords`.
  final String? reasonHint;

  @override
  String toString() =>
      'QuarantineGrew(totalQuarantined: $totalQuarantined, reasonHint: $reasonHint)';
}

/// Emitted when the SDK's quarantine janitor purges quarantined records
/// older than [olderThan].
final class QuarantinePurged extends LocusReliabilityEvent {
  QuarantinePurged({
    required this.count,
    required this.olderThan,
    super.occurredAt,
  }) : assert(count > 0, 'QuarantinePurged count must be positive');

  /// Number of rows discarded.
  final int count;

  /// Age threshold that triggered the discard.
  final Duration olderThan;

  @override
  String toString() => 'QuarantinePurged(count: $count, olderThan: $olderThan)';
}

/// Emitted when sync has failed long enough to warrant an operator alert
/// but is still considered recoverable.
final class SyncStalled extends LocusReliabilityEvent {
  SyncStalled({
    required this.sinceLastSuccess,
    required this.consecutiveFailures,
    this.lastHttpStatus,
    super.occurredAt,
  });

  /// How long it has been since the last successful sync.
  final Duration sinceLastSuccess;

  /// Number of consecutive failed attempts.
  final int consecutiveFailures;

  /// HTTP status of the last attempt (null if there was no response, e.g.
  /// network error).
  final int? lastHttpStatus;

  @override
  String toString() =>
      'SyncStalled(sinceLastSuccess: $sinceLastSuccess, consecutiveFailures: $consecutiveFailures, lastHttpStatus: $lastHttpStatus)';
}

/// Emitted when sync has been failing for so long that operator intervention
/// is required. The SDK keeps the data queued; resume is a manual action.
final class SyncUnrecoverable extends LocusReliabilityEvent {
  SyncUnrecoverable({
    required this.sinceLastSuccess,
    required this.consecutiveFailures,
    this.lastHttpStatus,
    super.occurredAt,
  });

  /// How long it has been since the last successful sync.
  final Duration sinceLastSuccess;

  /// Number of consecutive failed attempts.
  final int consecutiveFailures;

  /// HTTP status of the last attempt (null on transport-level errors).
  final int? lastHttpStatus;

  @override
  String toString() =>
      'SyncUnrecoverable(sinceLastSuccess: $sinceLastSuccess, consecutiveFailures: $consecutiveFailures, lastHttpStatus: $lastHttpStatus)';
}

/// Emitted when an underlying storage operation throws (insert, delete,
/// prune). Treated as a critical reliability incident by embedders.
final class PersistenceFailure extends LocusReliabilityEvent {
  PersistenceFailure({
    required this.operation,
    required this.message,
    super.occurredAt,
  });

  /// Logical operation that failed: `insert`, `delete`, `prune`.
  final String operation;

  /// Best-effort human-readable description of the failure.
  final String message;

  @override
  String toString() =>
      'PersistenceFailure(operation: $operation, message: $message)';
}
