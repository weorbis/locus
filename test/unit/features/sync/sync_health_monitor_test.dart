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

    test('failure crossing stalled threshold emits SyncStalled exactly once',
        () async {
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

    test('recordSuccess after stalled returns to healthy and re-arms emission',
        () async {
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

    test('evaluate() escalates stalled → unrecoverable without a new failure',
        () async {
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

    test('never-succeeded process escalates from first failure baseline',
        () async {
      // A fresh install with a bad token never produces a `recordSuccess`.
      // Pre-fix `evaluate` early-returned on a null `_lastSuccessAt` so the
      // unrecoverable threshold could not fire; post-fix it falls back to
      // `_firstFailureAt` (and ultimately `_startedAt`).
      final monitor = newMonitor();
      monitor.recordFailure(httpStatus: 401);
      // Same instant as the first failure: zero elapsed, no escalation.
      expect(monitor.state, SyncHealthState.healthy);

      // Cross stalled threshold (1 min) — first failure was 1 min ago.
      clock.advance(const Duration(minutes: 1, seconds: 1));
      monitor.evaluate();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.stalled);
      expect(events.whereType<SyncStalled>(), hasLength(1));

      // Cross unrecoverable threshold (30 min) — total 30 min, 1 sec from
      // the first failure.
      clock.advance(const Duration(minutes: 29));
      monitor.evaluate();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.unrecoverable);
      expect(events.whereType<SyncUnrecoverable>(), hasLength(1));
    });

    test('never-failed never-succeeded process escalates from process start',
        () async {
      // Even with zero failures observed, a process that has been alive
      // for >= unrecoverableThreshold and has never recorded a success can
      // be evaluated to unrecoverable. This protects against a wedged
      // sync that never even attempts (e.g. permanently-disabled network)
      // — the heartbeat keeps calling `evaluate` and eventually trips.
      final monitor = newMonitor();
      clock.advance(const Duration(minutes: 30, seconds: 1));
      monitor.evaluate();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.state, SyncHealthState.unrecoverable);
      expect(events.whereType<SyncUnrecoverable>(), hasLength(1));
    });

    test('recordSuccess clears the firstFailure baseline', () async {
      // After a recovery, the next failure streak must start its own clock
      // from scratch (otherwise a process that briefly failed an hour ago,
      // recovered, and is now failing for 30 seconds would trip stalled
      // immediately).
      final monitor = newMonitor();
      monitor.recordFailure(httpStatus: 503);
      clock.advance(const Duration(minutes: 5));
      monitor.recordSuccess();
      // No further failures; advance well past stalled threshold.
      clock.advance(const Duration(minutes: 5));
      monitor.recordFailure(httpStatus: 503);
      await Future<void>.delayed(Duration.zero);
      // Single failure 5 min after recovery → since(_lastSuccess) = 5 min.
      // Crosses stalled (1 min) but not unrecoverable (30 min).
      expect(monitor.state, SyncHealthState.stalled);
      expect(events.whereType<SyncStalled>(), hasLength(1));
      expect(events.whereType<SyncUnrecoverable>(), isEmpty);
    });

    test('attachTo bridges HttpEvent stream into success/failure paths',
        () async {
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

    test('emitted SyncStalled carries auto-classified lastErrorClass',
        () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure(httpStatus: 401);
      await Future<void>.delayed(Duration.zero);
      final stalled = events.whereType<SyncStalled>().single;
      expect(stalled.lastHttpStatus, 401);
      expect(stalled.lastErrorClass, SyncErrorClass.auth);
    });

    test('emitted SyncUnrecoverable carries auto-classified lastErrorClass',
        () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(minutes: 31));
      monitor.recordFailure(httpStatus: 503);
      await Future<void>.delayed(Duration.zero);
      final unrec = events.whereType<SyncUnrecoverable>().single;
      expect(unrec.lastHttpStatus, 503);
      expect(unrec.lastErrorClass, SyncErrorClass.server);
    });

    test('transport-level error (status 0) classifies as network', () async {
      final monitor = newMonitor();
      monitor.recordSuccess();
      clock.advance(const Duration(minutes: 2));
      monitor.recordFailure(httpStatus: 0);
      await Future<void>.delayed(Duration.zero);
      final stalled = events.whereType<SyncStalled>().single;
      expect(stalled.lastErrorClass, SyncErrorClass.network);
    });
  });

  group('classifySyncError', () {
    test('null → network (transport-level: no response received)', () {
      expect(classifySyncError(null), SyncErrorClass.network);
    });

    test('0 → network (matches the platform-side transport error sentinel)',
        () {
      expect(classifySyncError(0), SyncErrorClass.network);
    });

    test('401 / 403 → auth', () {
      expect(classifySyncError(401), SyncErrorClass.auth);
      expect(classifySyncError(403), SyncErrorClass.auth);
    });

    test('5xx → server', () {
      expect(classifySyncError(500), SyncErrorClass.server);
      expect(classifySyncError(502), SyncErrorClass.server);
      expect(classifySyncError(599), SyncErrorClass.server);
    });

    test('other 4xx → unknown (not classified as auth)', () {
      expect(classifySyncError(400), SyncErrorClass.unknown);
      expect(classifySyncError(404), SyncErrorClass.unknown);
      expect(classifySyncError(429), SyncErrorClass.unknown);
    });

    test('200/201 (defensive: not expected here) → unknown', () {
      // Recorder calls classify only on failures, but the function itself
      // must be total.
      expect(classifySyncError(200), SyncErrorClass.unknown);
    });
  });

  group('SyncStalled / SyncUnrecoverable constructor', () {
    test('explicit lastErrorClass overrides auto-classification', () {
      final stalled = SyncStalled(
        sinceLastSuccess: const Duration(minutes: 2),
        consecutiveFailures: 1,
        lastHttpStatus: 500,
        // Force a different class to verify the override path.
        lastErrorClass: SyncErrorClass.auth,
      );
      expect(stalled.lastErrorClass, SyncErrorClass.auth);
    });

    test('toString includes lastErrorClass', () {
      final stalled = SyncStalled(
        sinceLastSuccess: const Duration(minutes: 5),
        consecutiveFailures: 4,
        lastHttpStatus: 401,
      );
      expect(stalled.toString(), contains('lastErrorClass: auth'));
    });
  });
}
