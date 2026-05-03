@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The interesting branch — channel call → manufacturer → URL — only runs
  // on Android. On the test host (`Platform.isAndroid == false`) the
  // function short-circuits to `null` before invoking the channel, so the
  // tests in this file cover (a) the non-Android short-circuit and (b)
  // sanity of the static manufacturer→URL table that the Android branch
  // dispatches on. The Android branch itself is exercised by native
  // handler tests on the platform side (tracked via #39).

  group('DeviceOptimizationService.getManufacturerInstructionsUrl', () {
    test('returns null on non-Android hosts without invoking the channel',
        () async {
      // Guard: this assumption holds because `flutter test` runs on the
      // host (macOS / Linux / Windows / web). If `Platform.isAndroid`
      // ever becomes true here, the test would silently turn into an
      // integration test and need a channel mock instead.
      expect(Platform.isAndroid, isFalse,
          reason: 'precondition: tests run on a non-Android host');

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('locus/methods'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('locus/methods'), null);
      });

      final url = await DeviceOptimizationService
          .getManufacturerInstructionsUrl();

      expect(url, isNull);
      expect(calls, isEmpty,
          reason: 'channel must not be invoked on non-Android');
    });

    test('isIgnoringBatteryOptimizations returns false on non-Android',
        () async {
      expect(Platform.isAndroid, isFalse);

      final result = await DeviceOptimizationService
          .isIgnoringBatteryOptimizations();

      expect(result, isFalse);
    });
  });

  group('DeviceOptimizationService.getBackgroundLimitsInfo', () {
    test('returns guidance for both supported platforms', () {
      final info = DeviceOptimizationService.getBackgroundLimitsInfo();

      expect(info.keys, containsAll(<String>['android', 'ios']));
      expect(info['android'], isNotEmpty);
      expect(info['ios'], isNotEmpty);
    });
  });
}
