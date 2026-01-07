/// Comprehensive tests for LocationService API.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import '../../helpers/helpers.dart';

void main() {
  group('LocationService', () {
    late MockLocus mockLocus;
    late LocationServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = LocationServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('stream', () {
      test('should emit location updates', () async {
        final locations = <Location>[];
        final sub = service.stream.listen(locations.add);

        final loc1 = LocationFactory().at(37.7749, -122.4194).build();
        final loc2 = LocationFactory().at(37.7750, -122.4195).moving().build();

        mockLocus.emitLocation(loc1);
        mockLocus.emitLocation(loc2);

        await Future.delayed(Duration.zero);

        expect(locations, hasLength(2));
        expect(locations.first, isLocationAt(37.7749, -122.4194));
        expect(locations.last.isMoving, isTrue);

        await sub.cancel();
      });
    });

    group('motionChanges', () {
      test('should emit only motion change events', () async {
        final changes = <Location>[];
        final sub = service.motionChanges.listen(changes.add);

        final stationaryLoc = LocationFactory().at(37.0, -122.0).stationary().build();
        final movingLoc = LocationFactory().at(37.1, -122.1).moving().build();

        mockLocus.emitMotionChange(stationaryLoc);
        mockLocus.emitMotionChange(movingLoc);

        await Future.delayed(Duration.zero);

        expect(changes, hasLength(2));
        expect(changes.first.isMoving, isFalse);
        expect(changes.last.isMoving, isTrue);

        await sub.cancel();
      });
    });

    group('heartbeats', () {
      test('should emit heartbeat locations', () async {
        final heartbeats = <Location>[];
        final sub = service.heartbeats.listen(heartbeats.add);

        final loc = LocationFactory()
            .at(37.0, -122.0)
            .stationary()
            .heartbeat()
            .build();

        mockLocus.emitHeartbeat(loc);

        await Future.delayed(Duration.zero);

        expect(heartbeats, hasLength(1));
        expect(heartbeats.first.isHeartbeat, isTrue);

        await sub.cancel();
      });
    });

    group('getCurrentPosition', () {
      test('should return current position with default params', () async {
        final location = LocationFactory().at(37.4219, -122.084).build();
        mockLocus.emitLocation(location);

        final result = await service.getCurrentPosition();

        expect(result, isNotNull);
      });

      test('should accept custom samples parameter', () async {
        final location = LocationFactory().at(40.7580, -73.9855).withAccuracy(5.0).build();
        mockLocus.emitLocation(location);

        final result = await service.getCurrentPosition(samples: 3);

        expect(result.coords.accuracy, lessThan(20));
        expect(mockLocus.methodCalls, contains('getCurrentPosition'));
      });

      test('should accept timeout parameter', () async {
        final location = LocationFactory().at(51.5007, -0.1246).build();
        mockLocus.emitLocation(location);

        final result = await service.getCurrentPosition(timeout: 5000);

        expect(result, isNotNull);
      });

      test('should allow persist flag', () async {
        final location = LocationFactory().at(37.0, -122.0).build();
        mockLocus.emitLocation(location);

        await service.getCurrentPosition(persist: true);

        expect(mockLocus.methodCalls, contains('getCurrentPosition'));
      });

      test('should accept extras metadata', () async {
        final location = LocationFactory().at(37.0, -122.0).build();
        mockLocus.emitLocation(location);

        await service.getCurrentPosition(
          extras: {'source': 'manual', 'userId': '123'},
        );

        expect(mockLocus.methodCalls, contains('getCurrentPosition'));
      });
    });

    group('getLocations', () {
      test('should return stored locations', () async {
        final loc1 = LocationFactory().at(37.0, -122.0).build();
        final loc2 = LocationFactory().at(37.1, -122.1).build();

        mockLocus.emitLocation(loc1);
        mockLocus.emitLocation(loc2);

        final result = await service.getLocations();

        expect(result, hasLength(2));
      });

      test('should respect limit parameter', () async {
        for (var i = 0; i < 10; i++) {
          mockLocus.emitLocation(
            LocationFactory().at(37.0 + i * 0.1, -122.0).build(),
          );
        }

        final result = await service.getLocations(limit: 5);

        expect(result.length, lessThanOrEqualTo(5));
      });
    });

    group('query', () {
      test('should filter by date range', () async {
        final now = DateTime.now();
        final hourAgo = now.subtract(const Duration(hours: 1));

        final loc1 = LocationFactory()
            .at(37.0, -122.0)
            .withTimestamp(hourAgo)
            .build();
        final loc2 = LocationFactory()
            .at(37.1, -122.1)
            .withTimestamp(now)
            .build();

        mockLocus.emitLocation(loc1);
        mockLocus.emitLocation(loc2);

        final query = LocationQuery(
          from: hourAgo,
          to: now,
        );

        final result = await service.query(query);

        expect(result, isNotEmpty);
      });

      test('should filter by accuracy', () async {
        final loc1 = LocationFactory().at(37.0, -122.0).withAccuracy(5.0).build();
        final loc2 = LocationFactory().at(37.1, -122.1).withAccuracy(25.0).build();

        mockLocus.emitLocation(loc1);
        mockLocus.emitLocation(loc2);

        const query = LocationQuery(minAccuracy: 10);

        await service.query(query);

        expect(mockLocus.methodCalls, contains('getLocations'));
      });

      test('should support pagination with limit', () async {
        for (var i = 0; i < 20; i++) {
          mockLocus.emitLocation(
            LocationFactory().at(37.0 + i * 0.01, -122.0).build(),
          );
        }

        const query = LocationQuery(limit: 10);
        final result = await service.query(query);

        expect(result.length, lessThanOrEqualTo(10));
      });
    });

    group('getSummary', () {
      test('should return location summary', () async {
        final loc1 = LocationFactory().at(37.0, -122.0).stationary().build();
        final loc2 = LocationFactory().at(37.1, -122.1).moving().withSpeed(5.0).build();

        mockLocus.emitLocation(loc1);
        mockLocus.emitLocation(loc2);

        final summary = await service.getSummary();

        expect(summary, isA<LocationSummary>());
      });

      test('should accept specific date', () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));

        final summary = await service.getSummary(date: yesterday);

        expect(summary, isA<LocationSummary>());
      });

      test('should accept custom query', () async {
        final query = LocationQuery(
          from: DateTime.now().subtract(const Duration(hours: 6)),
        );

        final summary = await service.getSummary(query: query);

        expect(summary, isA<LocationSummary>());
      });
    });

    group('changePace', () {
      test('should change to moving state', () async {
        final result = await service.changePace(true);

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('changePace'));
      });

      test('should change to stationary state', () async {
        final result = await service.changePace(false);

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('changePace'));
      });
    });

    group('odometer', () {
      test('should set odometer value', () async {
        final result = await service.setOdometer(1000.0);

        expect(result, 1000.0);
        expect(mockLocus.methodCalls, contains('setOdometer'));
      });

      test('should accept zero value', () async {
        final result = await service.setOdometer(0.0);

        expect(result, 0.0);
      });
    });

    group('destroyLocations', () {
      test('should clear all stored locations', () async {
        mockLocus.emitLocation(LocationFactory().at(37.0, -122.0).build());
        mockLocus.emitLocation(LocationFactory().at(37.1, -122.1).build());

        final result = await service.destroyLocations();

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('destroyLocations'));
      });
    });

    group('subscriptions', () {
      test('onLocation should receive updates', () async {
        Location? received;
        final sub = service.onLocation((location) {
          received = location;
        });

        final location = LocationFactory().at(37.0, -122.0).build();
        mockLocus.emitLocation(location);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received, isLocationAt(37.0, -122.0));

        await sub.cancel();
      });

      test('onMotionChange should receive motion events', () async {
        Location? received;
        final sub = service.onMotionChange((location) {
          received = location;
        });

        final location = LocationFactory().at(37.0, -122.0).moving().build();
        mockLocus.emitMotionChange(location);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received!.isMoving, isTrue);

        await sub.cancel();
      });

      test('onHeartbeat should receive heartbeat events', () async {
        Location? received;
        final sub = service.onHeartbeat((location) {
          received = location;
        });

        final location = LocationFactory()
            .at(37.0, -122.0)
            .heartbeat()
            .build();
        mockLocus.emitHeartbeat(location);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);

        await sub.cancel();
      });
    });
  });
}
