import 'dart:async';

import 'package:locus/src/features/sync/models/location_sync_backlog.dart';
import 'package:locus/src/observability/locus_logger.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';

/// Reads the current sync backlog. Production callers pass
/// `Locus.dataSync.getBacklog`; tests inject a stub.
typedef BacklogReader = Future<LocationSyncBacklog> Function();

/// Reads the current sync pause reason (`null` when not paused). Production
/// callers pass `() => Locus.dataSync.pauseReason`; tests inject a stub.
typedef PauseReasonReader = String? Function();

/// Periodically emits a `tracking_heartbeat` structured log carrying the
/// SDK's reliability snapshot — captured/sent/dropped/quarantined counters,
/// pending backlog, last-success age, and pause state — so dashboards can
/// detect a silent stop ("no heartbeat in last 5 min" alarm).
///
/// The emitter is independent of the SDK's sync health monitor; on every
/// tick it also pokes the monitor's `evaluate` so the unrecoverable
/// threshold can fire during long silent pauses (no new sync attempts
/// arriving). Wire-up is the embedder's responsibility — typically
/// [start]ed when tracking is activated and [stop]ped when tracking ends.
class HeartbeatEmitter {
  HeartbeatEmitter({
    required BacklogReader backlogReader,
    PauseReasonReader? pauseReasonReader,
    Duration interval = const Duration(seconds: 60),
    LocusReliabilityRegistry? registry,
    DateTime Function()? clock,
  })  : assert(interval > Duration.zero, 'heartbeat interval must be positive'),
        _backlogReader = backlogReader,
        _pauseReasonReader = pauseReasonReader,
        _interval = interval,
        _registry = registry ?? LocusReliabilityRegistry.instance,
        _clock = clock ?? DateTime.now;

  final BacklogReader _backlogReader;
  final PauseReasonReader? _pauseReasonReader;
  final Duration _interval;
  final LocusReliabilityRegistry _registry;
  final DateTime Function() _clock;
  final _log = locusLogger('heartbeat');

  Timer? _timer;

  /// Whether the emitter is currently ticking.
  bool get isRunning => _timer != null;

  /// Starts the heartbeat. Idempotent: calling twice without [stop] in
  /// between is a no-op. Emits one tick immediately so dashboards do not
  /// have to wait `interval` for the first record.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  /// Cancels the heartbeat. Safe to call multiple times.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Emits a single heartbeat. Public for tests; production callers should
  /// rely on [start].
  Future<void> tickNow() => _tick();

  Future<void> _tick() async {
    LocationSyncBacklog? backlog;
    try {
      backlog = await _backlogReader();
    } on Object catch (e, stack) {
      _log.eventWarning('heartbeat_backlog_unavailable', const {}, e, stack);
    }
    final snapshot = await _registry.metrics.snapshot();

    final lastSuccess = snapshot.lastSuccessAt ?? backlog?.lastSuccessAt;
    final ageMs = lastSuccess == null
        ? null
        : _clock().toUtc().difference(lastSuccess.toUtc()).inMilliseconds;

    final pauseReason = _pauseReasonReader?.call();

    // Refresh the quarantine gauge from the live backlog so
    // Locus.metrics.pointsQuarantinedNow stays in step with reality. The
    // gauge is read-after-write per design — replace, don't accumulate.
    if (backlog != null) {
      _registry.setQuarantinedNow(backlog.quarantinedLocationCount);
    }

    _log.eventInfo('tracking_heartbeat', <String, Object?>{
      'points_captured': snapshot.pointsCaptured,
      'points_sent': snapshot.pointsSent,
      'points_dropped': snapshot.pointsDropped,
      'points_pending': backlog?.pendingLocationCount ?? 0,
      'points_quarantined': backlog?.quarantinedLocationCount ?? 0,
      'last_success_age_ms': ageMs,
      'sync_paused': backlog?.isPaused ?? false,
      'sync_pause_reason': pauseReason,
      'sync_attempts_total': snapshot.syncAttemptsTotal,
      'sync_attempts_failed': snapshot.syncAttemptsFailed,
    });

    // Re-evaluate the health monitor so escalation can fire even if no new
    // sync attempts arrived since the last heartbeat (e.g. backend pause).
    _registry.syncHealthMonitor?.evaluate();
  }
}
