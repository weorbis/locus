import 'dart:async';

import 'package:locus/src/features/sync/models/http_event.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';

/// Bridges the SDK's [HttpEvent] stream into [LocusReliabilityRegistry]
/// counters so that `Locus.metrics` reflects real-world sync activity.
///
/// On every observed event:
///
/// - `event.ok == true` → [LocusReliabilityRegistry.recordSent] with
///   `event.recordsSent` (or `1` when the platform has not filled it).
///   Stamps `lastSuccessAt` and increments `syncAttemptsTotal`.
/// - `event.ok == false` → [LocusReliabilityRegistry.recordSyncFailure]
///   with `event.status` (which is `0` for transport-level errors). Stamps
///   `lastFailureAt` and increments both totals.
///
/// The recorder is independent of `SyncHealthMonitor`: the monitor decides
/// when to *escalate* failures into reliability events, while the recorder
/// keeps the cumulative counters exposed via `LocusMetrics.snapshot` in
/// step with reality. Both can attach to the same [HttpEvent] stream.
///
/// `recordsSent` cardinality is intentionally per-batch, not per-record:
/// when a batch flushes 10 locations the counter advances by 10 in a single
/// call. This keeps writer pressure bounded and matches how the platform
/// side actually deletes rows on success.
class SyncMetricsRecorder {
  SyncMetricsRecorder({LocusReliabilityRegistry? registry})
      : _registry = registry ?? LocusReliabilityRegistry.instance;

  final LocusReliabilityRegistry _registry;

  // ignore: cancel_subscriptions — cancelled via [detach].
  StreamSubscription<HttpEvent>? _subscription;

  /// Subscribes to the given [HttpEvent] stream. Calling [attachTo] again
  /// detaches the previous subscription first; calling [detach] cancels it.
  void attachTo(Stream<HttpEvent> events) {
    unawaited(detach());
    _subscription = events.listen(record);
  }

  /// Records a single [HttpEvent] without going through the stream. Useful
  /// for tests and for sites that already have an event in hand.
  void record(HttpEvent event) {
    if (event.ok) {
      // Platform success without a count is treated as a single-record sync.
      // Zero or negative values are ignored by the registry.
      final count = event.recordsSent ?? 1;
      _registry.recordSent(count);
    } else {
      _registry.recordSyncFailure(httpStatus: event.status);
    }
  }

  /// Cancels the subscription created by [attachTo], if any.
  Future<void> detach() async {
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
  }
}
