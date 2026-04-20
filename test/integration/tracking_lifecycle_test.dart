/// Regression coverage for issue #34 — "Location tracking stops when app is closed
/// despite foreground service being configured".
///
/// The native-level fix (LocusPlugin soft-detach + ForegroundService.onTaskRemoved +
/// bg_tracking_active persistence) must be verified on-device because it spans
/// process lifecycles and OS-level services. These Dart tests pin down the
/// plugin's PUBLIC API CONTRACT that the fix relies on:
///
///   * [Locus.isTracking] must reflect the native tracker's `enabled` flag, not a
///     Dart-side cache. If the native side is kept alive during engine detach and
///     reports `enabled=true` after re-attach, isTracking() must propagate that.
///   * [Locus.start] and [Locus.stop] must invoke the `start` / `stop` method calls
///     verbatim — the native side uses these (not any Dart-side flag) to toggle the
///     persisted `bg_tracking_active` key.
///
/// See also: docs/guides/headless-execution.md (Process Lifecycle section).
@TestOn('vm')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Stateful mock that simulates the native tracker's `enabled` flag surviving
  /// across isTracking() invocations and start/stop cycles. This is the contract
  /// the #34 fix relies on (native is the source of truth; Dart never caches).
  late _StatefulMock mock;

  setUp(() {
    mock = _StatefulMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      mock.handle,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('locus/methods'), null);
  });

  test('isTracking reads native enabled flag every call (no Dart-side cache)',
      () async {
    // Fresh process: native says tracking is off.
    expect(await Locus.isTracking(), isFalse);

    // Native starts tracking.
    mock.nativeEnabled = true;
    expect(await Locus.isTracking(), isTrue);

    // Native stops (e.g. user called Locus.stop, or native auto-stopped).
    mock.nativeEnabled = false;
    expect(await Locus.isTracking(), isFalse);
  });

  test('Locus.start → isTracking true → Locus.stop → isTracking false',
      () async {
    expect(await Locus.isTracking(), isFalse);

    await Locus.start();
    expect(await Locus.isTracking(), isTrue,
        reason: 'Native must report enabled=true after start');

    await Locus.stop();
    expect(await Locus.isTracking(), isFalse,
        reason: 'Native must report enabled=false after stop');

    // Sanity: no stray calls.
    expect(mock.callsOf('start').length, 1);
    expect(mock.callsOf('stop').length, 1);
  });

  test(
      'isTracking returns true on a simulated cold-restart if native re-armed '
      'tracking from bg_tracking_active (#34 reconciliation contract)',
      () async {
    // Before "process restart":
    await Locus.start();
    expect(await Locus.isTracking(), isTrue);

    // Simulate cold restart: new mock, but native has reconciled
    // bg_tracking_active=true → re-armed tracking itself. In the real plugin
    // this happens inside LocusPlugin.onAttachedToEngine (Android) /
    // SwiftLocusPlugin.maybeResumePersistedTracking (iOS).
    final postRestart = _StatefulMock()..nativeEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      postRestart.handle,
    );

    // The UI (Dart) should see tracking=true without having to call start()
    // again. That's the whole point of the persistence reconciliation fix.
    expect(await Locus.isTracking(), isTrue);
    expect(postRestart.callsOf('start'), isEmpty,
        reason: 'Dart must not re-issue start on relaunch; native reconciles');
  });
}

class _StatefulMock {
  bool nativeEnabled = false;
  final List<MethodCall> _calls = <MethodCall>[];

  List<MethodCall> callsOf(String method) =>
      _calls.where((c) => c.method == method).toList();

  Future<Object?> handle(MethodCall call) async {
    _calls.add(call);
    switch (call.method) {
      case 'start':
        nativeEnabled = true;
        return _state();
      case 'stop':
        nativeEnabled = false;
        return _state();
      case 'getState':
      case 'ready':
      case 'setConfig':
        return _state();
      case 'getLocationSyncBacklog':
        return {'pendingLocationCount': 0, 'isPaused': false};
      default:
        return null;
    }
  }

  Map<String, Object> _state() => <String, Object>{
        'enabled': nativeEnabled,
        'isMoving': false,
        'odometer': 0.0,
      };
}
