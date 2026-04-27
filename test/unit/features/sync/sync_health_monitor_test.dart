import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/sync/models/http_event.dart';
import 'package:locus/src/features/sync/services/sync_health_monitor.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:locus/src/observability/reliability_event.dart';

class _FakeClock {
  DateTime _now = DateTime.utc(2026, 4, 27, 12, 0, 0);

  DateTime call() => _now;

  void advance(Duration d) {
    _now = _now.add(d);
  }
}

void main() {
  late LocusReliabilityRegistry registry;
  late _FakeClock clock;
  late List<LocusReliabilityEvent> events;
  late StreamSubscription<LocusReliabilityEvent> sub;

  setUp(() async {
    registry = LocusReliabilityRegistry.instance;
    await registry.resetForTests();
    clock = _FakeClock();
    events = <LocusReliabilityEvent>[];
    sub = registry.reliability.listen(events.add);
  });

  tearDown(() async {
    await sub.cancel();
  });

  SyncHealthMonitor newMonitor() => SyncHealthMonitor(
        stalledThreshold: const Duration(minutes: 1),
        unrecoverableThreshold: const Duration(minutes: 30),
        registry: registry,
        clock: clock.call,
      );

  group('SyncHealthMonitor', () {
    test('starts healthy with no last-success baseline', () {
      final monitor = newMonitor();
      expect(monitor.state, SyncHealthState.healthy);
      expect(monitor.lastSuccessAt, isNull);
      expect(monitor.consecutiveFailures, 0);
    });

    test('asserts stalledThreshold < unrecoverableThreshold', () {
      expect(
        () => SyncHealthMonitor(
          stalledThreshold: const Duration(minutes: 5),
          unrecoverableThreshold: const Duration(minutes: 1),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('recordSuccess sets the baseline and stays healthy', () {
      final monitor = newMonitor();
      monitor.recordSuccess();
      expect(monitor.state, SyncHealthState.healthy);
      expect(monitor.lastSuccessAt, isNotNull);
      expect(monitor.consecutiveFailures, 0);
    });

    test('failure under stalled threshold does not emit', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(seconds: 30));
      monitor.recordFailure(httpStatus: 500);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(monitor.state, SyncHealthState.healthy);
      expect(monitor.consecutiveFailures, 1);
    });

    test('failure crossing stalled threshold emits SyncStalled exactly once', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(seconds: 65));
      monitor.recordFailure(httpStatus: 503);
      // Another failure later in the same band should not re-emit.
      clock.advance(const Duration(seconds: 30));
      monitor.recordFailure(httpStatus: 503);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      final stalled = events.single as SyncStalled;
      expect(stalled.consecutiveFailures, 1);
      expect(stalled.lastHttpStatus, 503);
      expect(stalled.sinceLastSuccess, const Duration(seconds: 65));
      expect(monitor.state, SyncHealthState.stalled);
    });

    test('crossing unrecoverable threshold emits SyncUnrecoverable', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      // Cross stalled boundary first.
      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure(httpStatus: 401);
      // Cross unrecoverable boundary.
      clock.advance(const Duration(minutes: 30));
      monitor.recordFailure(httpStatus: 401);
      await Future<void>.delayed(Duration.zero);

      expect(events.map((e) => e.runtimeType), [
        SyncStalled,
        SyncUnrecoverable,
      ]);
      final unrec = events.last as SyncUnrecoverable;
      expect(unrec.consecutiveFailures, 2);
      expect(unrec.sinceLastSuccess, const Duration(minutes: 32));
      expect(monitor.state, SyncHealthState.unrecoverable);
    });

    test('recordSuccess after stalled returns to healthy and re-arms emission', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.stalled);

      clock.advance(const Duration(seconds: 5));
      monitor.recordSuccess();
      expect(monitor.state, SyncHealthState.healthy);
      expect(monitor.consecutiveFailures, 0);

      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<SyncStalled>(), hasLength(2));
    });

    test('evaluate() escalates stalled → unrecoverable without a new failure', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.stalled);

      clock.advance(const Duration(minutes: 30));
      monitor.evaluate();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.unrecoverable);
      expect(events.last, isA<SyncUnrecoverable>());
    });

    test('attachTo bridges HttpEvent stream into success/failure paths', () async {
      final controller = StreamController<HttpEvent>();
      final monitor = newMonitor();
      monitor.attachTo(controller.stream);

      controller.add(const HttpEvent(status: 200, ok: true));
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.healthy);

      clock.advance(const Duration(minutes: 2));
      controller.add(const HttpEvent(status: 500, ok: false));
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.stalled);

      await monitor.detach();
      await controller.close();
    });
  });
}
