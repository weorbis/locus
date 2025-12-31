/// Specialized tests for geofences and complex workflows.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Location> locationStream;
  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];
    locationStream = StreamController<Location>.broadcast();

    // Mock platform channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      (call) async {
        methodCalls.add(call);
        return null; // Most methods return void/null
      },
    );
  });

  tearDown(() {
    locationStream.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      null,
    );
  });

  group('Geofence Workflows', () {
    test('Sequential Geofence Chain', () async {
      // Scenario: User must visit A -> B -> C in order
      // This is simulated by adding B only after A triggers, etc.

      // 1. Add Geofence A
      final zoneA = Geofence(
        identifier: 'zone_a',
        latitude: 37.0,
        longitude: -122.0,
        radius: 100,
        notifyOnEntry: true,
      );
      await Locus.addGeofence(zoneA);

      expect(methodCalls.last.method, 'addGeofence');
      expect(methodCalls.last.arguments['identifier'], 'zone_a');

      // Simulate entry into A (would come from platform)
      // For this test, we verify the logic we would implement in an app using the SDK

      // 2. Add Geofence B (simulating "User entered A, now tracking B")
      final zoneB = Geofence(
        identifier: 'zone_b',
        latitude: 37.1,
        longitude: -122.1,
        radius: 100,
        notifyOnEntry: true,
      );
      await Locus.addGeofence(zoneB);
      // And remove A to stop tracking it
      await Locus.removeGeofence('zone_a');

      expect(
          methodCalls.map((c) => c.method),
          containsAllInOrder(
            ['addGeofence', 'addGeofence', 'removeGeofence'],
          ));
    });

    test('Mass Geofence Update', () async {
      // Scenario: Updating a large list of geofences (e.g., loaded from API)
      final newGeofences = List.generate(
        100,
        (i) => Geofence(
          identifier: 'store_$i',
          latitude: 37.7 + (i * 0.001),
          longitude: -122.4 + (i * 0.001),
          radius: 50,
        ),
      );

      // Clearing old ones and adding new ones
      await Locus.removeGeofences();
      await Locus.addGeofences(newGeofences);

      expect(methodCalls.length, 2);
      expect(methodCalls[0].method, 'removeGeofences');
      expect(methodCalls[1].method, 'addGeofences');
      expect((methodCalls[1].arguments as List).length, 100);
    });

    test('Geofence Dwell Workflow', () async {
      // Scenario: Only trigger if user dwells for 5 minutes
      final dwellZone = Geofence(
        identifier: 'dwell_zone',
        latitude: 37.5,
        longitude: -122.5,
        radius: 200,
        notifyOnEntry: false,
        notifyOnExit: false,
        notifyOnDwell: true,
        loiteringDelay: 300000, // 5 minutes (in ms)
      );

      await Locus.addGeofence(dwellZone);

      final call = methodCalls.last;
      expect(call.method, 'addGeofence');
      expect(call.arguments['loiteringDelay'], 300000);
      expect(call.arguments['notifyOnDwell'], true);
      expect(call.arguments['notifyOnEntry'], false);
    });
  });

  group('Performance Profile Switching', () {
    test('Dynamic Profile Switching', () async {
      // Scenario: App switches profiles based on app state/actions

      // 1. App starts -> Balanced
      await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);
      expect(Locus.adaptiveTrackingConfig?.enabled, true);

      // 2. User starts navigation -> High Accuracy
      await Locus.setAdaptiveTracking(const AdaptiveTrackingConfig(
        enabled: true,
        speedTiers: SpeedTiers.driving,
        batteryThresholds: BatteryThresholds.conservative,
        stationaryGpsOff: false, // Keep GPS on for nav
      ));

      // 3. User stops navigation -> Power Save
      await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);
      expect(Locus.adaptiveTrackingConfig?.stationaryGpsOff, true);
    });
  });
}
