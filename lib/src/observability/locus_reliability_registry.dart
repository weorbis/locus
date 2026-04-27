import 'dart:async';

import 'package:locus/src/observability/locus_metrics.dart';
import 'package:locus/src/observability/reliability_event.dart';

/// Singleton that holds the SDK's reliability event stream and counters.
///
/// The public surface (`Locus.reliability`, `Locus.metrics`) is a thin
/// re-export of this registry. Internal SDK code (sync, storage, quarantine
/// janitor, ...) calls the `record*` / `emit` methods to feed it.
class LocusReliabilityRegistry {
  LocusReliabilityRegistry._();

  /// Process-wide singleton.
  static final LocusReliabilityRegistry instance = LocusReliabilityRegistry._();

  final _InMemoryLocusMetrics _metrics = _InMemoryLocusMetrics();
  StreamController<LocusReliabilityEvent> _eventController =
      StreamController<LocusReliabilityEvent>.broadcast();

  /// Public stream of reliability events.
  Stream<LocusReliabilityEvent> get reliability => _eventController.stream;

  /// Public read-only metrics view.
  LocusMetrics get metrics => _metrics;

  /// Emit a reliability event to subscribers. Safe to call at any time:
  /// after [resetForTests] closes the controller, the next call will see a
  /// fresh broadcast stream.
  void emit(LocusReliabilityEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  /// Increment the captured-points counter.
  void recordCaptured(int count) {
    if (count <= 0) return;
    _metrics._pointsCaptured += count;
  }

  /// Record a successful sync that flushed [count] points.
  void recordSent(int count, {DateTime? at}) {
    if (count < 0) return;
    final ts = (at ?? DateTime.now()).toUtc();
    _metrics._pointsSent += count;
    _metrics._syncAttemptsTotal += 1;
    _metrics._lastSuccessAt = ts;
  }

  /// Record a failed sync attempt. Optionally carries the HTTP status seen.
  void recordSyncFailure({int? httpStatus, DateTime? at}) {
    final ts = (at ?? DateTime.now()).toUtc();
    _metrics._syncAttemptsTotal += 1;
    _metrics._syncAttemptsFailed += 1;
    _metrics._lastFailureAt = ts;
  }

  /// Record an eviction (queue overflow or age limit) that dropped [count]
  /// points. Increments the cumulative `pointsDropped` counter.
  void recordDropped(int count) {
    if (count <= 0) return;
    _metrics._pointsDropped += count;
  }

  /// Update the current quarantine size. This is a *gauge*, not a counter,
  /// so the value is replaced wholesale.
  void setQuarantinedNow(int count) {
    if (count < 0) return;
    _metrics._pointsQuarantinedNow = count;
  }

  /// Resets the registry to a pristine state. Intended for tests only.
  /// Closes the existing event stream and creates a fresh one.
  Future<void> resetForTests() async {
    await _metrics.reset();
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
    _eventController = StreamController<LocusReliabilityEvent>.broadcast();
  }
}

/// Mutable in-memory implementation of [LocusMetrics] used by the registry.
///
/// Private to this library: external code reads through [LocusMetrics], and
/// the registry mutates the underlying fields directly.
final class _InMemoryLocusMetrics implements LocusMetrics {
  int _pointsCaptured = 0;
  int _pointsSent = 0;
  int _pointsDropped = 0;
  int _pointsQuarantinedNow = 0;
  int _syncAttemptsTotal = 0;
  int _syncAttemptsFailed = 0;
  DateTime? _lastSuccessAt;
  DateTime? _lastFailureAt;

  @override
  Future<LocusMetricsSnapshot> snapshot() async {
    return LocusMetricsSnapshot(
      pointsCaptured: _pointsCaptured,
      pointsSent: _pointsSent,
      pointsDropped: _pointsDropped,
      pointsQuarantinedNow: _pointsQuarantinedNow,
      syncAttemptsTotal: _syncAttemptsTotal,
      syncAttemptsFailed: _syncAttemptsFailed,
      lastSuccessAt: _lastSuccessAt,
      lastFailureAt: _lastFailureAt,
    );
  }

  @override
  Future<void> reset() async {
    _pointsCaptured = 0;
    _pointsSent = 0;
    _pointsDropped = 0;
    _pointsQuarantinedNow = 0;
    _syncAttemptsTotal = 0;
    _syncAttemptsFailed = 0;
    _lastSuccessAt = null;
    _lastFailureAt = null;
  }
}
