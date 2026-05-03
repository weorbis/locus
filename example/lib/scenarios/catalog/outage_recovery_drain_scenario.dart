import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class fixed in CHANGELOG entry "Backlog stalls
/// after a transient backend outage" (#34). Before that fix,
/// `drainExhaustedContexts` was only cleared in `resumeSync()`, so an outage
/// that flipped every active context into the exhausted set would leave the
/// drain stuck even after a 2xx came back. The fix made `recordSyncSuccess`
/// clear the set, so the drain self-heals on any 2xx — exactly what this
/// scenario reproduces.
class OutageRecoveryDrainScenario extends Scenario {
  @override
  String get id => 'outage-recovery-drain';

  @override
  String get displayName => 'Drain resumes after transient outage';

  @override
  ScenarioCategory get category => ScenarioCategory.sync;

  @override
  Duration get expectedDuration => const Duration(seconds: 25);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => true;

  @override
  String get description =>
      'A backend that returns 5x HTTP 503 then flips to 200 must let the '
      'queue drain to empty without manual intervention. This guards #34: '
      'before the fix, an outage would mark every context as exhausted and '
      'the drain stayed wedged after recovery, because the exhausted set '
      'was only cleared in resumeSync(). Now any 2xx must self-heal the '
      'drain so queued payloads ship without an explicit pause/resume.';

  @override
  Future<void> setup(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    if (Locus.dataSync.isPaused) {
      await Locus.dataSync.resume();
    }
    await Locus.dataSync.clearQueue();
    await backend.setMode(MockMode.outage);
    await backend.reset();
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    for (int i = 0; i < 5; i++) {
      await Locus.dataSync.enqueue(<String, Object?>{
        'type': 'check-in',
        'index': i,
      });
    }

    // Drive sync attempts in a bounded poll loop until the queue empties or
    // we hit the time budget. The mock returns 503 for the first 5 hits and
    // 200 thereafter, so the drain should self-heal once a 2xx lands.
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await Locus.dataSync.syncQueue();
      await Future<void>.delayed(const Duration(seconds: 1));
      final List<QueueItem> queue =
          await Locus.dataSync.getQueue(limit: 10);
      if (queue.isEmpty) break;
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);

    final List<RecordedEvent> http503s = events
        .where(
          (RecordedEvent e) =>
              e.type == 'http_response_error' &&
              (e.payload['status'] as num?)?.toInt() == 503,
        )
        .toList(growable: false);
    final List<RecordedEvent> http2xx = events
        .where((RecordedEvent e) => e.type == 'http_response_ok')
        .toList(growable: false);

    final List<AssertionResult> results = <AssertionResult>[];

    if (http503s.isNotEmpty) {
      results.add(
        AssertionResult.pass(
          'SDK observed at least one HTTP 503 during the outage window '
          '(${http503s.length} recorded)',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'SDK observed at least one HTTP 503 during the outage window',
          failureDetail: 'No http_response_error event with status==503 '
              'was recorded.',
          expected: '>=1 http_response_error with status==503',
          actual: '0',
        ),
      );
    }

    if (http2xx.isNotEmpty) {
      results.add(
        AssertionResult.pass(
          'SDK observed at least one 2xx HTTP event after the outage '
          'cleared (${http2xx.length} recorded)',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'SDK observed at least one 2xx HTTP event after the outage '
          'cleared',
          failureDetail: 'No http_response_ok recorded; recovery 2xx '
              'never landed.',
          expected: '>=1 http_response_ok',
          actual: '0',
        ),
      );
    }

    final List<QueueItem> finalQueue =
        await Locus.dataSync.getQueue(limit: 50);
    if (finalQueue.isEmpty) {
      results.add(
        const AssertionResult.pass(
          'Queue drained to empty after the outage recovered '
          '(self-healing drainExhaustedContexts)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Queue drained to empty after the outage recovered '
          '(self-healing drainExhaustedContexts)',
          failureDetail:
              'getQueue() still returned ${finalQueue.length} item(s) at '
              'the end of the execute window — drain stayed wedged.',
          expected: '0',
          actual: '${finalQueue.length}',
        ),
      );
    }

    if (backend.requestCount >= 6) {
      results.add(
        AssertionResult.pass(
          'Mock backend received at least 6 inbound requests '
          '(5 outage + at least 1 recovery), saw ${backend.requestCount}',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Mock backend received at least 6 inbound requests '
          '(5 outage + at least 1 recovery)',
          failureDetail:
              'requestCount=${backend.requestCount}; the SDK never made '
              'enough attempts to traverse the outage window.',
          expected: '>=6',
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
