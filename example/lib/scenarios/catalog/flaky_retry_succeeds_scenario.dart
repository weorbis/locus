import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class that motivated the SDK's reliability
/// observability work (CHANGELOG: "tracking heartbeat and sync health
/// monitoring", `SyncStalled` / `SyncUnrecoverable` reliability events). A
/// backend that alternates 500 / 200 must NOT trip the SDK into giving up —
/// retry-with-success is the load-bearing path that lets a real, jittery
/// production backend drain the queue. If retry stops on the first 500 the
/// queue stalls forever and SyncStalled fires for no good reason.
class FlakyRetrySucceedsScenario extends Scenario {
  @override
  String get id => 'flaky-retry-succeeds';

  @override
  String get displayName => 'Flaky 500/200 alternation eventually drains';

  @override
  ScenarioCategory get category => ScenarioCategory.sync;

  @override
  Duration get expectedDuration => const Duration(seconds: 30);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => true;

  @override
  String get description =>
      'A backend that alternates HTTP 500 and 200 must not stall the queue. '
      'This guards the retry-with-success path documented in the SDK\'s '
      'reliability observability work: every odd-numbered request fails, '
      'every even-numbered succeeds, and the queue must still drain to '
      'empty. If the SDK gave up on the first 500 the queue would wedge '
      'and SyncStalled would fire even though the backend is recoverable.';

  @override
  Future<void> setup(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    if (Locus.dataSync.isPaused) {
      await Locus.dataSync.resume();
    }
    await Locus.dataSync.clearQueue();
    await backend.setMode(MockMode.flaky);
    await backend.reset();
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    for (int i = 0; i < 4; i++) {
      await Locus.dataSync.enqueue(<String, Object?>{
        'type': 'check-in',
        'index': i,
      });
    }

    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      await Locus.dataSync.syncQueue();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final List<QueueItem> queue =
          await Locus.dataSync.getQueue(limit: 50);
      if (queue.isEmpty) break;
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);

    final List<RecordedEvent> httpErrors = events
        .where((RecordedEvent e) => e.type == 'http_response_error')
        .toList(growable: false);
    final List<RecordedEvent> httpOks = events
        .where((RecordedEvent e) => e.type == 'http_response_ok')
        .toList(growable: false);

    final List<AssertionResult> results = <AssertionResult>[];

    if (httpErrors.length >= 2) {
      results.add(
        AssertionResult.pass(
          'SDK observed at least 2 HTTP error events from the flaky '
          'backend (${httpErrors.length} recorded)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'SDK observed at least 2 HTTP error events from the flaky '
          'backend',
          failureDetail:
              'http_response_error count=${httpErrors.length}; the SDK '
              'did not exercise enough of the flaky cycle to verify '
              'retry behavior.',
          expected: '>=2 http_response_error events',
          actual: '${httpErrors.length}',
        ),
      );
    }

    if (httpOks.length >= 2) {
      results.add(
        AssertionResult.pass(
          'SDK observed at least 2 successful HTTP events between the '
          'failures (${httpOks.length} recorded)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'SDK observed at least 2 successful HTTP events between the '
          'failures',
          failureDetail: 'http_response_ok count=${httpOks.length}; '
              'recovery 2xx responses were not delivered or not retried.',
          expected: '>=2 http_response_ok events',
          actual: '${httpOks.length}',
        ),
      );
    }

    final List<QueueItem> finalQueue =
        await Locus.dataSync.getQueue(limit: 50);
    if (finalQueue.isEmpty) {
      results.add(
        const AssertionResult.pass(
          'Queue drained to empty despite alternating 500s — retry path '
          'kept making progress',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Queue drained to empty despite alternating 500s — retry path '
          'kept making progress',
          failureDetail:
              'getQueue() still returned ${finalQueue.length} item(s) at '
              'the end of the execute window — retry stopped making '
              'progress against the flaky backend.',
          expected: '0',
          actual: '${finalQueue.length}',
        ),
      );
    }

    if (backend.requestCount >= 8) {
      results.add(
        AssertionResult.pass(
          'Mock backend received at least 8 inbound requests across the '
          'retry cycles, saw ${backend.requestCount}',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Mock backend received at least 8 inbound requests across the '
          'retry cycles',
          failureDetail:
              'requestCount=${backend.requestCount}; the SDK did not '
              'retry enough times to exercise the flaky path.',
          expected: '>=8',
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
