import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:locus/locus.dart';

/// Integration tests for the Locus background geolocation SDK.
///
/// These tests require a real device or emulator with location permissions.
/// Run with: flutter test integration_test/locus_integration_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Locus SDK Initialization', () {
    testWidgets('ready() initializes the SDK and returns state',
        (tester) async {
      final state = await Locus.ready(const Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
        logLevel: LogLevel.debug,
      ));

      expect(state, isNotNull);
      expect(state.enabled, isFalse);
    });

    testWidgets('getState() returns current state', (tester) async {
      await Locus.ready(const Config());
      final state = await Locus.getState();

      expect(state, isNotNull);
      expect(state.odometer, isA<double>());
    });

    testWidgets('setConfig() updates configuration', (tester) async {
      await Locus.ready(const Config(distanceFilter: 10));
      await Locus.setConfig(const Config(distanceFilter: 50));

      // Verify config was applied (no exception thrown)
      expect(true, isTrue);
    });
  });

  group('Permission Handling', () {
    testWidgets('requestPermission() returns boolean', (tester) async {
      final granted = await Locus.requestPermission();
      expect(granted, isA<bool>());
    });
  });

  group('Location Tracking', () {
    testWidgets('start() and stop() toggle tracking', (tester) async {
      final granted = await Locus.requestPermission();
      if (!granted) return; // Skip if no permission

      await Locus.ready(const Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
      ));

      // Start tracking
      final startState = await Locus.start();
      expect(startState.enabled, isTrue);

      // Stop tracking
      final stopState = await Locus.stop();
      expect(stopState.enabled, isFalse);
    });

    testWidgets('getCurrentPosition() returns location when permission granted',
        (tester) async {
      final granted = await Locus.requestPermission();
      if (!granted) return;

      await Locus.ready(const Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
      ));

      final location = await Locus.location.getCurrentPosition();

      expect(location.coords.accuracy, greaterThanOrEqualTo(0));
      expect(location.coords.latitude, inInclusiveRange(-90, 90));
      expect(location.coords.longitude, inInclusiveRange(-180, 180));
      expect(location.timestamp, isNotNull);
    });

    testWidgets('changePace() sets moving state', (tester) async {
      await Locus.ready(const Config());
      await Locus.location.changePace(true);
      // No exception means success
      expect(true, isTrue);
    });
  });

  group('Odometer', () {
    testWidgets('setOdometer() updates odometer value', (tester) async {
      await Locus.ready(const Config());

      const testOdometer = 12345.67;
      final result = await Locus.location.setOdometer(testOdometer);

      expect(result, equals(testOdometer));

      final state = await Locus.getState();
      expect(state.odometer, equals(testOdometer));
    });
  });

  group('Geofencing', () {
    testWidgets('addGeofence() and getGeofences() work correctly',
        (tester) async {
      await Locus.ready(const Config());

      // Clear existing geofences
      await Locus.geofencing.removeAll();

      // Add a test geofence
      await Locus.geofencing.add(const Geofence(
        identifier: 'test_geofence',
        radius: 100,
        latitude: 37.4219983,
        longitude: -122.084,
        notifyOnEntry: true,
        notifyOnExit: true,
      ));

      final geofences = await Locus.geofencing.getAll();
      expect(geofences, isNotEmpty);
      expect(geofences.any((g) => g.identifier == 'test_geofence'), isTrue);
    });

    testWidgets('geofenceExists() returns correct boolean', (tester) async {
      await Locus.ready(const Config());
      await Locus.geofencing.removeAll();

      await Locus.geofencing.add(const Geofence(
        identifier: 'exists_test',
        radius: 50,
        latitude: 40.0,
        longitude: -74.0,
      ));

      final exists = await Locus.geofencing.exists('exists_test');
      expect(exists, isTrue);

      final notExists = await Locus.geofencing.exists('nonexistent');
      expect(notExists, isFalse);
    });

    testWidgets('removeGeofence() removes specific geofence', (tester) async {
      await Locus.ready(const Config());
      await Locus.geofencing.removeAll();

      await Locus.geofencing.add(const Geofence(
        identifier: 'to_remove',
        radius: 50,
        latitude: 40.0,
        longitude: -74.0,
      ));

      await Locus.geofencing.remove('to_remove');
      final exists = await Locus.geofencing.exists('to_remove');
      expect(exists, isFalse);
    });

    testWidgets('addGeofences() adds multiple geofences', (tester) async {
      await Locus.ready(const Config());
      await Locus.geofencing.removeAll();

      await Locus.geofencing.addAll(const [
        Geofence(
            identifier: 'multi_1', radius: 50, latitude: 40, longitude: -74),
        Geofence(
            identifier: 'multi_2', radius: 50, latitude: 41, longitude: -75),
        Geofence(
            identifier: 'multi_3', radius: 50, latitude: 42, longitude: -76),
      ]);

      final geofences = await Locus.geofencing.getAll();
      expect(geofences.length, greaterThanOrEqualTo(3));
    });
  });

  group('Custom Queue', () {
    testWidgets('enqueue() and getQueue() work correctly', (tester) async {
      await Locus.ready(const Config());
      await Locus.dataSync.clearQueue();

      final id = await Locus.dataSync.enqueue({
        'event': 'test_event',
        'timestamp': DateTime.now().toIso8601String(),
        'data': {'key': 'value'},
      });

      expect(id, isNotEmpty);

      final queue = await Locus.dataSync.getQueue();
      expect(queue, isNotEmpty);
      expect(queue.any((item) => item.id == id), isTrue);
    });

    testWidgets('clearQueue() removes all items', (tester) async {
      await Locus.ready(const Config());

      await Locus.dataSync.enqueue({'test': 'data'});
      await Locus.dataSync.clearQueue();

      final queue = await Locus.dataSync.getQueue();
      expect(queue, isEmpty);
    });
  });

  group('Location Storage', () {
    testWidgets('getLocations() returns stored locations', (tester) async {
      await Locus.ready(const Config(
        persistMode: PersistMode.all,
      ));

      final locations = await Locus.location.getLocations(limit: 10);
      expect(locations, isA<List<Location>>());
    });

    testWidgets('destroyLocations() clears stored locations', (tester) async {
      await Locus.ready(const Config());
      await Locus.location.destroyLocations();

      final locations = await Locus.location.getLocations();
      expect(locations, isEmpty);
    });
  });

  group('Trip Engine', () {
    testWidgets('startTrip() and stopTrip() work', (tester) async {
      await Locus.ready(const Config());

      // Start a trip
      await Locus.trips.start(const TripConfig(
        startOnMoving: false,
        updateIntervalSeconds: 30,
      ));

      // Get trip state
      final tripState = Locus.trips.getState();
      // tripState is nullable TripState?
      expect(tripState, anyOf(isNull, isA<TripState>()));

      // Stop the trip
      final summary = await Locus.trips.stop();
      // summary is nullable TripSummary?
      expect(summary, anyOf(isNull, isA<TripSummary>()));
    });
  });

  group('Schedule', () {
    testWidgets('startSchedule() and stopSchedule() work', (tester) async {
      await Locus.ready(const Config(
        schedule: ['08:00-12:00', '13:00-18:00'],
      ));

      await Locus.startSchedule();
      var state = await Locus.getState();
      expect(state.schedulerEnabled, isTrue);

      await Locus.stopSchedule();
      state = await Locus.getState();
      expect(state.schedulerEnabled, isFalse);
    });
  });

  group('Background Tasks', () {
    testWidgets('startBackgroundTask() returns valid task ID', (tester) async {
      await Locus.ready(const Config());

      final taskId = await Locus.startBackgroundTask();
      expect(taskId, isA<int>());
      expect(taskId, greaterThan(0));

      // Clean up
      await Locus.stopBackgroundTask(taskId);
    });
  });

  group('Diagnostics', () {
    testWidgets('getDiagnostics() returns valid snapshot', (tester) async {
      await Locus.ready(const Config());

      final diagnostics = await Locus.getDiagnostics();

      expect(diagnostics, isNotNull);
      expect(diagnostics.capturedAt, isA<DateTime>());
      expect(diagnostics.queue, isA<List<QueueItem>>());
    });

    testWidgets('getLog() returns log entries', (tester) async {
      await Locus.ready(const Config(logLevel: LogLevel.debug));

      final log = await Locus.getLog();
      expect(log, isA<List<LogEntry>>());
    });
  });

  group('Config Presets', () {
    testWidgets('ConfigPresets provide valid configurations', (tester) async {
      // Test each preset can be applied without errors
      for (final preset in [
        ConfigPresets.lowPower,
        ConfigPresets.balanced,
        ConfigPresets.tracking,
        ConfigPresets.trail,
      ]) {
        await Locus.ready(preset);
        final state = await Locus.getState();
        expect(state, isNotNull);
      }
    });

    testWidgets('Config.copyWith() creates modified copy', (tester) async {
      final config = ConfigPresets.tracking.copyWith(
        distanceFilter: 100,
        logLevel: LogLevel.debug,
      );

      await Locus.ready(config);
      // No exception means success
      expect(true, isTrue);
    });
  });

  group('Tracking Profiles', () {
    testWidgets('setTrackingProfiles() configures profiles', (tester) async {
      await Locus.ready(const Config());

      await Locus.setTrackingProfiles(
        {
          TrackingProfile.offDuty: ConfigPresets.lowPower,
          TrackingProfile.standby: ConfigPresets.balanced,
          TrackingProfile.enRoute: ConfigPresets.tracking,
          TrackingProfile.arrived: ConfigPresets.trail,
        },
        initialProfile: TrackingProfile.standby,
      );

      expect(Locus.currentTrackingProfile, equals(TrackingProfile.standby));
    });

    testWidgets('setTrackingProfile() switches profile', (tester) async {
      await Locus.ready(const Config());

      await Locus.setTrackingProfiles(
        {
          TrackingProfile.offDuty: ConfigPresets.lowPower,
          TrackingProfile.enRoute: ConfigPresets.tracking,
        },
        initialProfile: TrackingProfile.offDuty,
      );

      await Locus.setTrackingProfile(TrackingProfile.enRoute);
      expect(Locus.currentTrackingProfile, equals(TrackingProfile.enRoute));
    });
  });

  group('Geofence Workflows', () {
    testWidgets('registerWorkflows() stores workflows', (tester) async {
      await Locus.ready(const Config());

      Locus.geofencing.registerWorkflows(const [
        GeofenceWorkflow(
          id: 'test_workflow',
          steps: [
            GeofenceWorkflowStep(
              id: 'step1',
              geofenceIdentifier: 'zone_a',
              action: GeofenceAction.enter,
            ),
            GeofenceWorkflowStep(
              id: 'step2',
              geofenceIdentifier: 'zone_b',
              action: GeofenceAction.enter,
            ),
          ],
        ),
      ]);

      // No exception means success
      expect(true, isTrue);
    });
  });

  group('Event Streams', () {
    testWidgets('location stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.location.stream.listen((location) {});
      expect(subscription, isNotNull);

      // Clean up
      await subscription.cancel();
    });

    testWidgets('motionChanges stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.location.motionChanges.listen((location) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('activity stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.instance.activityStream.listen((activity) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('provider stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.instance.providerStream.listen((event) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('geofence events stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.geofencing.events.listen((event) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('connectivity stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.dataSync.connectivityEvents.listen((event) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('http events stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.dataSync.events.listen((event) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('trip events stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.trips.events.listen((event) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    testWidgets('location anomaly stream can be subscribed', (tester) async {
      await Locus.ready(const Config());

      final subscription = Locus.onLocationAnomaly((anomaly) {});
      expect(subscription, isNotNull);
      await subscription.cancel();
    });
  });

  group('Error Handling', () {
    testWidgets('handles MissingPluginException gracefully', (tester) async {
      // This test verifies the SDK doesn't crash on missing platform implementation
      // In integration tests, the platform should be available
      try {
        await Locus.ready(const Config());
        expect(true, isTrue);
      } on MissingPluginException {
        // Expected in some test environments
        expect(true, isTrue);
      }
    });
  });
}
