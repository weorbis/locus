/// Regression coverage for issue #35 — "No Data Sent Backend using api".
///
/// Root cause: sync defaulted to paused on both the Dart cache and the native
/// SyncManager. Host apps that set `Config.url` (including the example) would
/// stream locations in Dart but never actually hit the backend, because every
/// `attemptBatchSync` (auto) and every `Locus.dataSync.now()` (manual) was
/// short-circuited by the pause flag.
///
/// The fix flips the default to active. Pause is now reserved for transport-
/// level auth failures (401/403, persisted across process restart via
/// ConfigManager.setSyncPauseReason) or explicit `Locus.dataSync.pause()`
/// (in-memory only). Domain gating belongs in setPreSyncValidator.
///
/// These tests pin down the PUBLIC API CONTRACT that the fix relies on:
///
///   * `Locus.dataSync.now()` must dispatch to the platform channel without
///     requiring a prior `resume()` call.
///   * `Locus.dataSync.isPaused` reflects the current pause state; after an
///     explicit `pause()` it is true, after `resume()` it is false.
///   * On a simulated cold-restart where native reconciled itself into the
///     paused state (because the previous process recorded a 401), the Dart
///     layer observes that paused state via the backlog getter.
///
/// The cross-restart persistence itself is a native contract — verified
/// on-device (see doc/guides/http-synchronization.md and the smoke protocol
/// in the #35 PR description).
@TestOn('vm')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StatefulSyncMock mock;

  setUp(() {
    mock = _StatefulSyncMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      mock.handle,
    );
  });

  tearDown(() async {
    // Reset Dart-side pause cache between tests. resume() clears it; some
    // tests call pause() and need a clean slate for the next run. Do this
    // BEFORE detaching the mock handler so the resume dispatch has a target.
    await Locus.dataSync.resume();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('locus/methods'), null);
  });

  test(
      'Locus.dataSync.now() dispatches sync without requiring prior resume() '
      '(the #35 regression)', () async {
    expect(Locus.dataSync.isPaused, isFalse,
        reason:
            'Dart cache must default to active — not-paused is the new contract');

    final result = await Locus.dataSync.now();

    expect(result, isTrue);
    expect(mock.calls, contains('sync'),
        reason:
            'Auto-pause used to short-circuit this before the platform channel ran');
  });

  test('pause() then resume() toggles the Dart cache and dispatches both calls',
      () async {
    expect(Locus.dataSync.isPaused, isFalse);

    await Locus.dataSync.pause();
    expect(Locus.dataSync.isPaused, isTrue);
    expect(mock.calls, contains('pauseSync'));

    await Locus.dataSync.resume();
    expect(Locus.dataSync.isPaused, isFalse);
    expect(mock.calls, contains('resumeSync'));
  });

  test('sync() is a no-op while paused and does not hit the platform channel',
      () async {
    await Locus.dataSync.pause();
    mock.calls.clear();

    final result = await Locus.dataSync.now();

    expect(result, isFalse);
    expect(mock.calls, isNot(contains('sync')),
        reason:
            'Dart-side short-circuit must prevent the channel call while paused');
  });

  test(
      'cold-restart with native-persisted auth pause surfaces isPaused=true on '
      'getLocationSyncBacklog (native is source of truth)', () async {
    // Simulate a fresh process where the native SyncManager read a persisted
    // sync_pause_reason of "http_401" on init and therefore starts paused.
    mock.nativePaused = true;

    final backlog = await Locus.dataSync.getBacklog();

    expect(backlog.isPaused, isTrue,
        reason:
            'Native contract: persisted 401 from prior process must be visible after relaunch');

    // Dart cache default is false; this is fine — it's cosmetic until resume()
    // or the first pause-side method call rehydrates it. The authoritative
    // gate is the native SyncManager, which refuses to dispatch while paused.
  });

  test(
      'resume() clears native pause by invoking resumeSync, unblocking subsequent '
      'sync() calls', () async {
    // Start from a "native-paused" state (as if the last process ended with 401).
    mock.nativePaused = true;
    await Locus.dataSync
        .pause(); // also set Dart cache so this test is realistic
    mock.calls.clear();

    await Locus.dataSync.resume();
    expect(mock.calls, contains('resumeSync'));
    expect(mock.nativePaused, isFalse,
        reason: 'resumeSync must actually unpause the native side');

    mock.calls.clear();
    final result = await Locus.dataSync.now();
    expect(result, isTrue);
    expect(mock.calls, contains('sync'));
  });

  group('Reactive pause-state stream', () {
    late MockLocus mockLocus;
    late SyncServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = SyncServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test(
        'pause() emits a SyncPauseState(isPaused: true, reason: "app") on '
        'pauseChanges and updates pauseReason synchronously', () async {
      final events = <SyncPauseState>[];
      final sub = service.pauseChanges.listen(events.add);

      expect(service.isPaused, isFalse);
      expect(service.pauseReason, isNull);

      await service.pause();
      await Future<void>.delayed(Duration.zero);

      expect(service.isPaused, isTrue);
      expect(service.pauseReason, 'app');
      expect(events, hasLength(1));
      expect(events.single.isPaused, isTrue);
      expect(events.single.reason, 'app');
      expect(events.single.isAuthFailure, isFalse);

      await sub.cancel();
    });

    test(
        'resume() emits a SyncPauseState(isPaused: false) and clears the '
        'reason', () async {
      await service.pause();
      final events = <SyncPauseState>[];
      final sub = service.pauseChanges.listen(events.add);

      await service.resume();
      await Future<void>.delayed(Duration.zero);

      expect(service.isPaused, isFalse);
      expect(service.pauseReason, isNull);
      expect(events, hasLength(1));
      expect(events.single.isPaused, isFalse);
      expect(events.single.reason, isNull);

      await sub.cancel();
    });

    test(
        'simulated native 401 auto-pause propagates via emitSyncPauseChange — '
        'UI subscribers observe isAuthFailure without having called pause()',
        () async {
      final events = <SyncPauseState>[];
      final sub = service.pauseChanges.listen(events.add);

      // Simulate the native side receiving a 401 mid-session and pushing the
      // new state over the event channel. The Dart cache must update without
      // the host app doing anything.
      mockLocus.emitSyncPauseChange(
        const SyncPauseState(isPaused: true, reason: 'http_401'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.isPaused, isTrue);
      expect(service.pauseReason, 'http_401');
      expect(events.last.isAuthFailure, isTrue,
          reason: 'isAuthFailure must distinguish 401/403 from "app" pauses');

      await sub.cancel();
    });

    test(
        'repeated pause() calls are idempotent — only one event fires and '
        'state does not churn', () async {
      final events = <SyncPauseState>[];
      final sub = service.pauseChanges.listen(events.add);

      await service.pause();
      await service.pause();
      await service.pause();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1),
          reason:
              'Duplicate pause() should be a no-op and emit exactly once to avoid UI flicker');

      await sub.cancel();
    });
  });
}

/// Stateful mock that simulates the native SyncManager's pause state. The
/// native side is the source of truth — `nativePaused` flips in response to
/// `pauseSync` / `resumeSync` calls, and `getLocationSyncBacklog` reports it
/// back honestly (mirroring the fact that backlog reads read-through native
/// state).
class _StatefulSyncMock {
  bool nativePaused = false;
  final List<String> calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'pauseSync':
        nativePaused = true;
        return null;
      case 'resumeSync':
        nativePaused = false;
        return true;
      case 'sync':
        // Native would refuse while paused; mirror that so assertions match
        // the real contract. (In practice the Dart cache short-circuits first,
        // but if the cache ever goes stale this is the backstop.)
        return !nativePaused;
      case 'getLocationSyncBacklog':
        return <String, Object?>{
          'pendingLocationCount': 0,
          'pendingBatchCount': 0,
          'isPaused': nativePaused,
          'quarantinedLocationCount': 0,
          'lastSuccessAt': null,
          'lastFailureReason': nativePaused ? 'http_401' : null,
          'groups': <Map<String, Object?>>[],
        };
      case 'getSyncPauseState':
        return <String, Object?>{
          'isPaused': nativePaused,
          'reason': nativePaused ? 'http_401' : null,
        };
      case 'ready':
      case 'setConfig':
      case 'getState':
        return <String, Object?>{
          'enabled': false,
          'isMoving': false,
          'odometer': 0.0,
        };
      default:
        return null;
    }
  }
}
