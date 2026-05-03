import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class fixed in CHANGELOG entry "Auth-failure pause
/// now persists across process restarts (#35)" — specifically the previously-
/// missing 403 leg. Before #35, a 403 paused only in memory; the next cold
/// start would happily retry-storm a stale token. This scenario asserts that
/// the SDK reports `http_403` (or an equivalent reason string containing
/// "403") on the pause-state stream, which is the contract surface
/// `ConfigManager.setSyncPauseReason` now persists across restarts.
class Auth403PersistentPauseScenario extends Scenario {
  @override
  String get id => 'auth-403-persistent-pause';

  @override
  String get displayName => '403 pauses sync persistently';

  @override
  String get description =>
      'A backend that returns HTTP 403 must take the SDK from active → '
      'paused with a 403 reason on the pauseChanges stream. This guards #35: '
      'before that fix 403 paused in memory only and was wiped on the next '
      'cold start, so a permanently-revoked credential would hammer the '
      'backend on every relaunch. The pause must surface a reason string '
      'identifying the 403 path so the host app can render a re-auth '
      'affordance instead of swallowing the failure.';

  @override
  ScenarioCategory get category => ScenarioCategory.httpAdversarial;

  @override
  Duration get expectedDuration => const Duration(seconds: 12);

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
    await backend.setMode(MockMode.auth403);
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
        DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);
      final bool sawError403 = events.any(
        (RecordedEvent e) =>
            e.type == 'http_response_error' &&
            (e.payload['status'] as num?)?.toInt() == 403,
      );
      final bool sawPauseTrue = events.any(
        (RecordedEvent e) =>
            e.type == 'pause_state_changed' &&
            e.payload['isPaused'] == true,
      );
      if (sawError403 && sawPauseTrue) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);
    final List<AssertionResult> results = <AssertionResult>[];

    final List<RecordedEvent> http403s = events
        .where(
          (RecordedEvent e) =>
              e.type == 'http_response_error' &&
              (e.payload['status'] as num?)?.toInt() == 403,
        )
        .toList(growable: false);

    if (http403s.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'SDK observed at least one HTTP 403 response from the backend',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'SDK observed at least one HTTP 403 response from the backend',
          failureDetail: 'No http_response_error event with status==403 '
              'was recorded since scenario start.',
          expected: '>=1 http_response_error with status==403',
          actual: '0',
        ),
      );
    }

    final List<RecordedEvent> pauseTrueWith403Reason = events
        .where((RecordedEvent e) {
          if (e.type != 'pause_state_changed') return false;
          if (e.payload['isPaused'] != true) return false;
          final Object? reason = e.payload['reason'];
          if (reason == null) return false;
          final String reasonStr = reason.toString();
          return reasonStr == 'http_403' || reasonStr.contains('403');
        })
        .toList(growable: false);

    if (pauseTrueWith403Reason.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'Pause-state event identifies the 403 as the cause '
          '(reason contains "403" or equals "http_403")',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Pause-state event identifies the 403 as the cause '
          '(reason contains "403" or equals "http_403")',
          failureDetail:
              'No pause_state_changed event with isPaused==true and a '
              '403-shaped reason was recorded.',
          expected: 'pause_state_changed with reason ~= "http_403"',
          actual: 'none recorded',
        ),
      );
    }

    if (Locus.dataSync.isPaused) {
      results.add(
        const AssertionResult.pass(
          'Locus.dataSync.isPaused is true after the 403 round-trip',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Locus.dataSync.isPaused is true after the 403 round-trip',
          failureDetail: 'Synchronous getter still reports false; '
              'pause did not stick.',
          expected: 'true',
          actual: 'false',
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
