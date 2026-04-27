import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/observability/locus_metrics.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:locus/src/observability/reliability_event.dart';

void main() {
  group('LocusMetricsSnapshot', () {
    test('toJson maps every field to a snake_case key', () {
      final ts = DateTime.utc(2026, 4, 27, 10, 0, 0);
      const snapshot = LocusMetricsSnapshot(
        pointsCaptured: 100,
        pointsSent: 80,
        pointsDropped: 5,
        pointsQuarantinedNow: 3,
        syncAttemptsTotal: 12,
        syncAttemptsFailed: 2,
      );
      expect(snapshot.toJson(), {
        'points_captured': 100,
        'points_sent': 80,
        'points_dropped': 5,
        'points_quarantined_now': 3,
        'sync_attempts_total': 12,
        'sync_attempts_failed': 2,
        'last_success_at': null,
        'last_failure_at': null,
      });
      // Use ts to avoid lint about unused local.
      expect(ts.isUtc, isTrue);
    });
  });

  group('LocusReliabilityRegistry', () {
    setUp(() async {
      await LocusReliabilityRegistry.instance.resetForTests();
    });

    test('initial snapshot has zeroed counters', () async {
      final snap = await LocusReliabilityRegistry.instance.metrics.snapshot();
      expect(snap.pointsCaptured, 0);
      expect(snap.pointsSent, 0);
      expect(snap.pointsDropped, 0);
      expect(snap.pointsQuarantinedNow, 0);
      expect(snap.syncAttemptsTotal, 0);
      expect(snap.syncAttemptsFailed, 0);
      expect(snap.lastSuccessAt, isNull);
      expect(snap.lastFailureAt, isNull);
    });

    test('recordCaptured / recordSent advance counters', () async {
      final reg = LocusReliabilityRegistry.instance;
      final at = DateTime.utc(2026, 4, 27, 10, 0, 0);
      reg.recordCaptured(3);
      reg.recordCaptured(2);
      reg.recordSent(5, at: at);

      final snap = await reg.metrics.snapshot();
      expect(snap.pointsCaptured, 5);
      expect(snap.pointsSent, 5);
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.syncAttemptsFailed, 0);
      expect(snap.lastSuccessAt, at);
      expect(snap.lastFailureAt, isNull);
    });

    test('recordSyncFailure advances total + failed and stamps lastFailureAt', () async {
      final reg = LocusReliabilityRegistry.instance;
      final at = DateTime.utc(2026, 4, 27, 11, 0, 0);
      reg.recordSyncFailure(httpStatus: 500, at: at);
      final snap = await reg.metrics.snapshot();
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.syncAttemptsFailed, 1);
      expect(snap.lastSuccessAt, isNull);
      expect(snap.lastFailureAt, at);
    });

    test('recordDropped accumulates pointsDropped', () async {
      final reg = LocusReliabilityRegistry.instance;
      reg.recordDropped(7);
      reg.recordDropped(0); // no-op
      reg.recordDropped(-3); // ignored
      reg.recordDropped(2);
      final snap = await reg.metrics.snapshot();
      expect(snap.pointsDropped, 9);
    });

    test('setQuarantinedNow replaces gauge value', () async {
      final reg = LocusReliabilityRegistry.instance;
      reg.setQuarantinedNow(4);
      reg.setQuarantinedNow(0);
      reg.setQuarantinedNow(7);
      final snap = await reg.metrics.snapshot();
      expect(snap.pointsQuarantinedNow, 7);
    });

    test('reliability stream forwards every emitted event', () async {
      final reg = LocusReliabilityRegistry.instance;
      final events = <LocusReliabilityEvent>[];
      final sub = reg.reliability.listen(events.add);
      reg.emit(PointsEvicted(count: 5, reason: EvictionReason.countLimit));
      reg.emit(SyncStalled(
        sinceLastSuccess: const Duration(minutes: 2),
        consecutiveFailures: 3,
        lastHttpStatus: 503,
      ));
      // Allow microtask drain for broadcast stream.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, hasLength(2));
      expect(events[0], isA<PointsEvicted>());
      expect((events[0] as PointsEvicted).count, 5);
      expect(events[1], isA<SyncStalled>());
      expect((events[1] as SyncStalled).consecutiveFailures, 3);
    });

    test('LocusMetrics.reset clears every counter', () async {
      final reg = LocusReliabilityRegistry.instance;
      reg.recordCaptured(5);
      reg.recordSent(3);
      reg.recordSyncFailure();
      reg.recordDropped(1);
      reg.setQuarantinedNow(2);

      await reg.metrics.reset();

      final snap = await reg.metrics.snapshot();
      expect(snap.pointsCaptured, 0);
      expect(snap.pointsSent, 0);
      expect(snap.pointsDropped, 0);
      expect(snap.pointsQuarantinedNow, 0);
      expect(snap.syncAttemptsTotal, 0);
      expect(snap.syncAttemptsFailed, 0);
      expect(snap.lastSuccessAt, isNull);
      expect(snap.lastFailureAt, isNull);
    });
  });

  group('Reliability event subtypes', () {
    test('PointsEvicted asserts a positive count', () {
      expect(
        () => PointsEvicted(count: 0, reason: EvictionReason.ageLimit),
        throwsA(isA<AssertionError>()),
      );
    });

    test('QuarantinePurged asserts a positive count', () {
      expect(
        () => QuarantinePurged(
          count: 0,
          olderThan: const Duration(days: 7),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('occurredAt defaults to now in UTC', () {
      final before = DateTime.now().toUtc();
      final event = QuarantineGrew(totalQuarantined: 5);
      final after = DateTime.now().toUtc();
      expect(event.occurredAt.isUtc, isTrue);
      expect(event.occurredAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(event.occurredAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });
}
