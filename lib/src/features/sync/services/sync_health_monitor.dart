import 'dart:async';

import 'package:locus/src/features/sync/models/http_event.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:locus/src/observability/reliability_event.dart';

/// Coarse-grained health states the monitor cycles through.
enum SyncHealthState {
  /// Sync is keeping up: either succeeding, or failing for less than
  /// [SyncHealthMonitor.stalledThreshold].
  healthy,

  /// Sync has been failing for at least [SyncHealthMonitor.stalledThreshold]
  /// but less than [SyncHealthMonitor.unrecoverableThreshold].
  stalled,

  /// Sync has been failing for at least
  /// [SyncHealthMonitor.unrecoverableThreshold]; operator intervention is
  /// expected.
  unrecoverable,
}

/// State machine that watches a sequence of sync attempts and emits
/// [SyncStalled] / [SyncUnrecoverable] reliability events when the gap since
/// the last successful sync crosses the configured thresholds.
///
/// The monitor is event-driven and idempotent: re-emitting `recordFailure`
/// repeatedly while still inside the same band does not produce duplicate
/// events. [recordSuccess] resets the state to [SyncHealthState.healthy].
///
/// Embedders typically:
///
/// 1. Construct one monitor at SDK init (or attach via [attachTo]).
/// 2. Call [recordSuccess] / [recordFailure] from the sync HTTP callback.
/// 3. Periodically call [evaluate] (e.g. from a 60 s heartbeat) so that the
///    `unrecoverable` threshold can fire even when sync is paused and no
///    new failures arrive.
class SyncHealthMonitor {
  SyncHealthMonitor({
    required this.stalledThreshold,
    required this.unrecoverableThreshold,
    LocusReliabilityRegistry? registry,
    DateTime Function()? clock,
  })  : assert(
          stalledThreshold < unrecoverableThreshold,
          'stalledThreshold must be smaller than unrecoverableThreshold',
        ),
        _registry = registry ?? LocusReliabilityRegistry.instance,
        _clock = clock ?? DateTime.now {
    // Anchor the fallback baseline at construction. A new install with a
    // bad token has no `_lastSuccessAt` and would otherwise be unable to
    // escalate `SyncUnrecoverable` even after 30 minutes of failed
    // attempts — `evaluate()` would early-return on the null baseline.
    _startedAt = (_clock()).toUtc();
  }

  /// Time-since-last-success threshold at which a [SyncStalled] event is
  /// emitted.
  final Duration stalledThreshold;

  /// Time-since-last-success threshold at which a [SyncUnrecoverable] event
  /// is emitted.
  final Duration unrecoverableThreshold;

  final LocusReliabilityRegistry _registry;
  final DateTime Function() _clock;

  /// Wall-clock at which this monitor was constructed. Used as the final
  /// fallback baseline for `evaluate` when the process has never observed
  /// a success or failure (so a wedged-from-cold-start sync still
  /// escalates after `unrecoverableThreshold`).
  late final DateTime _startedAt;

  DateTime? _lastSuccessAt;

  /// Wall-clock of the first failure observed since process start (or since
  /// the last `recordSuccess` if one happened). Acts as the second-tier
  /// baseline for `evaluate`: when there is no success yet but at least
  /// one failure has been seen, escalate from that failure rather than
  /// from process start (so a process that idled cleanly for an hour and
  /// then started failing waits one stalled-window from the failure, not
  /// instantly).
  DateTime? _firstFailureAt;
  int _consecutiveFailures = 0;
  int? _lastHttpStatus;
  SyncHealthState _state = SyncHealthState.healthy;
  // ignore: cancel_subscriptions — cancelled via [detach].
  StreamSubscription<HttpEvent>? _httpSubscription;

  /// Current health state. Mostly useful for tests and diagnostics screens.
  SyncHealthState get state => _state;

  /// Number of consecutive failures since the last successful sync.
  int get consecutiveFailures => _consecutiveFailures;

  /// Wall-clock UTC of the last successful sync, or `null` if there has not
  /// been one yet.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Records a successful sync and clears the failure streak.
  void recordSuccess({DateTime? at}) {
    _lastSuccessAt = (at ?? _clock()).toUtc();
    _consecutiveFailures = 0;
    _lastHttpStatus = null;
    // A fresh success resets the failure-baseline so the next failure
    // streak starts its own clock from the moment it begins, not from
    // some prior failure that has since been resolved.
    _firstFailureAt = null;
    _state = SyncHealthState.healthy;
  }

  /// Records a failed sync attempt. Triggers state evaluation.
  void recordFailure({int? httpStatus, DateTime? at}) {
    final now = (at ?? _clock()).toUtc();
    _firstFailureAt ??= now;
    _consecutiveFailures += 1;
    _lastHttpStatus = httpStatus;
    evaluate(at: at);
  }

  /// Re-evaluates the current state without recording a new attempt. Use
  /// from a periodic heartbeat to escalate `stalled → unrecoverable` even
  /// when no new sync attempts are happening.
  ///
  /// Reference-time fallback chain: `_lastSuccessAt → _firstFailureAt →
  /// _startedAt`. The last fallback ensures a process that has never
  /// successfully synced (e.g. fresh install with a bad token) can still
  /// reach `SyncUnrecoverable` once enough wall time has passed since
  /// process start.
  void evaluate({DateTime? at}) {
    final now = (at ?? _clock()).toUtc();
    final referenceTime = _lastSuccessAt ?? _firstFailureAt ?? _startedAt;
    final since = now.difference(referenceTime);

    if (since >= unrecoverableThreshold &&
        _state != SyncHealthState.unrecoverable) {
      _state = SyncHealthState.unrecoverable;
      _registry.emit(SyncUnrecoverable(
        sinceLastSuccess: since,
        consecutiveFailures: _consecutiveFailures,
        lastHttpStatus: _lastHttpStatus,
        occurredAt: now,
      ));
      return;
    }

    if (since >= stalledThreshold && _state == SyncHealthState.healthy) {
      _state = SyncHealthState.stalled;
      _registry.emit(SyncStalled(
        sinceLastSuccess: since,
        consecutiveFailures: _consecutiveFailures,
        lastHttpStatus: _lastHttpStatus,
        occurredAt: now,
      ));
    }
  }

  /// Subscribes the monitor to a stream of [HttpEvent]s.
  ///
  /// `event.ok == true` is treated as success, anything else as failure with
  /// `event.status` carried into the next reliability event.
  ///
  /// Call [detach] to unsubscribe; constructing a new monitor or calling
  /// [attachTo] again first detaches the existing subscription.
  void attachTo(Stream<HttpEvent> events) {
    unawaited(detach());
    _httpSubscription = events.listen((HttpEvent event) {
      if (event.ok) {
        recordSuccess();
      } else {
        recordFailure(httpStatus: event.status);
      }
    });
  }

  /// Cancels the subscription created by [attachTo], if any.
  Future<void> detach() async {
    final sub = _httpSubscription;
    _httpSubscription = null;
    await sub?.cancel();
  }
}
