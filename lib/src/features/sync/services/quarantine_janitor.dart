import 'dart:async';

import 'package:locus/src/observability/locus_logger.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:locus/src/observability/reliability_event.dart';

/// Function that asks the SDK's native side to discard quarantined records
/// older than [olderThan]. Returns the number of rows actually deleted so
/// the janitor can decide whether to emit a [QuarantinePurged] event.
typedef QuarantinePurger = Future<int> Function(Duration olderThan);

/// Default no-op purger. Used until the SDK's native quarantine-discard
/// API is wired in by the embedder. Returning zero keeps the janitor
/// inert: the timer ticks, but no events fire and no native calls go out.
Future<int> _noopPurger(Duration olderThan) async => 0;

/// Periodically discards quarantined records whose age exceeds [ttl] and
/// emits a single [QuarantinePurged] reliability event per non-empty sweep.
///
/// The janitor delegates the actual deletion to a [QuarantinePurger]
/// callback so the SDK's native API surface (`discardQuarantinedLocations`
/// and similar) can be wired in without coupling this class to a method
/// channel. Tests inject a fake purger.
///
/// Wire-up is the embedder's responsibility — call [start] alongside
/// tracking activation. Idempotent.
class QuarantineJanitor {
  QuarantineJanitor({
    QuarantinePurger? purger,
    this.ttl = const Duration(days: 7),
    Duration sweepInterval = const Duration(hours: 1),
    LocusReliabilityRegistry? registry,
  })  : assert(ttl > Duration.zero, 'ttl must be positive'),
        assert(sweepInterval > Duration.zero, 'sweepInterval must be positive'),
        _purger = purger ?? _noopPurger,
        _sweepInterval = sweepInterval,
        _registry = registry ?? LocusReliabilityRegistry.instance;

  /// Records older than [ttl] are eligible for discard.
  final Duration ttl;

  final QuarantinePurger _purger;
  final Duration _sweepInterval;
  final LocusReliabilityRegistry _registry;
  final _log = locusLogger('quarantine_janitor');

  Timer? _timer;

  /// Whether the janitor is currently scheduling sweeps.
  bool get isRunning => _timer != null;

  /// Starts periodic sweeps. Idempotent: a second start without a [stop]
  /// in between is a no-op. Triggers an immediate sweep so a long-stale
  /// quarantine starts draining without waiting for [_sweepInterval].
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_sweepInterval, (_) => unawaited(sweepNow()));
    unawaited(sweepNow());
  }

  /// Cancels the timer. Safe to call multiple times.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs a single sweep and returns the number of records discarded.
  ///
  /// Errors thrown by the [QuarantinePurger] are logged as a structured
  /// warning and converted to `0` so a transient failure does not stop
  /// the periodic schedule.
  Future<int> sweepNow() async {
    int discarded;
    try {
      discarded = await _purger(ttl);
    } on Object catch (e, stack) {
      _log.eventWarning('quarantine_purge_failed',
          <String, Object?>{'ttl_ms': ttl.inMilliseconds}, e, stack);
      return 0;
    }
    if (discarded > 0) {
      _log.eventInfo('quarantine_purged', <String, Object?>{
        'count': discarded,
        'ttl_ms': ttl.inMilliseconds,
      });
      _registry.emit(QuarantinePurged(count: discarded, olderThan: ttl));
    }
    return discarded;
  }
}
