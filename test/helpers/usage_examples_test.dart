/// Example usage of test infrastructure.
///
/// This file demonstrates how to use the test helpers, factories,
/// and fixtures provided by the locus test infrastructure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

// Import test infrastructure
import '../fixtures/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  group('Test Infrastructure Examples', () {
    group('Using LocationFactory', () {
      test('create a simple location', () {
        final location = LocationFactory()
            .at(37.7749, -122.4194)
            .withAccuracy(10)
            .moving()
            .withSpeed(5.0)
            .build();

        expect(location.coords.latitude, 37.7749);
        expect(location.coords.longitude, -122.4194);
        expect(location.isMoving, isTrue);
      });

      test('create a route', () {
        final route = LocationFactory.route([
          (37.7749, -122.4194),
          (37.7750, -122.4195),
          (37.7751, -122.4196),
        ]);

        expect(route.length, 3);
        expect(route.first, isLocationAt(37.7749, -122.4194));
      });

      test('create heartbeat sequence', () {
        final heartbeats = LocationFactory.stationarySequence(
          37.7749,
          -122.4194,
          count: 5,
          interval: const Duration(minutes: 1),
        );

        expect(heartbeats.length, 5);
        expect(heartbeats.every((l) => l.isHeartbeat == true), isTrue);
      });
    });

    group('Using GeofenceFactory', () {
      test('create a geofence', () {
        final geofence = GeofenceFactory()
            .named('home')
            .at(37.7749, -122.4194)
            .withRadius(100)
            .notifyOnEntry()
            .notifyOnExit()
            .build();

        expect(geofence.identifier, 'home');
        expect(geofence.radius, 100);
      });

      test('create geofence around location', () {
        final location = LocationFixtures.sanFrancisco();
        final geofence = GeofenceFactory.around(
          location,
          identifier: 'current-location',
          radius: 50,
        );

        expect(geofence.identifier, 'current-location');
        expect(location, isInsideGeofence(geofence));
      });
    });

    group('Using ConfigFactory', () {
      test('create high-accuracy config', () {
        final config = ConfigFactory()
            .highAccuracy()
            .enableHeadless()
            .withUrl('https://api.example.com/locations')
            .build();

        expect(config, hasAccuracy(DesiredAccuracy.high));
        expect(config.enableHeadless, isTrue);
      });

      test('create custom config', () {
        final config = ConfigFactory()
            .withAccuracy(DesiredAccuracy.medium)
            .withDistanceFilter(50)
            .batchSync(maxBatchSize: 50)
            .build();

        expect(config.distanceFilter, 50);
        expect(config.maxBatchSize, 50);
      });
    });

    group('Using Fixtures', () {
      test('use location fixtures', () {
        final sf = LocationFixtures.sanFrancisco();
        final ny = LocationFixtures.newYork();

        expect(sf.coords.latitude, closeTo(37.7749, 0.001));
        expect(ny.coords.latitude, closeTo(40.7580, 0.001));
      });

      test('use geofence fixtures', () {
        final home = GeofenceFixtures.home();
        final office = GeofenceFixtures.office();

        expect(home.identifier, 'home');
        expect(office.notifyOnDwell, isTrue);
      });

      test('use config fixtures', () {
        final highAccuracy = ConfigFixtures.highAccuracy();
        final lowPower = ConfigFixtures.lowPower();

        expect(highAccuracy, hasAccuracy(DesiredAccuracy.high));
        expect(lowPower, hasAccuracy(DesiredAccuracy.low));
      });
    });

    group('Using Async Helpers', () {
      late MockLocus mock;

      setUp(() {
        mock = MockLocus();
      });

      tearDown(() async {
        await mock.dispose();
      });

      test('wait for stream value', () async {
        // Emit location after a delay
        Future.delayed(const Duration(milliseconds: 100), () {
          mock.emitLocation(LocationFixtures.sanFrancisco());
        });

        final location = await waitForStreamValue(
          mock.locationStream,
          (loc) => loc.coords.latitude > 37.0,
        );

        expect(location.coords.latitude, greaterThan(37.0));
      });

      test('wait for multiple stream events', () async {
        // Emit multiple locations
        for (var i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 100), () {
            mock.emitLocation(LocationFixtures.sanFrancisco());
          });
        }

        final locations = await waitForStreamCount(
          mock.locationStream,
          count: 5,
        );

        expect(locations.length, 5);
      });

      test('poll until condition is met', () async {
        Future.delayed(const Duration(milliseconds: 500), () async {
          await mock.ready(const Config());
        });

        await pollUntil(() => mock.isReady);

        expect(mock.isReady, isTrue);
      });
    });

    group('Using Custom Matchers', () {
      test('location matchers', () {
        final location = LocationFactory()
            .at(37.7749, -122.4194)
            .moving()
            .withAccuracy(5)
            .build();

        expect(location, isLocationAt(37.7749, -122.4194));
        expect(location, isMoving);
        expect(location, hasGoodAccuracy);
      });

      test('geofence matchers', () {
        final geofence = GeofenceFixtures.home();
        final location = LocationFixtures.sanFrancisco();

        expect(geofence, hasIdentifier('home'));
        expect(location, isInsideGeofence(geofence));
      });
    });

    group('Using Base Test Classes', () {
      // Example of using serviceTest group helper
      serviceTestGroup<LocationServiceImpl>(
        'LocationServiceImpl',
        (getMock, getService) {
          test('returns empty summary when no locations', () async {
            final service = getService();
            final summary = await service.getSummary();

            expect(summary.locationCount, 0);
            expect(summary.totalDistanceMeters, 0);
          });

          test('calculates summary correctly', () async {
            final mock = getMock();
            final service = getService();

            // Emit locations
            mock.emitLocation(LocationFixtures.sanFrancisco(
              timestamp: DateTime(2026, 1, 1, 10, 0),
            ));
            mock.emitLocation(LocationFixtures.sanFrancisco(
              timestamp: DateTime(2026, 1, 1, 10, 5),
              isMoving: true,
            ));

            final summary = await service.getSummary(
              date: DateTime(2026, 1, 1),
            );

            expect(summary.locationCount, 2);
          });
        },
        createService: (mock) => LocationServiceImpl(() => mock),
      );
    });
  });
}
