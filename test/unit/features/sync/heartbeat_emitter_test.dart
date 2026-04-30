import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/sync/models/location_sync_backlog.dart';
import 'package:locus/src/features/sync/services/heartbeat_emitter.dart';
import 'package:locus/src/observability/locus_logger.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:logging/logging.dart';

void main() {
  late LocusReliabilityRegistry registry;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() async {
    registry = LocusReliabilityRegistry.instance;
    await registry.resetForTests();
    records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
  });

  group('HeartbeatEmitter', () {
    test('rejects non-positive interval', () {
      expect(
        () => HeartbeatEmitter(
          backlogReader: () async => const LocationSyncBacklog(),
          interval: Duration.zero,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('tickNow emits a tracking_heartbeat structured log', () async {
      final clock = DateTime.utc(2026, 4, 27, 12, 0, 0);
      registry.recordCaptured(10);
      registry.recordSent(8, at: clock.subtract(const Duration(seconds: 30)));

      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(
          pendingLocationCount: 2,
          quarantinedLocationCount: 1,
          isPaused: false,
        ),
        pauseReasonReader: () => null,
        clock: () => clock,
      );

      await emitter.tickNow();

      final heartbeat = records.singleWhere(
        (r) => r.object is LocusEvent && (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      final attrs = (heartbeat.object! as LocusEvent).attributes;
      expect(attrs['points_captured'], 10);
      expect(attrs['points_sent'], 8);
      expect(attrs['points_dropped'], 0);
      expect(attrs['points_pending'], 2);
      expect(attrs['points_quarantined'], 1);
      expect(attrs['last_success_age_ms'], 30 * 1000);
      expect(attrs['sync_paused'], false);
      expect(attrs['sync_pause_reason'], isNull);
      expect(heartbeat.level, Level.INFO);
    });

    test('tickNow refreshes the registry quarantine gauge from the backlog',
        () async {
      // Seed a stale gauge value so we can prove the tick replaces it.
      registry.setQuarantinedNow(99);

      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(
          quarantinedLocationCount: 4,
        ),
      );
      await emitter.tickNow();

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsQuarantinedNow, 4,
          reason: 'each tick must replace the gauge with the live backlog');
    });

    test('tickNow leaves the quarantine gauge alone when backlog read fails',
        () async {
      registry.setQuarantinedNow(7);
      final emitter = HeartbeatEmitter(
        backlogReader: () async => throw StateError('backlog kaboom'),
      );
      await emitter.tickNow();

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsQuarantinedNow, 7,
          reason: 'a failed backlog read must not zero the gauge');
    });

    test('emits last_success_age_ms = null when no success has been recorded', () async {
      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(),
      );
      await emitter.tickNow();
      final heartbeat = records.singleWhere(
        (r) => r.object is LocusEvent && (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      final attrs = (heartbeat.object! as LocusEvent).attributes;
      expect(attrs['last_success_age_ms'], isNull);
    });

    test('logs a warning and continues when backlog read fails', () async {
      final emitter = HeartbeatEmitter(
        backlogReader: () async => throw StateError('backlog kaboom'),
      );
      await emitter.tickNow();

      final warnings = records.whereType<LogRecord>().where(
            (r) => r.object is LocusEvent &&
                (r.object! as LocusEvent).name == 'heartbeat_backlog_unavailable',
          );
      expect(warnings, hasLength(1));

      // The heartbeat itself still fires with default values.
      final heartbeat = records.singleWhere(
        (r) => r.object is LocusEvent && (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      final attrs = (heartbeat.object! as LocusEvent).attributes;
      expect(attrs['points_pending'], 0);
      expect(attrs['sync_paused'], false);
    });

    test('forwards pause reason when provided', () async {
      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(isPaused: true),
        pauseReasonReader: () => 'http_401',
      );
      await emitter.tickNow();
      final heartbeat = records.singleWhere(
        (r) => r.object is LocusEvent && (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      final attrs = (heartbeat.object! as LocusEvent).attributes;
      expect(attrs['sync_paused'], true);
      expect(attrs['sync_pause_reason'], 'http_401');
    });

    test('start fires an immediate heartbeat and is idempotent', () async {
      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(),
        interval: const Duration(minutes: 5), // long enough that the periodic
        // timer cannot fire within the test.
      );
      emitter.start();
      emitter.start(); // idempotent
      await Future<void>.delayed(Duration.zero);
      expect(emitter.isRunning, isTrue);

      final heartbeats = records.where(
        (r) => r.object is LocusEvent && (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      expect(heartbeats, hasLength(1));

      await emitter.stop();
      expect(emitter.isRunning, isFalse);
    });

    test('M-1: startIfNotRunning is idempotent and a no-op when running',
        () async {
      // The lifecycle path (LocusLifecycle.ready) calls `startIfNotRunning`
      // on every `ready()` so repeat invocations (hot reload, test setup,
      // re-attach after a transient detach) must not stack timers.
      final emitter = HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(),
        interval: const Duration(minutes: 5),
      );
      emitter.startIfNotRunning();
      emitter.startIfNotRunning();
      emitter.startIfNotRunning();
      await Future<void>.delayed(Duration.zero);

      expect(emitter.isRunning, isTrue);
      final heartbeats = records.where(
        (r) =>
            r.object is LocusEvent &&
            (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      // Only one immediate tick despite three start calls.
      expect(heartbeats, hasLength(1));

      await emitter.stop();
      expect(emitter.isRunning, isFalse);
    });

    test('M-1: never-started emitter does not emit until start is called',
        () async {
      // Apps that import the package without calling `Locus.ready` (test
      // suites, lazy-loaded bundles) must not start a background timer.
      // Pre-fix the constructor of `MethodChannelLocus` started the timer
      // unconditionally; this test guards the new behavior at the unit
      // level — constructing the emitter without calling `start` is
      // observably silent.
      HeartbeatEmitter(
        backlogReader: () async => const LocationSyncBacklog(),
        interval: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final heartbeats = records.where(
        (r) =>
            r.object is LocusEvent &&
            (r.object! as LocusEvent).name == 'tracking_heartbeat',
      );
      expect(heartbeats, isEmpty);
    });
  });
}
