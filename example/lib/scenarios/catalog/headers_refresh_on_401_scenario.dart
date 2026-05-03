import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Guards the regression class touched by CHANGELOG entries "Native 401
/// recovery now retries once before pausing sync" and "Android: 401-recovery
/// retry crashes with `NetworkOnMainThreadException`". On a 401, the
/// foreground headers callback registered via
/// `Locus.dataSync.setHeadersCallback` must fire at least once, and the
/// refreshed headers must reach the network on the retry — otherwise the
/// SDK falls back to the persistent pause path with stale credentials.
class HeadersRefreshOn401Scenario extends Scenario {
  /// Number of times the headers callback was invoked during this scenario
  /// run. Owned by the scenario instance so verify can read it without
  /// relying on a static.
  int _callbackInvocations = 0;

  @override
  String get id => 'headers-refresh-on-401';

  @override
  String get displayName => '401 triggers headers refresh callback';

  @override
  String get description =>
      'A 401 must invoke the foreground headers callback registered via '
      '`Locus.dataSync.setHeadersCallback` so the host app can refresh its '
      'auth token before the SDK gives up and pauses. Guards two related '
      'CHANGELOG entries: "Native 401 recovery now retries once before '
      'pausing sync" (the retry must actually run) and the Android '
      '`NetworkOnMainThreadException` crash that previously dropped the '
      'retry batch. The refreshed Authorization header must also reach the '
      'wire — otherwise the callback fires but the recovery is cosmetic.';

  @override
  ScenarioCategory get category => ScenarioCategory.httpAdversarial;

  @override
  Duration get expectedDuration => const Duration(seconds: 15);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => true;

  Future<Map<String, String>> _provideHeaders() async {
    _callbackInvocations += 1;
    return <String, String>{
      'Authorization': 'Bearer scenario-refreshed-token',
    };
  }

  @override
  Future<void> setup(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    _callbackInvocations = 0;
    if (Locus.dataSync.isPaused) {
      await Locus.dataSync.resume();
    }
    await Locus.dataSync.clearQueue();
    await Locus.dataSync.setHeadersCallback(_provideHeaders);
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

    // Wait until either the headers callback ran or the SDK gave up and
    // emitted a pause-state transition. Either is a terminating condition
    // for the execute phase; verify decides what passes.
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (_callbackInvocations > 0) {
        // Give the SDK a beat to apply the refreshed headers before we
        // exit, so verify can observe the resulting wire-level request.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final List<RecordedEvent> events = ctx.recorder.since(ctx.startedAt);
      final bool sawPause = events.any(
        (RecordedEvent e) => e.type == 'pause_state_changed',
      );
      if (_callbackInvocations > 0 || sawPause) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    final List<AssertionResult> results = <AssertionResult>[];

    if (_callbackInvocations >= 1) {
      results.add(
        AssertionResult.pass(
          'Headers refresh callback was invoked at least once '
          '($_callbackInvocations invocation(s) recorded)',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Headers refresh callback was invoked at least once',
          failureDetail: 'The callback registered via '
              'Locus.dataSync.setHeadersCallback was never called during '
              'the 401 recovery path.',
          expected: '>=1 invocation',
          actual: '0',
        ),
      );
    }

    final List<MockRequest> requestsWithRefreshedAuth = backend.recentRequests
        .where((MockRequest r) =>
            (r.headers['authorization'] ?? '') ==
            'Bearer scenario-refreshed-token')
        .toList(growable: false);

    if (requestsWithRefreshedAuth.isNotEmpty) {
      results.add(
        AssertionResult.pass(
          'A request carried the refreshed Authorization header, proving '
          'the headers callback output reached the wire '
          '(${requestsWithRefreshedAuth.length} request(s) matched)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'A request carried the refreshed Authorization header, proving '
          'the headers callback output reached the wire',
          failureDetail:
              'Inspected ${backend.recentRequests.length} captured '
              'request(s); none had Authorization=='
              '"Bearer scenario-refreshed-token". The callback fired '
              'but its return value did not flow through to the network '
              'request.',
          expected: 'authorization=="Bearer scenario-refreshed-token"',
          actual: 'no matching request',
        ),
      );
    }

    // The SDK may either pause (auth failure persisted) or remain active
    // (refresh succeeded against the mock — though the mock here returns
    // 401 unconditionally, so a pause is the expected steady state). Either
    // outcome is acceptable for this scenario; we record but do not enforce.
    results.add(
      AssertionResult.skip(
        'Pause-vs-no-pause outcome is implementation-defined here',
        failureDetail:
            'isPaused=${Locus.dataSync.isPaused} '
            'pauseReason=${Locus.dataSync.pauseReason ?? "(none)"} — '
            'recorded for context, not asserted.',
      ),
    );

    return results;
  }

  @override
  Future<void> teardown(ScenarioContext ctx) async {
    final MockBackend backend = ctx.backend!;
    try {
      await Locus.dataSync.setHeadersCallback(null);
    } on Object catch (error, stack) {
      ctx.recorder.log(
        EventCategory.error,
        'teardown_clear_headers_callback_failed',
        payload: <String, Object?>{
          'error': error.toString(),
          'stack': stack.toString(),
        },
        sourceId: id,
      );
    }
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
