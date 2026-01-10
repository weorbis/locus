import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

/// Helper to check if a method was called (matches method name prefix)
bool _wasMethodCalled(MockLocus mock, String methodName) {
  return mock.methodCalls.any((call) => call.startsWith(methodName));
}

void main() {
  group('LocationServiceImpl', () {
    late MockLocus mockLocus;
    late LocationServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = LocationServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<LocationService>());
    });

    test('stream delegates to locationStream', () async {
      final locations = <Location>[];
      final sub = service.stream.listen(locations.add);

      final testLocation = MockLocationExtension.mock(
        latitude: 37.4219,
        longitude: -122.084,
      );
      mockLocus.emitLocation(testLocation);

      await Future.delayed(Duration.zero);
      expect(locations.length, 1);
      expect(locations.first.coords.latitude, 37.4219);

      await sub.cancel();
    });

    test('motionChanges delegates to motionChangeStream', () async {
      final events = <Location>[];
      final sub = service.motionChanges.listen(events.add);

      mockLocus.emitMotionChange(MockLocationExtension.mock(isMoving: true));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.isMoving, isTrue);

      await sub.cancel();
    });

    test('heartbeats delegates to heartbeatStream', () async {
      final events = <Location>[];
      final sub = service.heartbeats.listen(events.add);

      mockLocus.emitHeartbeat(MockLocationExtension.mock());

      await Future.delayed(Duration.zero);
      expect(events.length, 1);

      await sub.cancel();
    });

    test('getCurrentPosition delegates to instance', () async {
      final testLocation = MockLocationExtension.mock(
        latitude: 51.5074,
        longitude: -0.1278,
      );
      mockLocus.emitLocation(testLocation);

      final current = await service.getCurrentPosition();
      expect(current.coords.latitude, 51.5074);
      expect(current.coords.longitude, -0.1278);
    });

    test('getCurrentPosition passes parameters correctly', () async {
      mockLocus.emitLocation(MockLocationExtension.mock());

      await service.getCurrentPosition(
        samples: 3,
        timeout: 5000,
        maximumAge: 1000,
        persist: true,
        desiredAccuracy: 10,
        extras: {'key': 'value'},
      );

      expect(_wasMethodCalled(mockLocus, 'getCurrentPosition'), isTrue);
    });

    test('getLocations delegates to instance', () async {
      mockLocus.emitLocation(MockLocationExtension.mock(latitude: 1));
      mockLocus.emitLocation(MockLocationExtension.mock(latitude: 2));

      final locations = await service.getLocations();
      expect(locations.length, 2);
    });

    test('getLocations respects limit parameter', () async {
      mockLocus.emitLocation(MockLocationExtension.mock());
      mockLocus.emitLocation(MockLocationExtension.mock());
      mockLocus.emitLocation(MockLocationExtension.mock());

      final locations = await service.getLocations(limit: 2);
      expect(locations.length, 2);
    });

    test('query delegates to queryLocations', () async {
      mockLocus.emitLocation(MockLocationExtension.mock());

      final query = LocationQuery(
        from: DateTime.now().subtract(const Duration(hours: 1)),
        to: DateTime.now(),
        limit: 100,
      );

      final result = await service.query(query);
      expect(result, isA<List<Location>>());
    });

    test('getSummary delegates to getLocationSummary', () async {
      final summary = await service.getSummary(date: DateTime.now());
      expect(summary, isA<LocationSummary>());
    });

    test('changePace delegates to instance', () async {
      await service.changePace(true);
      final state = await mockLocus.getState();
      expect(state.isMoving, isTrue);

      await service.changePace(false);
      final state2 = await mockLocus.getState();
      expect(state2.isMoving, isFalse);
    });

    test('setOdometer delegates to instance', () async {
      await service.setOdometer(5000);
      final state = await mockLocus.getState();
      expect(state.odometer, 5000);
    });

    test('destroyLocations delegates to instance', () async {
      mockLocus.emitLocation(MockLocationExtension.mock());
      mockLocus.emitLocation(MockLocationExtension.mock());

      var locations = await service.getLocations();
      expect(locations.length, 2);

      await service.destroyLocations();
      locations = await service.getLocations();
      expect(locations, isEmpty);
    });

    test('onLocation subscription works', () async {
      final locations = <Location>[];
      final sub = service.onLocation(locations.add);

      mockLocus.emitLocation(MockLocationExtension.mock(latitude: 40.7128));
      await Future.delayed(Duration.zero);

      expect(locations.length, 1);
      expect(locations.first.coords.latitude, 40.7128);

      await sub.cancel();
    });

    test('onMotionChange subscription works', () async {
      final events = <Location>[];
      final sub = service.onMotionChange(events.add);

      mockLocus.emitMotionChange(MockLocationExtension.mock(isMoving: true));
      await Future.delayed(Duration.zero);

      expect(events.length, 1);
      await sub.cancel();
    });

    test('onHeartbeat subscription works', () async {
      final events = <Location>[];
      final sub = service.onHeartbeat(events.add);

      mockLocus.emitHeartbeat(MockLocationExtension.mock());
      await Future.delayed(Duration.zero);

      expect(events.length, 1);
      await sub.cancel();
    });
  });

  group('GeofenceServiceImpl', () {
    late MockLocus mockLocus;
    late GeofenceServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = GeofenceServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<GeofenceService>());
    });

    test('events delegates to geofenceStream', () async {
      final events = <GeofenceEvent>[];
      final sub = service.events.listen(events.add);

      final testGeofence = MockGeofenceExtension.mock(identifier: 'test');
      mockLocus.emitGeofenceEvent(GeofenceEvent(
        geofence: testGeofence,
        action: GeofenceAction.enter,
        location: MockLocationExtension.mock(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.geofence.identifier, 'test');
      expect(events.first.action, GeofenceAction.enter);

      await sub.cancel();
    });

    test('add delegates to addGeofence', () async {
      final geofence = MockGeofenceExtension.mock(
        identifier: 'office',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100,
      );

      await service.add(geofence);

      final geofences = await mockLocus.getGeofences();
      expect(geofences.length, 1);
      expect(geofences.first.identifier, 'office');
    });

    test('addAll delegates to addGeofences', () async {
      final geofences = [
        MockGeofenceExtension.mock(identifier: 'a'),
        MockGeofenceExtension.mock(identifier: 'b'),
        MockGeofenceExtension.mock(identifier: 'c'),
      ];

      await service.addAll(geofences);

      final stored = await mockLocus.getGeofences();
      expect(stored.length, 3);
    });

    test('remove delegates to removeGeofence', () async {
      await service.add(MockGeofenceExtension.mock(identifier: 'temp'));
      expect(await service.exists('temp'), isTrue);

      await service.remove('temp');
      expect(await service.exists('temp'), isFalse);
    });

    test('removeAll delegates to removeGeofences', () async {
      await service.addAll([
        MockGeofenceExtension.mock(identifier: 'x'),
        MockGeofenceExtension.mock(identifier: 'y'),
      ]);

      await service.removeAll();

      final geofences = await service.getAll();
      expect(geofences, isEmpty);
    });

    test('getAll delegates to getGeofences', () async {
      await service.addAll([
        MockGeofenceExtension.mock(identifier: 'home'),
        MockGeofenceExtension.mock(identifier: 'work'),
      ]);

      final geofences = await service.getAll();
      expect(geofences.length, 2);
    });

    test('get delegates to getGeofence', () async {
      await service.add(MockGeofenceExtension.mock(
        identifier: 'target',
        radius: 250,
      ));

      final geofence = await service.get('target');
      expect(geofence, isNotNull);
      expect(geofence!.identifier, 'target');
      expect(geofence.radius, 250);
    });

    test('get returns null for non-existent geofence', () async {
      final geofence = await service.get('nonexistent');
      expect(geofence, isNull);
    });

    test('exists delegates to geofenceExists', () async {
      await service.add(MockGeofenceExtension.mock(identifier: 'exists'));

      expect(await service.exists('exists'), isTrue);
      expect(await service.exists('notexists'), isFalse);
    });

    test('startMonitoring delegates to startGeofences', () async {
      final result = await service.startMonitoring();
      expect(result, isA<bool>());
      expect(_wasMethodCalled(mockLocus, 'startGeofences'), isTrue);
    });

    test('onGeofence subscription works', () async {
      final events = <GeofenceEvent>[];
      final sub = service.onGeofence(events.add);

      final testGeofence = MockGeofenceExtension.mock(identifier: 'work');
      mockLocus.emitGeofenceEvent(GeofenceEvent(
        geofence: testGeofence,
        action: GeofenceAction.exit,
        location: MockLocationExtension.mock(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.action, GeofenceAction.exit);

      await sub.cancel();
    });

    test('registerWorkflows delegates to registerGeofenceWorkflows', () {
      final workflows = [
        const GeofenceWorkflow(
          id: 'workflow-1',
          steps: [
            GeofenceWorkflowStep(
              id: 'step-1',
              geofenceIdentifier: 'office',
              action: GeofenceAction.enter,
            ),
          ],
        ),
      ];

      service.registerWorkflows(workflows);
      expect(_wasMethodCalled(mockLocus, 'registerGeofenceWorkflows'), isTrue);
    });

    test('getWorkflowState delegates to instance', () {
      final state = service.getWorkflowState('test-workflow');
      // May be null if workflow doesn't exist
      expect(state, isNull);
    });

    test('clearWorkflows delegates to clearGeofenceWorkflows', () {
      service.clearWorkflows();
      expect(_wasMethodCalled(mockLocus, 'clearGeofenceWorkflows'), isTrue);
    });

    test('stopWorkflows delegates to stopGeofenceWorkflows', () {
      service.stopWorkflows();
      expect(_wasMethodCalled(mockLocus, 'stopGeofenceWorkflows'), isTrue);
    });

    test('isInActiveGeofence delegates to instance', () async {
      final result = await service.isInActiveGeofence();
      expect(result, isA<bool>());
    });
  });

  group('PrivacyServiceImpl', () {
    late MockLocus mockLocus;
    late PrivacyServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = PrivacyServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<PrivacyService>());
    });

    test('add delegates to addPrivacyZone', () async {
      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      await service.add(zone);
      expect(_wasMethodCalled(mockLocus, 'addPrivacyZone'), isTrue);
    });

    test('addAll delegates to addPrivacyZones', () async {
      final zones = [
        PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ),
        PrivacyZone.create(
          identifier: 'work',
          latitude: 37.7849,
          longitude: -122.4094,
          radius: 50.0,
        ),
      ];

      await service.addAll(zones);
      expect(_wasMethodCalled(mockLocus, 'addPrivacyZones'), isTrue);
    });

    test('remove delegates to removePrivacyZone', () async {
      final zone = PrivacyZone.create(
        identifier: 'temp',
        latitude: 37.0,
        longitude: -122.0,
        radius: 100.0,
      );
      await service.add(zone);

      final result = await service.remove('temp');
      expect(result, isA<bool>());
      expect(_wasMethodCalled(mockLocus, 'removePrivacyZone'), isTrue);
    });

    test('removeAll delegates to removeAllPrivacyZones', () async {
      await service.removeAll();
      expect(_wasMethodCalled(mockLocus, 'removeAllPrivacyZones'), isTrue);
    });

    test('get delegates to getPrivacyZone', () async {
      final zone = await service.get('test');
      expect(zone, isNull); // No zone added
      expect(_wasMethodCalled(mockLocus, 'getPrivacyZone'), isTrue);
    });

    test('getAll delegates to getPrivacyZones', () async {
      final zones = await service.getAll();
      expect(zones, isA<List<PrivacyZone>>());
      expect(_wasMethodCalled(mockLocus, 'getPrivacyZones'), isTrue);
    });

    test('setEnabled delegates to setPrivacyZoneEnabled', () async {
      final zone = PrivacyZone.create(
        identifier: 'toggle',
        latitude: 37.0,
        longitude: -122.0,
        radius: 100.0,
      );
      await service.add(zone);

      final result = await service.setEnabled('toggle', false);
      expect(result, isA<bool>());
      expect(_wasMethodCalled(mockLocus, 'setPrivacyZoneEnabled'), isTrue);
    });

    test('events stream is accessible', () {
      expect(service.events, isA<Stream<PrivacyZoneEvent>>());
    });

    test('onChange sets up listener', () async {
      final events = <PrivacyZoneEvent>[];
      service.onChange(events.add);

      // Verify no crash - actual event emission would require MockLocus support
      expect(events, isEmpty);
    });
  });

  group('TripServiceImpl', () {
    late MockLocus mockLocus;
    late TripServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = TripServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<TripService>());
    });

    test('events delegates to tripEvents', () async {
      final events = <TripEvent>[];
      final sub = service.events.listen(events.add);

      mockLocus.emitTripEvent(TripEvent(
        type: TripEventType.tripStart,
        tripId: 'test-trip',
        timestamp: DateTime.now(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.type, TripEventType.tripStart);

      await sub.cancel();
    });

    test('start delegates to startTrip', () async {
      const config = TripConfig(tripId: 'delivery-123');
      await service.start(config);
      expect(_wasMethodCalled(mockLocus, 'startTrip'), isTrue);
    });

    test('stop delegates to stopTrip', () async {
      final summary = await service.stop();
      // MockLocus always returns a summary, but real impl may return null if no trip active
      expect(summary, isA<TripSummary?>());
      expect(_wasMethodCalled(mockLocus, 'stopTrip'), isTrue);
    });

    test('getState delegates to getTripState', () {
      final state = service.getState();
      // May be null if no trip is active
      expect(state, isNull);
      expect(_wasMethodCalled(mockLocus, 'getTripState'), isTrue);
    });

    test('onEvent subscription works', () async {
      final events = <TripEvent>[];
      final sub = service.onEvent(events.add);

      mockLocus.emitTripEvent(TripEvent(
        type: TripEventType.tripUpdate,
        tripId: 'test-trip',
        timestamp: DateTime.now(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.type, TripEventType.tripUpdate);

      await sub.cancel();
    });
  });

  group('SyncServiceImpl', () {
    late MockLocus mockLocus;
    late SyncServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = SyncServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<SyncService>());
    });

    test('events delegates to httpStream', () async {
      final events = <HttpEvent>[];
      final sub = service.events.listen(events.add);

      mockLocus.emitHttpEvent(const HttpEvent(
        responseText: '{"success": true}',
        status: 200,
        ok: true,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.ok, isTrue);
      expect(events.first.status, 200);

      await sub.cancel();
    });

    test('connectivityEvents delegates to connectivityStream', () async {
      final events = <ConnectivityChangeEvent>[];
      final sub = service.connectivityEvents.listen(events.add);

      mockLocus.emitConnectivityChange(const ConnectivityChangeEvent(
        connected: true,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.connected, isTrue);

      await sub.cancel();
    });

    test('now delegates to sync', () async {
      // Must resume first since sync is paused by default
      await service.resume();
      final result = await service.now();
      expect(result, isA<bool>());
      expect(_wasMethodCalled(mockLocus, 'sync'), isTrue);
    });

    test('resume delegates to resumeSync', () async {
      final result = await service.resume();
      expect(result, isA<bool>());
      expect(_wasMethodCalled(mockLocus, 'resumeSync'), isTrue);
    });

    test('setPolicy delegates to setSyncPolicy', () async {
      const policy = SyncPolicy(
        lowBatteryThreshold: 20,
        preferWifi: true,
      );

      await service.setPolicy(policy);
      expect(_wasMethodCalled(mockLocus, 'setSyncPolicy'), isTrue);
    });

    test('evaluatePolicy delegates to evaluateSyncPolicy', () async {
      const policy = SyncPolicy(lowBatteryThreshold: 10);
      final decision = await service.evaluatePolicy(policy: policy);
      expect(decision, isA<SyncDecision>());
    });

    test('setSyncBodyBuilder delegates to instance', () async {
      await service.setSyncBodyBuilder((locations, extras) async {
        return {'locations': locations.length};
      });
      expect(_wasMethodCalled(mockLocus, 'setSyncBodyBuilder'), isTrue);
    });

    test('clearSyncBodyBuilder delegates to instance', () {
      service.clearSyncBodyBuilder();
      expect(_wasMethodCalled(mockLocus, 'clearSyncBodyBuilder'), isTrue);
    });

    test('setHeadersCallback delegates to instance', () {
      service.setHeadersCallback(() async => {'Authorization': 'Bearer token'});
      expect(_wasMethodCalled(mockLocus, 'setHeadersCallback'), isTrue);
    });

    test('clearHeadersCallback delegates to instance', () {
      service.clearHeadersCallback();
      expect(_wasMethodCalled(mockLocus, 'clearHeadersCallback'), isTrue);
    });

    test('refreshHeaders delegates to instance', () async {
      await service.refreshHeaders();
      expect(_wasMethodCalled(mockLocus, 'refreshHeaders'), isTrue);
    });

    test('enqueue delegates to instance', () async {
      final id = await service.enqueue({'event': 'test', 'value': 42});
      expect(id, isNotEmpty);

      final queue = await service.getQueue();
      expect(queue.length, 1);
      expect(queue.first.payload['event'], 'test');
    });

    test('enqueue with type and idempotencyKey', () async {
      final id = await service.enqueue(
        {'action': 'check-in'},
        type: 'attendance',
        idempotencyKey: 'unique-123',
      );
      expect(id, isNotEmpty);
    });

    test('getQueue delegates to instance', () async {
      await service.enqueue({'a': 1});
      await service.enqueue({'b': 2});
      await service.enqueue({'c': 3});

      final queue = await service.getQueue();
      expect(queue.length, 3);

      final limitedQueue = await service.getQueue(limit: 2);
      expect(limitedQueue.length, 2);
    });

    test('clearQueue delegates to instance', () async {
      await service.enqueue({'data': 'test'});
      var queue = await service.getQueue();
      expect(queue, isNotEmpty);

      await service.clearQueue();
      queue = await service.getQueue();
      expect(queue, isEmpty);
    });

    test('syncQueue delegates to instance', () async {
      await service.enqueue({'payload': 'data'});
      final count = await service.syncQueue();
      expect(count, isA<int>());
    });

    test('onHttp subscription works', () async {
      final events = <HttpEvent>[];
      final sub = service.onHttp(events.add);

      mockLocus.emitHttpEvent(const HttpEvent(
        responseText: '{}',
        status: 201,
        ok: true,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.status, 201);

      await sub.cancel();
    });

    test('onConnectivityChange subscription works', () async {
      final events = <ConnectivityChangeEvent>[];
      final sub = service.onConnectivityChange(events.add);

      mockLocus.emitConnectivityChange(const ConnectivityChangeEvent(
        connected: false,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.connected, isFalse);

      await sub.cancel();
    });
  });

  group('BatteryServiceImpl', () {
    late MockLocus mockLocus;
    late BatteryServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = BatteryServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('can be instantiated with a mock provider', () {
      expect(service, isA<BatteryService>());
    });

    test('powerStateEvents stream is accessible', () {
      expect(service.powerStateEvents, isA<Stream<PowerStateChangeEvent>>());
    });

    test('powerSaveChanges stream is accessible', () async {
      final changes = <bool>[];
      final sub = service.powerSaveChanges.listen(changes.add);

      mockLocus.emitPowerSaveChange(true);
      await Future.delayed(Duration.zero);

      expect(changes.length, 1);
      expect(changes.first, isTrue);

      await sub.cancel();
    });

    test('getStats delegates to getBatteryStats', () async {
      final stats = await service.getStats();
      expect(stats, isA<BatteryStats>());
    });

    test('getPowerState delegates to instance', () async {
      final state = await service.getPowerState();
      expect(state, isA<PowerState>());
    });

    test('estimateRunway delegates to estimateBatteryRunway', () async {
      final runway = await service.estimateRunway();
      expect(runway, isA<BatteryRunway>());
    });

    test('setAdaptiveTracking delegates to instance', () async {
      const config = AdaptiveTrackingConfig.balanced;
      await service.setAdaptiveTracking(config);
      expect(_wasMethodCalled(mockLocus, 'setAdaptiveTracking'), isTrue);
    });

    test('adaptiveTrackingConfig getter works', () {
      final config = service.adaptiveTrackingConfig;
      // May be null initially
      expect(config, isNull);
    });

    test('calculateAdaptiveSettings delegates to instance', () async {
      final settings = await service.calculateAdaptiveSettings();
      expect(settings, isA<AdaptiveSettings>());
    });

    test('startBenchmark delegates to startBatteryBenchmark', () async {
      await service.startBenchmark();
      expect(_wasMethodCalled(mockLocus, 'startBatteryBenchmark'), isTrue);
    });

    test('stopBenchmark delegates to stopBatteryBenchmark', () async {
      final result = await service.stopBenchmark();
      // May be null if no benchmark running
      expect(result, isNull);
      expect(_wasMethodCalled(mockLocus, 'stopBatteryBenchmark'), isTrue);
    });

    test('recordBenchmarkLocationUpdate delegates to instance', () {
      service.recordBenchmarkLocationUpdate(accuracy: 10.5);
      expect(
        _wasMethodCalled(mockLocus, 'recordBenchmarkLocationUpdate'),
        isTrue,
      );
    });

    test('recordBenchmarkSync delegates to instance', () {
      service.recordBenchmarkSync();
      expect(_wasMethodCalled(mockLocus, 'recordBenchmarkSync'), isTrue);
    });

    test('onPowerStateChange subscription works', () async {
      final events = <PowerStateChangeEvent>[];
      final sub = service.onPowerStateChange(events.add);

      mockLocus.emitPowerStateChange(PowerStateChangeEvent(
        previous: PowerState.unknown,
        current: const PowerState(batteryLevel: 80, isCharging: false),
        changeType: PowerStateChangeType.batteryLevel,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.current.batteryLevel, 80);

      await sub.cancel();
    });

    test('onPowerSaveChange subscription works', () async {
      final changes = <bool>[];
      final sub = service.onPowerSaveChange(changes.add);

      mockLocus.emitPowerSaveChange(false);
      await Future.delayed(Duration.zero);

      expect(changes.length, 1);
      expect(changes.first, isFalse);

      await sub.cancel();
    });
  });

  group('Service Provider Pattern', () {
    test('services can share the same mock provider', () async {
      final mockLocus = MockLocus();
      MockLocus provider() => mockLocus;

      final locationService = LocationServiceImpl(provider);
      final geofenceService = GeofenceServiceImpl(provider);
      final privacyService = PrivacyServiceImpl(provider);
      final tripService = TripServiceImpl(provider);
      final syncService = SyncServiceImpl(provider);
      final batteryService = BatteryServiceImpl(provider);

      // All services are usable
      expect(locationService, isA<LocationService>());
      expect(geofenceService, isA<GeofenceService>());
      expect(privacyService, isA<PrivacyService>());
      expect(tripService, isA<TripService>());
      expect(syncService, isA<SyncService>());
      expect(batteryService, isA<BatteryService>());

      await mockLocus.dispose();
    });

    test('provider is called lazily when methods are invoked', () async {
      var providerCalls = 0;
      final mockLocus = MockLocus();

      final service = LocationServiceImpl(() {
        providerCalls++;
        return mockLocus;
      });

      // Provider not called until we use the service
      expect(providerCalls, 0);

      // Access a method
      await service.getLocations();
      expect(providerCalls, greaterThan(0));

      await mockLocus.dispose();
    });

    test('stream access invokes provider', () async {
      var providerCalls = 0;
      final mockLocus = MockLocus();

      final service = LocationServiceImpl(() {
        providerCalls++;
        return mockLocus;
      });

      // Access stream
      final _ = service.stream;
      expect(providerCalls, greaterThan(0));

      await mockLocus.dispose();
    });
  });
}
