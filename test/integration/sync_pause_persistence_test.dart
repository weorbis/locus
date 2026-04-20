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
    await Locus.dataSync.pause(); // also set Dart cache so this test is realistic
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
