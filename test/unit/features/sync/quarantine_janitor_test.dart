import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/sync/services/quarantine_janitor.dart';
import 'package:locus/src/observability/locus_reliability_registry.dart';
import 'package:locus/src/observability/reliability_event.dart';

void main() {
  late LocusReliabilityRegistry registry;
  late List<LocusReliabilityEvent> events;
  late StreamSubscription<LocusReliabilityEvent> sub;

  setUp(() async {
    registry = LocusReliabilityRegistry.instance;
    await registry.resetForTests();
    events = <LocusReliabilityEvent>[];
    sub = registry.reliability.listen(events.add);
  });

  tearDown(() async {
    await sub.cancel();
  });

  group('QuarantineJanitor', () {
    test('rejects non-positive ttl', () {
      expect(
        () => QuarantineJanitor(ttl: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects non-positive sweepInterval', () {
      expect(
        () => QuarantineJanitor(sweepInterval: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });

    test('default purger discards nothing and emits no event', () async {
      final janitor = QuarantineJanitor();
      final discarded = await janitor.sweepNow();
      expect(discarded, 0);
      expect(events, isEmpty);
    });

    test('emits QuarantinePurged when the purger reports a positive count', () async {
      final janitor = QuarantineJanitor(
        purger: (ttl) async => 4,
        ttl: const Duration(days: 7),
      );
      final discarded = await janitor.sweepNow();
      await Future<void>.delayed(Duration.zero);
      expect(discarded, 4);
      expect(events, hasLength(1));
      final event = events.single as QuarantinePurged;
      expect(event.count, 4);
      expect(event.olderThan, const Duration(days: 7));
    });

    test('does not emit when purger reports zero', () async {
      final janitor = QuarantineJanitor(purger: (ttl) async => 0);
      await janitor.sweepNow();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('catches purger exceptions and continues', () async {
      var calls = 0;
      final janitor = QuarantineJanitor(
        purger: (ttl) async {
          calls++;
          throw StateError('purge boom');
        },
      );
      final discarded = await janitor.sweepNow();
      await Future<void>.delayed(Duration.zero);
      expect(discarded, 0);
      expect(calls, 1);
      // No reliability event raised on failure.
      expect(events, isEmpty);
    });

    test('start fires an immediate sweep and is idempotent', () async {
      var calls = 0;
      final janitor = QuarantineJanitor(
        purger: (ttl) async {
          calls++;
          return 0;
        },
        // Long enough that the periodic timer cannot fire within the test.
        sweepInterval: const Duration(hours: 1),
      );
      janitor.start();
      janitor.start(); // idempotent
      await Future<void>.delayed(Duration.zero);
      expect(janitor.isRunning, isTrue);
      // Only the start-immediate sweep counts; periodic timer hasn't fired.
      expect(calls, 1);
      await janitor.stop();
      expect(janitor.isRunning, isFalse);
    });
  });
}
