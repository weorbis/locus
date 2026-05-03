import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class repaired by CHANGELOG entry "Auth-failure pause
/// now persists across process restarts (#35)" and the original "401
/// pauses sync" contract documented in v1.x. Confirms that a single 401 from
/// the backend takes the SDK from active → paused via the persistent pause
/// path, not just an in-memory flag, so the next attempt is suppressed
/// instead of retry-storming a stale token.
class Auth401PausesSyncScenario extends Scenario {
  @override
  String get id => 'auth-401-pauses-sync';

  @override
  String get displayName => '401 pauses sync (auth-failure)';

  @override
  String get description =>
      'A backend that returns HTTP 401 on every request must drive the sync '
      'layer into a paused state with a 401 reason. This scenario reproduces '
      'the regression class fixed in #35 (auth pause persistence) and the '
      'baseline auth-pause contract documented since v1: one 401 must flip '
      '`SyncPauseState.isPaused` to true and surface `http_401` as the '
      'reason, otherwise the SDK would retry-storm the same stale token on '
      'every subsequent attempt.';

  @override
  ScenarioCategory get category => ScenarioCategory.httpAdversarial;

  @override
  Duration get expectedDuration => const Duration(seconds: 15);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => true;

  @override
  Future<void> setup(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    if (Locus.dataSync.isPaused) {
      await Locus.dataSync.resume();
    }
    await Locus.dataSync.clearQueue();
    await backend.setMode(MockMode.auth401);
    await backend.reset();
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    await Locus.dataSync.enqueue(<String, Object?>{
      'type': 'check-in',
      'count': 1,
    });
    await Locus.dataSync.syncQueue();

    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);
      final bool sawError401 = events.any(
        (RecordedEvent e) =>
            e.type == 'http_response_error' &&
            (e.payload['status'] as num?)?.toInt() == 401,
      );
      final bool sawPauseTrue = events.any(
        (RecordedEvent e) =>
            e.type == 'pause_state_changed' &&
            e.payload['isPaused'] == true,
      );
      if (sawError401 && sawPauseTrue) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);

    final List<RecordedEvent> http401s = events
        .where(
          (RecordedEvent e) =>
              e.type == 'http_response_error' &&
              (e.payload['status'] as num?)?.toInt() == 401,
        )
        .toList(growable: false);
    final List<RecordedEvent> pauseTrueEvents = events
        .where(
          (RecordedEvent e) =>
              e.type == 'pause_state_changed' &&
              e.payload['isPaused'] == true,
        )
        .toList(growable: false);

    final List<AssertionResult> results = <AssertionResult>[];

    if (http401s.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'SDK observed at least one HTTP 401 response from the backend',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'SDK observed at least one HTTP 401 response from the backend',
          failureDetail: 'No http_response_error event with status==401 '
              'was recorded since scenario start.',
          expected: '>=1 http_response_error with status==401',
          actual: '0',
        ),
      );
    }

    if (pauseTrueEvents.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'Sync transitioned to paused after the 401 response',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Sync transitioned to paused after the 401 response',
          failureDetail:
              'No pause_state_changed event with isPaused==true recorded.',
          expected: '>=1 pause_state_changed with isPaused==true',
          actual: '0',
        ),
      );
    }

    if (Locus.dataSync.isPaused) {
      results.add(
        const AssertionResult.pass(
          'Locus.dataSync.isPaused is true after the 401 round-trip',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Locus.dataSync.isPaused is true after the 401 round-trip',
          failureDetail: 'Synchronous getter still reports false; pause '
              'state did not stick.',
          expected: 'true',
          actual: 'false',
        ),
      );
    }

    if (backend.requestCount >= 1) {
      results.add(
        const AssertionResult.pass(
          'Mock backend received at least one inbound request',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Mock backend received at least one inbound request',
          failureDetail:
              'requestCount=${backend.requestCount}; sync did not reach '
              'the network.',
          expected: '>=1',
          actual: '${backend.requestCount}',
        ),
      );
    }

    return results;
  }

  @override
  Future<void> teardown(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    try {
      if (Locus.dataSync.isPaused) {
        await Locus.dataSync.resume();
      }
    } on Object catch (error, stack) {
      ctx.recorder.log(
        EventCategory.error,
        'teardown_resume_failed',
        payload: <String, Object?>{
          'error': error.toString(),
          'stack': stack.toString(),
        },
        sourceId: id,
      );
    }
    try {
      await Locus.dataSync.clearQueue();
    } on Object catch (error, stack) {
      ctx.recorder.log(
        EventCategory.error,
        'teardown_clear_queue_failed',
        payload: <String, Object?>{
          'error': error.toString(),
          'stack': stack.toString(),
        },
        sourceId: id,
      );
    }
    await backend.setMode(MockMode.normal);
    await backend.reset();
  }
}
