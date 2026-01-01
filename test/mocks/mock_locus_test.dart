import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('MockLocus', () {
    late MockLocus mock;

    setUp(() {
      mock = MockLocus();
    });

    tearDown(() {
      mock.dispose();
    });

    test('starts in not ready state', () {
      expect(mock.isReady, isFalse);
    });

    test('ready() sets isReady and stores config', () async {
      const config = Config(distanceFilter: 25);
      await mock.ready(config);

      expect(mock.isReady, isTrue);
      expect(mock.config.distanceFilter, 25);
      expect(mock.methodCalls.contains('ready'), isTrue);
    });

    test('start() enables tracking', () async {
      final state = await mock.start();

      expect(state.enabled, isTrue);
      expect(mock.methodCalls.contains('start'), isTrue);
    });

    test('stop() disables tracking', () async {
      await mock.start();
      final state = await mock.stop();

      expect(state.enabled, isFalse);
      expect(mock.methodCalls.contains('stop'), isTrue);
    });

    test('setMockState updates state', () async {
      mock.setMockState(const GeolocationState(
        enabled: true,
        isMoving: true,
        odometer: 1000,
      ));

      final state = await mock.getState();
      expect(state.enabled, isTrue);
      expect(state.isMoving, isTrue);
      expect(state.odometer, 1000);
    });

    test('emitLocation adds to storage and stream', () async {
      final locations = <Location>[];
      mock.locationStream.listen(locations.add);

      final location = MockLocationExtension.mock(
        latitude: 37.4219,
        longitude: -122.084,
      );
      mock.emitLocation(location);

      await Future.delayed(Duration.zero);
      expect(locations.length, 1);
      expect(locations.first.coords.latitude, 37.4219);

      final stored = await mock.getLocations();
      expect(stored.length, 1);
    });

    test('getCurrentPosition returns last stored location', () async {
      final location = MockLocationExtension.mock(
        latitude: 51.5074,
        longitude: -0.1278,
      );
      mock.emitLocation(location);

      final current = await mock.getCurrentPosition();
      expect(current.coords.latitude, 51.5074);
      expect(current.coords.longitude, -0.1278);
    });

    test('getCurrentPosition returns default when no locations', () async {
      final current = await mock.getCurrentPosition();
      expect(current.uuid, 'mock-uuid');
      expect(current.coords.latitude, 0);
    });

    group('geofence operations', () {
      test('addGeofence stores geofence', () async {
        final geofence = MockGeofenceExtension.mock(
          identifier: 'home',
          latitude: 37.4219,
          longitude: -122.084,
          radius: 100,
        );
        await mock.addGeofence(geofence);

        final geofences = await mock.getGeofences();
        expect(geofences.length, 1);
        expect(geofences.first.identifier, 'home');
      });

      test('geofenceExists returns correct value', () async {
        final geofence = MockGeofenceExtension.mock(identifier: 'work');
        await mock.addGeofence(geofence);

        expect(await mock.geofenceExists('work'), isTrue);
        expect(await mock.geofenceExists('home'), isFalse);
      });

      test('removeGeofence deletes geofence', () async {
        final geofence = MockGeofenceExtension.mock(identifier: 'temp');
        await mock.addGeofence(geofence);
        expect(await mock.geofenceExists('temp'), isTrue);

        await mock.removeGeofence('temp');
        expect(await mock.geofenceExists('temp'), isFalse);
      });

      test('addGeofences adds multiple', () async {
        await mock.addGeofences([
          MockGeofenceExtension.mock(identifier: 'a'),
          MockGeofenceExtension.mock(identifier: 'b'),
          MockGeofenceExtension.mock(identifier: 'c'),
        ]);

        final geofences = await mock.getGeofences();
        expect(geofences.length, 3);
      });

      test('removeGeofences clears all', () async {
        await mock.addGeofences([
          MockGeofenceExtension.mock(identifier: 'x'),
          MockGeofenceExtension.mock(identifier: 'y'),
        ]);
        await mock.removeGeofences();

        final geofences = await mock.getGeofences();
        expect(geofences, isEmpty);
      });
    });

    group('queue operations', () {
      test('enqueue adds to queue', () async {
        final id = await mock.enqueue({'event': 'test', 'value': 42});

        expect(id, isNotEmpty);
        final queue = await mock.getQueue();
        expect(queue.length, 1);
        expect(queue.first.payload['event'], 'test');
      });

      test('clearQueue empties queue', () async {
        await mock.enqueue({'a': 1});
        await mock.enqueue({'b': 2});
        await mock.clearQueue();

        final queue = await mock.getQueue();
        expect(queue, isEmpty);
      });
    });

    test('changePace updates isMoving state', () async {
      await mock.changePace(true);
      var state = await mock.getState();
      expect(state.isMoving, isTrue);

      await mock.changePace(false);
      state = await mock.getState();
      expect(state.isMoving, isFalse);
    });

    test('setOdometer updates odometer', () async {
      await mock.setOdometer(5000);
      final state = await mock.getState();
      expect(state.odometer, 5000);
    });

    test('destroyLocations clears storage', () async {
      mock.emitLocation(MockLocationExtension.mock());
      mock.emitLocation(MockLocationExtension.mock());

      var locations = await mock.getLocations();
      expect(locations.length, 2);

      await mock.destroyLocations();
      locations = await mock.getLocations();
      expect(locations, isEmpty);
    });

    test('methodCalls tracks all calls', () async {
      mock.clearMethodCalls();

      await mock.ready(const Config());
      await mock.start();
      await mock.getState();
      await mock.stop();

      expect(mock.methodCalls, ['ready', 'start', 'getState', 'stop']);
    });

    test('clearMethodCalls resets history', () async {
      await mock.ready(const Config());
      expect(mock.methodCalls, isNotEmpty);

      mock.clearMethodCalls();
      expect(mock.methodCalls, isEmpty);
    });

    group('event streams', () {
      test('emitMotionChange broadcasts event', () async {
        final events = <Location>[];
        mock.motionChangeStream.listen(events.add);

        mock.emitMotionChange(MockLocationExtension.mock(isMoving: true));
        await Future.delayed(Duration.zero);

        expect(events.length, 1);
        expect(events.first.isMoving, isTrue);
      });

      test('emitActivityChange broadcasts event', () async {
        final events = <Activity>[];
        mock.activityStream.listen(events.add);

        mock.emitActivityChange(
          MockActivityExtension.mock(type: ActivityType.walking),
        );
        await Future.delayed(Duration.zero);

        expect(events.length, 1);
        expect(events.first.type, ActivityType.walking);
      });

      test('emitEnabledChange broadcasts event', () async {
        final events = <bool>[];
        mock.enabledStream.listen(events.add);

        mock.emitEnabledChange(true);
        mock.emitEnabledChange(false);
        await Future.delayed(Duration.zero);

        expect(events, [true, false]);
      });
    });

    test('simulateLocationSequence emits locations over time', () async {
      final locations = <Location>[];
      mock.locationStream.listen(locations.add);

      final sequence = [
        MockLocationExtension.mock(latitude: 1),
        MockLocationExtension.mock(latitude: 2),
        MockLocationExtension.mock(latitude: 3),
      ];

      await mock.simulateLocationSequence(
        sequence,
        interval: const Duration(milliseconds: 10),
      );

      expect(locations.length, 3);
      expect(locations[0].coords.latitude, 1);
      expect(locations[2].coords.latitude, 3);
    });
  });

  group('MockLocationExtension', () {
    test('creates location with defaults', () {
      final location = MockLocationExtension.mock();
      expect(location.coords.latitude, 0);
      expect(location.coords.longitude, 0);
      expect(location.isMoving, isFalse);
    });

    test('creates location with custom values', () {
      final location = MockLocationExtension.mock(
        latitude: 40.7128,
        longitude: -74.006,
        speed: 15.5,
        activityType: ActivityType.inVehicle,
        isMoving: true,
      );

      expect(location.coords.latitude, 40.7128);
      expect(location.coords.longitude, -74.006);
      expect(location.coords.speed, 15.5);
      expect(location.activity?.type, ActivityType.inVehicle);
      expect(location.isMoving, isTrue);
    });
  });

  group('MockGeofenceExtension', () {
    test('creates geofence with defaults', () {
      final geofence = MockGeofenceExtension.mock();
      expect(geofence.radius, 100);
      expect(geofence.notifyOnEntry, isTrue);
      expect(geofence.notifyOnExit, isTrue);
    });

    test('creates geofence with custom values', () {
      final geofence = MockGeofenceExtension.mock(
        identifier: 'custom',
        latitude: 51.5,
        longitude: -0.1,
        radius: 200,
      );

      expect(geofence.identifier, 'custom');
      expect(geofence.latitude, 51.5);
      expect(geofence.radius, 200);
    });
  });
}
