import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/sync/models/http_event.dart';
import 'package:locus/src/features/sync/services/sync_metrics_recorder.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';

void main() {
  late LocusReliabilityRegistry registry;
  late SyncMetricsRecorder recorder;

  setUp(() async {
    registry = LocusReliabilityRegistry.instance;
    await registry.resetForTests();
    recorder = SyncMetricsRecorder(registry: registry);
  });

  tearDown(() async {
    await recorder.detach();
  });

  group('SyncMetricsRecorder.record', () {
    test('success with recordsSent advances pointsSent and stamps lastSuccess',
        () async {
      recorder.record(const HttpEvent(status: 200, ok: true, recordsSent: 7));
      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 7);
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.syncAttemptsFailed, 0);
      expect(snap.lastSuccessAt, isNotNull);
      expect(snap.lastFailureAt, isNull);
    });

    test('success without recordsSent defaults to zero and warns', () async {
      // L-5 / Wave 3 §5.6: a success without an explicit count is now
      // treated as zero records (was 1) so a queue-path that never fills
      // `recordsSent` cannot silently inflate `pointsSent`. The recorder
      // emits a `http_event_missing_records_sent` warning so the missing
      // call site is observable.
      recorder.record(const HttpEvent(status: 200, ok: true));
      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 0);
      expect(snap.syncAttemptsTotal, 1);
    });

    test('failure with non-2xx status advances failed counter', () async {
      recorder.record(const HttpEvent(status: 500, ok: false));
      final snap = await registry.metrics.snapshot();
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.syncAttemptsFailed, 1);
      expect(snap.pointsSent, 0);
      expect(snap.lastFailureAt, isNotNull);
      expect(snap.lastSuccessAt, isNull);
    });

    test('failure with transport error (status 0) is still counted', () async {
      // Network error: native side emits status 0 with ok=false.
      recorder.record(const HttpEvent(status: 0, ok: false));
      final snap = await registry.metrics.snapshot();
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.syncAttemptsFailed, 1);
    });

    test('mixed sequence accumulates correctly', () async {
      recorder.record(const HttpEvent(status: 200, ok: true, recordsSent: 3));
      recorder.record(const HttpEvent(status: 500, ok: false));
      recorder.record(const HttpEvent(status: 200, ok: true, recordsSent: 5));
      recorder.record(const HttpEvent(status: 401, ok: false));

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 8);
      expect(snap.syncAttemptsTotal, 4);
      expect(snap.syncAttemptsFailed, 2);
      expect(snap.lastSuccessAt, isNotNull);
      expect(snap.lastFailureAt, isNotNull);
    });

    test('zero recordsSent on success is a no-op for pointsSent but counts attempt',
        () async {
      // Success that flushed nothing (defensive): registry's recordSent treats
      // count >= 0 as a valid attempt and increments syncAttemptsTotal.
      recorder.record(const HttpEvent(status: 200, ok: true, recordsSent: 0));
      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 0);
      expect(snap.syncAttemptsTotal, 1);
      expect(snap.lastSuccessAt, isNotNull);
    });
  });

  group('SyncMetricsRecorder.attachTo', () {
    test('forwards stream events into the registry', () async {
      final controller = StreamController<HttpEvent>();
      recorder.attachTo(controller.stream);

      controller
        ..add(const HttpEvent(status: 200, ok: true, recordsSent: 4))
        ..add(const HttpEvent(status: 503, ok: false));
      await Future<void>.delayed(Duration.zero);

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 4);
      expect(snap.syncAttemptsTotal, 2);
      expect(snap.syncAttemptsFailed, 1);
      await controller.close();
    });

    test('a second attachTo detaches the previous subscription', () async {
      final first = StreamController<HttpEvent>();
      final second = StreamController<HttpEvent>();
      recorder.attachTo(first.stream);
      recorder.attachTo(second.stream);

      // The first stream is now orphaned — events on it must not advance
      // counters because the recorder cancelled that subscription.
      first.add(const HttpEvent(status: 200, ok: true, recordsSent: 9));
      second.add(const HttpEvent(status: 200, ok: true, recordsSent: 1));
      await Future<void>.delayed(Duration.zero);

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 1);
      expect(snap.syncAttemptsTotal, 1);

      await first.close();
      await second.close();
    });

    test('detach cancels the subscription so further events are ignored',
        () async {
      final controller = StreamController<HttpEvent>();
      recorder.attachTo(controller.stream);

      controller.add(const HttpEvent(status: 200, ok: true, recordsSent: 2));
      await Future<void>.delayed(Duration.zero);
      await recorder.detach();
      controller.add(const HttpEvent(status: 200, ok: true, recordsSent: 99));
      await Future<void>.delayed(Duration.zero);

      final snap = await registry.metrics.snapshot();
      expect(snap.pointsSent, 2,
          reason: 'events emitted after detach must not advance counters');
      await controller.close();
    });
  });

  group('HttpEvent serialization', () {
    test('recordsSent round-trips through toMap/fromMap', () {
      const event = HttpEvent(status: 200, ok: true, recordsSent: 12);
      final restored = HttpEvent.fromMap(event.toMap());
      expect(restored.recordsSent, 12);
      expect(restored.ok, true);
      expect(restored.status, 200);
    });

    test('absent recordsSent decodes as null', () {
      final restored = HttpEvent.fromMap(<String, dynamic>{
        'status': 500,
        'ok': false,
      });
      expect(restored.recordsSent, isNull);
    });

    test('toMap omits recordsSent when null', () {
      const event = HttpEvent(status: 500, ok: false);
      expect(event.toMap().containsKey('recordsSent'), isFalse);
    });
  });
}
