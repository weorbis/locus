import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class introduced by CHANGELOG entry "415 response
/// suppresses compression for 60 minutes" (Q8 §4.2). When a backend or proxy
/// rejects a gzipped POST with HTTP 415, the SDK must drop request
/// compression for the rest of the suppression window and resume in raw
/// JSON. Without that fallback, every gzipped batch would be 415-bounced
/// indefinitely and the queue would never drain.
class Http415CompressionFallbackScenario extends Scenario {
  @override
  String get id => 'http-415-compression-fallback';

  @override
  String get displayName => '415 disables gzip for the fallback window';

  @override
  String get description =>
      'A gzipped POST that hits HTTP 415 must trigger the SDK\'s 60-minute '
      'compression-disable fallback documented in CHANGELOG (Q8 §4.2). The '
      'first request goes out gzipped and is rejected; subsequent requests '
      'in the same suppression window must be sent raw and accepted as 2xx. '
      'Without this fallback the SDK would 415-loop a misconfigured proxy '
      'and the queue would never drain.';

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
    await backend.setMode(MockMode.http415Once);
    await backend.reset();
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    // Phase 1: enqueue two payloads, drive the first sync attempt — expected
    // to produce one 415 (the first compressed POST) and at least one 2xx
    // recovery once the SDK drops gzip and retries.
    for (int i = 0; i < 2; i++) {
      await Locus.dataSync.enqueue(<String, Object?>{
        'type': 'check-in',
        'phase': 'first',
        'index': i,
      });
    }
    await Locus.dataSync.syncQueue();

    final DateTime phase1Deadline =
        DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(phase1Deadline)) {
      final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);
      final bool saw415 = events.any(
        (RecordedEvent e) =>
            e.type == 'http_response_error' &&
            (e.payload['status'] as num?)?.toInt() == 415,
      );
      final bool sawOk = events.any(
        (RecordedEvent e) => e.type == 'http_response_ok',
      );
      if (saw415 && sawOk) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    // Phase 2: enqueue a third payload and drive another sync. The
    // suppression window must still be active, so this request must be sent
    // raw (no gzip) and accepted as 2xx.
    await Locus.dataSync.enqueue(<String, Object?>{
      'type': 'check-in',
      'phase': 'second',
      'index': 0,
    });
    await Locus.dataSync.syncQueue();

    final DateTime phase2Deadline =
        DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(phase2Deadline)) {
      // Stop early if the queue fully drained.
      final List<QueueItem> queue =
          await Locus.dataSync.getQueue(limit: 10);
      if (queue.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    final List<RecordedEvent> httpEvents = ctx.recorder
        .since(ctx.startedAt)
        .where((RecordedEvent e) =>
            e.type == 'http_response_ok' || e.type == 'http_response_error')
        .toList(growable: false);

    final List<AssertionResult> results = <AssertionResult>[];

    if (httpEvents.isEmpty) {
      results.add(
        const AssertionResult.fail(
          'At least one HTTP event was recorded',
          failureDetail: 'No http_response_ok or http_response_error '
              'events captured since scenario start.',
          expected: '>=1 HTTP event',
          actual: '0',
        ),
      );
      return results;
    }

    // Assertion: the first HTTP event was a 415.
    final RecordedEvent firstHttp = httpEvents.first;
    final int firstStatus =
        (firstHttp.payload['status'] as num?)?.toInt() ?? -1;
    if (firstHttp.type == 'http_response_error' && firstStatus == 415) {
      results.add(
        const AssertionResult.pass(
          'First HTTP event in this scenario was a 415 (compressed POST '
          'rejected as unsupported media type)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'First HTTP event in this scenario was a 415 (compressed POST '
          'rejected as unsupported media type)',
          failureDetail:
              'First event was type=${firstHttp.type} status=$firstStatus',
          expected: 'http_response_error status=415',
          actual: '${firstHttp.type} status=$firstStatus',
        ),
      );
    }

    // Assertion: at least one subsequent HTTP event was 2xx.
    final List<RecordedEvent> followingOk = httpEvents
        .skip(1)
        .where((RecordedEvent e) => e.type == 'http_response_ok')
        .toList(growable: false);
    if (followingOk.isNotEmpty) {
      results.add(
        const AssertionResult.pass(
          'A 2xx HTTP event followed the 415 (queue continued to drain)',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'A 2xx HTTP event followed the 415 (queue continued to drain)',
          failureDetail:
              'Only the leading 415 was recorded; no recovery 2xx '
              'observed within the execute window.',
          expected: '>=1 http_response_ok after the 415',
          actual: '0',
        ),
      );
    }

    // Assertion: at least one captured request was gzipped and at least one
    // subsequent request was raw — proves the fallback flipped encoding off.
    final List<MockRequest> requests = backend.recentRequests;
    // recentRequests is newest-first; iterate in chronological order to
    // reason about "first gzipped, then raw".
    final List<MockRequest> chronological =
        requests.reversed.toList(growable: false);
    final int firstGzippedIndex =
        chronological.indexWhere((MockRequest r) => r.isGzipped);
    final bool laterRawSeen = firstGzippedIndex >= 0 &&
        chronological
            .skip(firstGzippedIndex + 1)
            .any((MockRequest r) => !r.isGzipped);

    if (firstGzippedIndex >= 0 && laterRawSeen) {
      results.add(
        const AssertionResult.pass(
          'At least one captured request was gzipped and a later request '
          'was raw — compression fallback flipped encoding off',
        ),
      );
    } else if (firstGzippedIndex < 0) {
      results.add(
        const AssertionResult.fail(
          'At least one captured request was gzipped and a later request '
          'was raw — compression fallback flipped encoding off',
          failureDetail: 'No gzipped request was observed; the SDK did not '
              'attempt compression in this run.',
          expected: '>=1 gzipped request followed by >=1 raw request',
          actual: '0 gzipped requests',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'At least one captured request was gzipped and a later request '
          'was raw — compression fallback flipped encoding off',
          failureDetail:
              'The first ${firstGzippedIndex + 1} request(s) included a '
              'gzipped POST, but no subsequent raw request followed.',
          expected: 'gzipped → raw transition',
          actual: 'gzipped only',
        ),
      );
    }

    if (backend.requestCount >= 3) {
      results.add(
        const AssertionResult.pass(
          'Mock backend received at least 3 inbound requests across the '
          'two sync phases',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Mock backend received at least 3 inbound requests across the '
          'two sync phases',
          failureDetail:
              'requestCount=${backend.requestCount}; insufficient traffic '
              'to evaluate the fallback transition.',
          expected: '>=3',
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
