import 'dart:async';

import 'package:locus/src/features/sync/services/sync_health_monitor.dart';
import 'package:locus/src/features/sync/services/sync_metrics_recorder.dart';
import 'package:locus/src/observability/locus_metrics.dart';
import 'package:locus/src/observability/reliability_event.dart';

/// Singleton that holds the SDK's reliability event stream and counters.
///
/// The public surface (`Locus.reliability`, `Locus.metrics`) is a thin
/// re-export of this registry. Internal SDK code (sync, storage, quarantine
/// janitor, ...) calls the `record*` / `emit` methods to feed it.
///
/// ## Per-isolate scope
///
/// [instance] is a `static final` inside this Dart library, which means
/// **one registry per Dart isolate**, not one per process. Headless
/// callbacks (geofence triggers, sync-on-boot) execute in a secondary
/// isolate spawned by the Flutter engine. Events that fire there land in
/// *that* isolate's registry, not the foreground app's.
///
/// Practical consequences for embedders:
///
/// * Subscribing to `Locus.reliability` from a Riverpod provider only sees
///   events emitted from the foreground isolate.
/// * `Locus.metrics.snapshot()` read from the foreground only reflects
///   foreground-side counters — captures and syncs that happen during
///   headless execution don't show up there.
/// * Background-isolate observability is best read via the structured logs
///   the SDK emits (e.g. `tracking_heartbeat`), which the platform side
///   forwards into the unified log stream.
///
/// Plumbing headless events into the foreground registry would require a
/// platform-channel bridge with explicit ordering guarantees and is
/// tracked as a follow-up.
class LocusReliabilityRegistry {
  LocusReliabilityRegistry._();

  /// Per-isolate singleton — see the class-level dartdoc on isolate scope.
  static final LocusReliabilityRegistry instance = LocusReliabilityRegistry._();

  final _InMemoryLocusMetrics _metrics = _InMemoryLocusMetrics();
  StreamController<LocusReliabilityEvent> _eventController =
      StreamController<LocusReliabilityEvent>.broadcast();
  SyncHealthMonitor? _syncHealthMonitor;
  SyncMetricsRecorder? _syncMetricsRecorder;

  /// Public stream of reliability events.
  Stream<LocusReliabilityEvent> get reliability => _eventController.stream;

  /// Public read-only metrics view.
  LocusMetrics get metrics => _metrics;

  /// Currently installed sync health monitor, if any. Internal callers may
  /// use it to call [SyncHealthMonitor.evaluate] from a heartbeat tick.
  SyncHealthMonitor? get syncHealthMonitor => _syncHealthMonitor;

  /// Installs a [SyncHealthMonitor]. Detaches and replaces any previously
  /// installed monitor.
  Future<void> installSyncHealthMonitor(SyncHealthMonitor monitor) async {
    final previous = _syncHealthMonitor;
    _syncHealthMonitor = monitor;
    await previous?.detach();
  }

  /// Installs a [SyncMetricsRecorder]. Detaches and replaces any previously
  /// installed recorder. Held by the registry so the subscription stays
  /// alive without callers needing to hold the reference themselves.
  Future<void> installSyncMetricsRecorder(SyncMetricsRecorder recorder) async {
    final previous = _syncMetricsRecorder;
    _syncMetricsRecorder = recorder;
    await previous?.detach();
  }

  /// Emit a reliability event to subscribers. Safe to call at any time:
  /// after [resetForTests] closes the controller, the next call will see a
  /// fresh broadcast stream.
  void emit(LocusReliabilityEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  /// Increment the captured-points counter.
  ///
  /// Called once per location event surfaced to embedders (after spoof and
  /// privacy-zone filtering). Granularity is per-event, not per-batch — the
  /// platform delivers locations one at a time.
  void recordCaptured(int count) {
    if (count <= 0) return;
    _metrics._pointsCaptured += count;
  }

  /// Record a successful sync that flushed [count] points.
  ///
  /// Cardinality is intentionally per-batch, not per-record: when a single
  /// HTTP request flushes 10 stored locations, [count] is 10 and
  /// [LocusMetricsSnapshot.syncAttemptsTotal] advances by 1. This matches
  /// the platform side, which deletes rows by `idsToDelete.size` on a 2xx.
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
    final monitor = _syncHealthMonitor;
    _syncHealthMonitor = null;
    await monitor?.detach();
    final recorder = _syncMetricsRecorder;
    _syncMetricsRecorder = null;
    await recorder?.detach();
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
