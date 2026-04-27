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
  });
}
