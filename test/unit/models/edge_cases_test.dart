/// Edge case unit tests for comprehensive coverage.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('Location Model', () {
    test('fromMap handles missing optional fields', () {
      final location = Location.fromMap({
        'uuid': 'test',
        'timestamp': DateTime.now().toIso8601String(),
        'isMoving': false,
        'odometer': 0.0,
        'coords': {
          'latitude': 37.0,
          'longitude': -122.0,
          'accuracy': 10.0,
        },
      });

      expect(location.uuid, 'test');
      expect(location.coords.speed, isNull);
      expect(location.activity, isNull);
    });

    test('toMap round-trips correctly', () {
      final original = Location(
        uuid: 'unique-id',
        timestamp: DateTime(2024, 1, 1),
        isMoving: true,
        odometer: 1500.5,
        coords: Coords(
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 5.0,
          speed: 10.0,
          heading: 90.0,
          altitude: 50.0,
        ),
      );

      final map = original.toMap();
      final restored = Location.fromMap(map);

      expect(restored.uuid, original.uuid);
      expect(restored.isMoving, original.isMoving);
      expect(restored.odometer, original.odometer);
      expect(restored.coords.latitude, original.coords.latitude);
      expect(restored.coords.longitude, original.coords.longitude);
    });

    test('Location.fromMap handles empty map', () {
      final location = Location.fromMap(const {});
      expect(location.coords, isNotNull);
      expect(location.timestamp, isNotNull);
    });

    test('Location.fromMap handles nested coords', () {
      final location = Location.fromMap({
        'coords': {
          'latitude': 37.7749,
          'longitude': -122.4194,
          'accuracy': 10.0,
        },
        'timestamp': '2024-01-01T00:00:00Z',
      });
      expect(location.coords.latitude, equals(37.7749));
      expect(location.coords.longitude, equals(-122.4194));
    });
  });

  group('Coords Model', () {
    test('fromMap handles zero values', () {
      final coords = Coords.fromMap({
        'latitude': 0.0,
        'longitude': 0.0,
        'accuracy': 0.0,
      });

      expect(coords.latitude, 0.0);
      expect(coords.longitude, 0.0);
      expect(coords.accuracy, 0.0);
    });

    test('handles extreme coordinates', () {
      final coords = Coords(
        latitude: 90.0, // North pole
        longitude: 180.0,
        accuracy: 100.0,
      );

      expect(coords.latitude, 90.0);
      expect(coords.longitude, 180.0);
    });

    test('Coords.fromMap handles null values', () {
      final coords = Coords.fromMap({
        'latitude': 37.0,
        'longitude': -122.0,
        // accuracy, speed, heading, altitude all null
      });
      expect(coords.latitude, equals(37.0));
      expect(coords.longitude, equals(-122.0));
      expect(coords.accuracy, equals(0.0)); // default when not provided
    });

    test('Coords.fromMap handles int numbers', () {
      final coords = Coords.fromMap({
        'latitude': 37.0,
        'longitude': -122.0,
        'accuracy': 15, // int instead of double
      });
      expect(coords.accuracy, equals(15.0));
    });
  });

  group('Geofence Model', () {
    test('fromMap handles all optional fields', () {
      final geofence = Geofence.fromMap({
        'identifier': 'test',
        'latitude': 37.0,
        'longitude': -122.0,
        'radius': 100,
        'notifyOnEntry': false,
        'notifyOnExit': false,
        'notifyOnDwell': true,
        'loiteringDelay': 30000,
        'extras': {'custom': 'value'},
      });

      expect(geofence.identifier, 'test');
      expect(geofence.notifyOnEntry, false);
      expect(geofence.notifyOnDwell, true);
      expect(geofence.loiteringDelay, 30000);
      expect(geofence.extras?['custom'], 'value');
    });

    test('default values are applied', () {
      const geofence = Geofence(
        identifier: 'basic',
        latitude: 37.0,
        longitude: -122.0,
        radius: 50,
      );

      expect(geofence.notifyOnEntry, true);
      expect(geofence.notifyOnExit, true);
      expect(geofence.notifyOnDwell, false);
    });
  });

  group('Config Validation', () {
    test('Config accepts all accuracy values', () {
      for (final accuracy in DesiredAccuracy.values) {
        final config = Config(desiredAccuracy: accuracy);
        expect(config.desiredAccuracy, accuracy);
      }
    });

    test('Config respects boundaries', () {
      final config = Config(
        distanceFilter: 0, // Minimum
        stopTimeout: 0,
        stopDetectionDelay: 0,
      );

      expect(config.distanceFilter, 0);
    });
  });

  group('PowerState Edge Cases', () {
    test('handles boundary battery levels', () {
      final empty = PowerState(
        batteryLevel: 0,
        isCharging: false,
        isPowerSaveMode: false,
        isDozeMode: false,
      );
      expect(empty.isCriticalBattery, true);

      final full = PowerState(
        batteryLevel: 100,
        isCharging: true,
        isPowerSaveMode: false,
        isDozeMode: false,
      );
      expect(full.shouldRestrictTracking, false);
    });

    test('optimizationSuggestion varies by state', () {
      final lowBattery = PowerState(
        batteryLevel: 5,
        isCharging: false,
        isPowerSaveMode: false,
        isDozeMode: false,
      );
      expect(lowBattery.optimizationSuggestion, isNotNull);
      expect(lowBattery.optimizationSuggestion.reason, contains('Critical'));

      final powerSave = PowerState(
        batteryLevel: 50,
        isCharging: false,
        isPowerSaveMode: true,
        isDozeMode: false,
      );
      expect(powerSave.optimizationSuggestion.reason, contains('save'));
    });
  });

  group('BatteryThresholds Edge Cases', () {
    test('getLevel boundaries', () {
      final thresholds = BatteryThresholds(
        lowThreshold: 30,
        criticalThreshold: 15,
      );

      expect(thresholds.getLevel(100), BatteryLevel.normal);
      expect(thresholds.getLevel(31), BatteryLevel.normal);
      expect(thresholds.getLevel(30), BatteryLevel.low);
      expect(thresholds.getLevel(15), BatteryLevel.critical);
      expect(thresholds.getLevel(0), BatteryLevel.critical);
    });
  });

  group('SpeedTiers Edge Cases', () {
    test('getTier boundaries', () {
      final tiers = SpeedTiers.balanced;

      expect(tiers.getTier(0).name, 'stationary');
      expect(tiers.getTier(4.9).name, 'walking');
      expect(tiers.getTier(5).name, 'city');
      expect(tiers.getTier(29.9).name, 'city');
      expect(tiers.getTier(30).name, 'suburban');
      expect(tiers.getTier(79.9).name, 'suburban');
      expect(tiers.getTier(80).name, 'highway');
      expect(tiers.getTier(200).name, 'highway');
    });

    test('handles negative speed', () {
      final tiers = SpeedTiers.balanced;
      final tier = tiers.getTier(-1);
      expect(tier.name, 'stationary');
    });
  });

  group('SyncPolicy Edge Cases', () {
    test('getBehavior handles all network types', () {
      final policy = SyncPolicy.balanced;

      final wifiDecision = policy.getBehavior(
        networkType: NetworkType.wifi,
        batteryPercent: 50,
        isCharging: false,
        isMetered: false,
        isForeground: true,
      );
      expect(wifiDecision, isNotNull);

      final cellDecision = policy.getBehavior(
        networkType: NetworkType.cellular,
        batteryPercent: 50,
        isCharging: false,
        isMetered: false,
        isForeground: true,
      );
      expect(cellDecision, isNotNull);
    });
  });

  group('SpoofDetector Edge Cases', () {
    test('handles first location gracefully', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 1,
      ));

      final location = _createLocation(lat: 37.0, lng: -122.0);
      final event = detector.analyze(location, isMockProvider: false);

      expect(event, isNull);
    });

    test('reset clears history', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 1,
      ));

      detector.analyze(_createLocation(lat: 37.0, lng: -122.0));
      detector.analyze(_createLocation(lat: 37.0, lng: -122.0));
      detector.analyze(_createLocation(lat: 37.0, lng: -122.0));

      detector.reset();

      final event = detector.analyze(
        _createLocation(lat: 37.0, lng: -122.0),
        isMockProvider: false,
      );
      expect(event, isNull);
    });
  });

  group('ErrorRecoveryManager Edge Cases', () {
    test('respects maxRetryDelay cap', () {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        retryDelay: Duration(seconds: 60),
        retryBackoff: 10.0,
        maxRetryDelay: Duration(minutes: 1),
        logErrors: false,
      ));

      for (var i = 0; i < 10; i++) {
        manager.handleError(LocusError.networkError());
      }

      final delay = manager.getRetryDelay(LocusErrorType.networkError);
      expect(delay, lessThanOrEqualTo(const Duration(minutes: 1)));

      manager.dispose();
    });

    test('scheduleRetry cancels previous timer', () async {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        retryDelay: Duration(milliseconds: 100),
        logErrors: false,
      ));

      var callCount = 0;
      manager.scheduleRetry(LocusErrorType.networkError, () => callCount++);
      manager.scheduleRetry(LocusErrorType.networkError, () => callCount++);

      await Future.delayed(const Duration(milliseconds: 200));

      expect(callCount, 1);

      manager.dispose();
    });
  });

  group('SignificantChangeManager Edge Cases', () {
    test('handles rapid location updates', () async {
      final manager = SignificantChangeManager();
      manager.start(const SignificantChangeConfig(
        minDisplacementMeters: 1000,
        deferUntilMoved: false,
      ));

      final events = <SignificantChangeEvent>[];
      manager.events.listen(events.add);

      for (var i = 0; i < 10; i++) {
        manager.processLocation(_createLocation(lat: 37.0, lng: -122.0));
      }

      await Future.delayed(const Duration(milliseconds: 10));

      expect(events.length, 1);

      manager.dispose();
    });
  });

  group('AdaptiveTrackingConfig Edge Cases', () {
    test('calculateSettings with extreme battery levels', () {
      final config = AdaptiveTrackingConfig.balanced;

      final criticalSettings = config.calculateSettings(
        speedMps: 0,
        batteryPercent: 1,
        isCharging: false,
        isMoving: false,
        activity: null,
        isInGeofence: false,
      );
      expect(criticalSettings.gpsEnabled, false);

      final chargingSettings = config.calculateSettings(
        speedMps: 0,
        batteryPercent: 1,
        isCharging: true,
        isMoving: false,
        activity: null,
        isInGeofence: false,
      );
      expect(chargingSettings.gpsEnabled, true);
    });

    test('calculateSettings respects geofence mode', () {
      final config = AdaptiveTrackingConfig(
        enabled: true,
        geofenceOptimization: true,
      );

      final settings = config.calculateSettings(
        speedMps: 0,
        batteryPercent: 50,
        isCharging: false,
        isMoving: false,
        activity: null,
        isInGeofence: true,
      );
      expect(settings.heartbeatInterval, greaterThan(0));
    });
  });

  group('SyncDecision', () {
    test('factory constructors create correct decisions', () {
      final proceed = SyncDecision(
        shouldSync: true,
        reason: 'Test decision',
      );
      expect(proceed.shouldSync, true);

      final deferred =
          SyncDecision.defer('Low battery', delay: Duration(minutes: 5));
      expect(deferred.shouldSync, false);
      expect(deferred.reason, contains('Low battery'));

      final batched = SyncDecision.batch(50, delay: Duration(seconds: 30));
      expect(batched.shouldSync, true);
      expect(batched.batchLimit, 50);
    });
  });
}

Location _createLocation({
  required double lat,
  required double lng,
  double accuracy = 10,
  DateTime? timestamp,
}) {
  return Location(
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      speed: 0,
      heading: 0,
      altitude: 0,
    ),
    timestamp: timestamp ?? DateTime.now(),
    isMoving: false,
    uuid: 'test-${DateTime.now().millisecondsSinceEpoch}',
    odometer: 0,
  );
}
