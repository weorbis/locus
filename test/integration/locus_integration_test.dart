/// Integration tests for the Locus SDK.
///
/// These tests verify end-to-end functionality with mocked platform channels.
@TestOn('vm')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> methodCalls;
  late dynamic Function(MethodCall) mockHandler;

  setUp(() {
    methodCalls = [];
    mockHandler = (call) async {
      methodCalls.add(call);
      return _handleMethodCall(call);
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      (call) => mockHandler(call),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('locus/methods'),
      null,
    );
    methodCalls.clear();
  });

  group('Config Integration', () {
    test('ready sends validated config to native', () async {
      final config = Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
        autoSync: false,
      );

      await Locus.ready(config);

      expect(methodCalls, isNotEmpty);
      final readyCall = methodCalls.firstWhere((c) => c.method == 'ready');
      expect(readyCall.arguments, isA<Map>());
      expect(readyCall.arguments['desiredAccuracy'], 'high');
      expect(readyCall.arguments['distanceFilter'], 10);
    });

    test('setConfig updates runtime config', () async {
      final config = Config(
        distanceFilter: 50,
        stopTimeout: 5,
      );

      await Locus.setConfig(config);

      final setCall = methodCalls.firstWhere((c) => c.method == 'setConfig');
      expect(setCall.arguments['distanceFilter'], 50);
      expect(setCall.arguments['stopTimeout'], 5);
    });
  });

  group('Location Operations', () {
    test('getCurrentPosition returns location', () async {
      final location = await Locus.getCurrentPosition();

      expect(location, isA<Location>());
      expect(location.coords.latitude, isNot(0));
      expect(location.coords.longitude, isNot(0));
      expect(location.uuid, isNotEmpty);
    });

    test('getCurrentPosition with options', () async {
      final location = await Locus.getCurrentPosition(
        timeout: 30000, // ms
        maximumAge: 60000, // ms
        desiredAccuracy: 0, // high
        persist: false,
      );

      expect(location, isA<Location>());
      expect(methodCalls.last.arguments['timeout'], 30000);
      expect(methodCalls.last.arguments['maximumAge'], 60000);
      expect(methodCalls.last.arguments['persist'], false);
    });

    test('getLocations returns stored locations', () async {
      final locations = await Locus.getLocations(limit: 10);

      expect(locations, isA<List<Location>>());
    });
  });

  group('Geofence Integration', () {
    test('addGeofence creates geofence on native', () async {
      const geofence = Geofence(
        identifier: 'office',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100,
        notifyOnEntry: true,
        notifyOnExit: true,
        notifyOnDwell: false,
      );

      await Locus.addGeofence(geofence);

      final call = methodCalls.firstWhere((c) => c.method == 'addGeofence');
      expect(call.arguments['identifier'], 'office');
      expect(call.arguments['latitude'], 37.7749);
      expect(call.arguments['radius'], 100);
    });

    test('addGeofences adds multiple geofences', () async {
      final geofences = [
        const Geofence(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 50,
        ),
        const Geofence(
          identifier: 'work',
          latitude: 37.7849,
          longitude: -122.4094,
          radius: 75,
        ),
      ];

      await Locus.addGeofences(geofences);

      final call = methodCalls.firstWhere((c) => c.method == 'addGeofences');
      expect(call.arguments, isA<List>());
      expect((call.arguments as List).length, 2);
    });

    test('removeGeofence removes by identifier', () async {
      await Locus.removeGeofence('office');

      final call = methodCalls.firstWhere((c) => c.method == 'removeGeofence');
      expect(call.arguments, 'office');
    });

    test('getGeofences returns all geofences', () async {
      final geofences = await Locus.getGeofences();

      expect(geofences, isA<List<Geofence>>());
    });
  });

  group('State Management', () {
    test('getState returns current state', () async {
      final state = await Locus.getState();

      expect(state, isA<GeolocationState>());
      expect(state.enabled, isA<bool>());
      expect(state.isMoving, isA<bool>());
    });

    test('start enables tracking', () async {
      await Locus.start();

      expect(methodCalls.any((c) => c.method == 'start'), true);
    });

    test('stop disables tracking', () async {
      await Locus.stop();

      expect(methodCalls.any((c) => c.method == 'stop'), true);
    });

    test('changePace updates motion state', () async {
      await Locus.changePace(true);

      final call = methodCalls.firstWhere((c) => c.method == 'changePace');
      expect(call.arguments, true);
    });
  });

  group('HTTP Sync', () {
    test('sync triggers server sync', () async {
      await Locus.sync();

      expect(methodCalls.any((c) => c.method == 'sync'), true);
    });

    test('destroyLocations clears stored locations', () async {
      await Locus.destroyLocations();

      expect(methodCalls.any((c) => c.method == 'destroyLocations'), true);
    });
  });

  group('Logging', () {
    test('getLog retrieves log entries', () async {
      final log = await Locus.getLog();

      expect(log, isA<List<LogEntry>>());
    });
  });

  group('Battery Optimization Integration', () {
    test('adaptive tracking config is applied', () async {
      await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

      final config = Locus.adaptiveTrackingConfig;
      expect(config, isNotNull);
      expect(config!.enabled, true);
    });

    test('sync policy is applied', () async {
      await Locus.setSyncPolicy(SyncPolicy.conservative);

      expect(methodCalls.any((c) => c.method == 'setSyncPolicy'), true);
    });

    test('power state can be retrieved', () async {
      final power = await Locus.getPowerState();

      expect(power, isA<PowerState>());
      expect(power.batteryLevel, greaterThanOrEqualTo(0));
      expect(power.batteryLevel, lessThanOrEqualTo(100));
    });

    test('battery stats can be retrieved', () async {
      final stats = await Locus.getBatteryStats();

      expect(stats, isA<BatteryStats>());
    });
  });

  group('Advanced Features Integration', () {
    test('spoof detection can be configured', () async {
      await Locus.setSpoofDetection(SpoofDetectionConfig.high);

      expect(Locus.spoofDetectionConfig?.enabled, true);
      expect(Locus.spoofDetectionConfig?.blockMockLocations, true);
    });

    test('significant change monitoring starts and stops', () async {
      await Locus.startSignificantChangeMonitoring(
        SignificantChangeConfig.sensitive,
      );

      expect(Locus.isSignificantChangeMonitoringActive, true);

      await Locus.stopSignificantChangeMonitoring();

      expect(Locus.isSignificantChangeMonitoringActive, false);
    });

    test('error handler can be configured', () {
      Locus.setErrorHandler(ErrorRecoveryConfig.aggressive);

      expect(Locus.errorRecoveryManager, isNotNull);
    });
  });

  group('Lifecycle Integration', () {
    test('lifecycle observing can be started and stopped', () {
      Locus.startLifecycleObserving();
      expect(Locus.isForeground, true);

      Locus.stopLifecycleObserving();
      expect(Locus.isForeground, true);
    });

    test('isTracking returns correct state', () async {
      final result = await Locus.isTracking();
      expect(result, isA<bool>());
    });
  });

  group('Geofence Check', () {
    test('isInActiveGeofence returns boolean', () async {
      final result = await Locus.isInActiveGeofence();
      expect(result, isA<bool>());
    });
  });

  group('Complex Workflows', () {
    test('complete tracking workflow', () async {
      await Locus.ready(Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
        autoSync: false,
      ));

      await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);
      await Locus.setSyncPolicy(SyncPolicy.balanced);

      Locus.setErrorHandler(ErrorRecoveryConfig.defaults);

      await Locus.start();

      final location = await Locus.getCurrentPosition();
      expect(location, isNotNull);

      final state = await Locus.getState();
      expect(state, isNotNull);

      await Locus.stop();

      expect(
          methodCalls.map((c) => c.method),
          containsAllInOrder([
            'ready',
            'setSyncPolicy',
            'start',
            'getCurrentPosition',
            'getState',
            'stop',
          ]));
    });

    test('geofence workflow', () async {
      await Locus.addGeofences([
        const Geofence(
          identifier: 'zone_a',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100,
        ),
        const Geofence(
          identifier: 'zone_b',
          latitude: 38.0,
          longitude: -122.0,
          radius: 200,
        ),
      ]);

      final geofences = await Locus.getGeofences();
      expect(geofences, isA<List<Geofence>>());

      final isIn = await Locus.isInActiveGeofence();
      expect(isIn, isA<bool>());

      await Locus.removeGeofence('zone_a');
      await Locus.removeGeofences();

      expect(methodCalls.where((c) => c.method.contains('Geofence')).length,
          greaterThan(0));
    });

    test('battery optimization workflow', () async {
      final power = await Locus.getPowerState();

      await Locus.setAdaptiveTracking(AdaptiveTrackingConfig(
        enabled: true,
        batteryThresholds: BatteryThresholds(
          lowThreshold: 20,
          criticalThreshold: 10,
        ),
      ));

      final settings = await Locus.calculateAdaptiveSettings();

      if (power.batteryLevel < 10) {
        expect(settings.gpsEnabled, false);
      }

      expect(settings.reason, isNotEmpty);
    });
  });
}

dynamic _handleMethodCall(MethodCall call) {
  switch (call.method) {
    case 'ready':
    case 'setConfig':
    case 'start':
    case 'stop':
    case 'changePace':
    case 'sync':
    case 'emptyLog':
    case 'destroyLocations':
    case 'addGeofence':
    case 'addGeofences':
    case 'removeGeofence':
    case 'removeGeofences':
    case 'setSpoofDetection':
    case 'setSyncPolicy':
    case 'setAdaptiveTracking':
    case 'startSignificantChangeMonitoring':
    case 'stopSignificantChangeMonitoring':
      return null;

    case 'getCurrentPosition':
      return {
        'uuid': 'test-uuid-123',
        'timestamp': DateTime.now().toIso8601String(),
        'isMoving': true,
        'odometer': 0.0,
        'coords': {
          'latitude': 37.7749,
          'longitude': -122.4194,
          'accuracy': 10.0,
          'speed': 5.0,
          'heading': 180.0,
          'altitude': 10.0,
        },
      };

    case 'getLocations':
      return <Map<String, dynamic>>[];

    case 'getState':
      return {
        'enabled': true,
        'isMoving': false,
        'odometer': 1000.0,
      };

    case 'getGeofences':
      return <Map<String, dynamic>>[];

    case 'getLog':
      return [
        {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'level': 'info',
          'message': 'Log entries...',
        }
      ];

    case 'getPowerState':
      return {
        'batteryLevel': 75,
        'isCharging': false,
        'isPowerSaveMode': false,
        'isDozeMode': false,
      };

    case 'getBatteryStats':
      return {
        'gpsOnTimePercent': 50.0,
        'locationUpdatesCount': 100,
        'syncRequestsCount': 5,
        'trackingDurationMinutes': 60,
        'currentBatteryLevel': 75,
        'isCharging': false,
        'estimatedDrainPercent': 5.0,
        'estimatedDrainPerHour': 5.0,
      };

    case 'getNetworkType':
      return 'wifi';

    case 'isMeteredConnection':
      return false;

    default:
      return null;
  }
}
