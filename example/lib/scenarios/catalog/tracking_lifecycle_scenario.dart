import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Polling cadence while waiting for the first `location_update` to land.
/// Tight enough that a fresh fix is observed within ~250ms; loose enough
/// that we don't busy-loop the event loop while the SDK warms up.
const Duration _kLocationPollInterval = Duration(milliseconds: 250);

/// Maximum wall-clock time we wait for the first location after `start()`.
/// Real devices on cold-start typically deliver within 2–4s; emulators on a
/// new process may need longer. Ten seconds keeps the scenario tight while
/// tolerating a slow first GNSS fix.
const Duration _kFirstLocationTimeout = Duration(seconds: 10);

/// Settle delay after `stop()`/`isTracking` toggles so the platform side
/// can flush its `_isTracking` flag before we read it back.
const Duration _kSettleDelay = Duration(milliseconds: 200);

/// Scenario: tracking lifecycle (start → location → stop).
///
/// Guards against regressions where calling [Locus.start] does not actually
/// emit location updates, or [Locus.stop] leaves stream subscriptions alive
/// past the call. Both have shipped before (notably as part of the lifecycle
/// rework around issue #34) and would not be caught by a pure unit test —
/// they require a real platform channel + GNSS handshake.
class TrackingLifecycleScenario implements Scenario {
  @override
  String get id => 'tracking-lifecycle';

  @override
  String get displayName => 'Tracking lifecycle (start → location → stop)';

  @override
  ScenarioCategory get category => ScenarioCategory.lifecycle;

  @override
  Duration get expectedDuration => const Duration(seconds: 15);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => false;

  @override
  String get description =>
      'Asserts the end-to-end tracking lifecycle: calling Locus.start() must '
      'produce at least one location_update on the recorder within 10 seconds, '
      'and Locus.stop() must transition Locus.isTracking() back to false. '
      'Protects against regressions where start() succeeds but the location '
      'stream never fires (foreground service started without subscribing to '
      'the fused-location callback) and where stop() returns success but '
      'leaves native subscriptions alive draining battery.';

  @override
  Future<void> setup(ScenarioContext ctx) async {
    if (await Locus.isTracking()) {
      await Locus.stop();
    }
    // Allow native to settle before we begin: stop() returns as soon as the
    // request reaches native, but the underlying `LocationManager` may still
    // be unwinding when execute() runs.
    await Future<void>.delayed(_kSettleDelay);
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    await Locus.start();
    ctx.log('tracking_start_called');

    final Stopwatch sw = Stopwatch()..start();
    bool sawLocation = false;
    while (sw.elapsed < _kFirstLocationTimeout) {
      final List<RecordedEvent> recent = ctx.recorder.since(ctx.startedAt);
      final bool hasLocation = recent.any(
        (RecordedEvent e) =>
            e.category == EventCategory.location &&
            e.type == 'location_update',
      );
      if (hasLocation) {
        sawLocation = true;
        ctx.log(
          'first_location_observed',
          payload: <String, Object?>{
            'elapsedMs': sw.elapsedMilliseconds,
          },
        );
        break;
      }
      await Future<void>.delayed(_kLocationPollInterval);
    }
    sw.stop();

    if (!sawLocation) {
      ctx.log(
        'first_location_timeout',
        payload: <String, Object?>{
          'elapsedMs': sw.elapsedMilliseconds,
        },
      );
    }

    await Locus.stop();
    ctx.log('tracking_stop_called');
    await Future<void>.delayed(_kSettleDelay);
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final List<RecordedEvent> trace = ctx.recorder.since(ctx.startedAt);

    final List<RecordedEvent> locations = trace
        .where((RecordedEvent e) =>
            e.category == EventCategory.location &&
            e.type == 'location_update')
        .toList(growable: false);

    final RecordedEvent? timeoutMarker = trace
        .where((RecordedEvent e) =>
            e.category == EventCategory.scenario &&
            e.type == 'first_location_timeout')
        .cast<RecordedEvent?>()
        .firstWhere((_) => true, orElse: () => null);

    final List<AssertionResult> results = <AssertionResult>[];

    if (locations.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'At least one location_update was emitted after Locus.start()',
        ),
      );
    } else {
      final Object? elapsedMs = timeoutMarker?.payload['elapsedMs'];
      results.add(
        AssertionResult.fail(
          'At least one location_update was emitted after Locus.start()',
          failureDetail:
              'No location_update events arrived within $_kFirstLocationTimeout '
              '(elapsedMs=${elapsedMs ?? '?'}). Either Locus.start() did not '
              'subscribe to the platform location stream, or no fix was '
              'available — check device permissions and GNSS state.',
          expected: '>=1 location_update',
          actual: '0 location_update events in trace',
        ),
      );
    }

    final bool stillTracking = await Locus.isTracking();
    if (!stillTracking) {
      results.add(
        const AssertionResult.pass(
          'Locus.isTracking() returns false after Locus.stop()',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Locus.isTracking() returns false after Locus.stop()',
          failureDetail:
              'Locus.isTracking() still reports true after Locus.stop() '
              'returned. The native side may have failed to teardown the '
              'foreground service or to clear its `_isTracking` flag.',
          expected: false,
          actual: true,
        ),
      );
    }

    final List<RecordedEvent> errors = trace
        .where((RecordedEvent e) => e.category == EventCategory.error)
        .toList(growable: false);
    if (errors.isEmpty) {
      results.add(
        const AssertionResult.pass(
          'No error-category events fired during the lifecycle',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'No error-category events fired during the lifecycle',
          failureDetail:
              '${errors.length} error event(s) recorded; first: '
              '${errors.first.type} (${errors.first.payload})',
          expected: 0,
          actual: errors.length,
        ),
      );
    }

    return results;
  }

  @override
  Future<void> teardown(ScenarioContext ctx) async {
    try {
      if (await Locus.isTracking()) {
        await Locus.stop();
      }
    } on Object catch (error) {
      // Teardown is best-effort: surface the failure as a scenario marker
      // so the trace is informative, but never propagate — the runner has
      // already captured the verdict.
      ctx.log(
        'teardown_stop_failed',
        payload: <String, Object?>{'error': error.toString()},
      );
    }
  }
}
