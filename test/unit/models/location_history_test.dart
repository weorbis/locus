import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/location/models/location_history.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/shared/models/coords.dart';

void main() {
  group('LocationQuery', () {
    late List<Location> testLocations;

    setUp(() {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      testLocations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          accuracy: 5.0,
          timestamp: baseTime,
        ),
        _createLocation(
          latitude: 37.4220,
          longitude: -122.0841,
          accuracy: 10.0,
          timestamp: baseTime.add(const Duration(minutes: 5)),
        ),
        _createLocation(
          latitude: 37.4221,
          longitude: -122.0842,
          accuracy: 50.0,
          timestamp: baseTime.add(const Duration(minutes: 10)),
        ),
        _createLocation(
          latitude: 37.4222,
          longitude: -122.0843,
          accuracy: 8.0,
          timestamp: baseTime.add(const Duration(minutes: 15)),
        ),
        _createLocation(
          latitude: 40.7128,
          longitude: -74.0060,
          accuracy: 5.0,
          timestamp: baseTime.add(const Duration(minutes: 20)),
        ),
      ];
    });

    test('should return all locations when no filters applied', () {
      final query = LocationQuery();
      final result = query.apply(testLocations);
      expect(result.length, 5);
    });

    test('should filter by from date', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final query = LocationQuery(
        from: baseTime.add(const Duration(minutes: 10)),
      );
      final result = query.apply(testLocations);
      expect(result.length, 3);
    });

    test('should filter by to date', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final query = LocationQuery(
        to: baseTime.add(const Duration(minutes: 10)),
      );
      final result = query.apply(testLocations);
      expect(result.length, 3);
    });

    test('should filter by date range', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final query = LocationQuery(
        from: baseTime.add(const Duration(minutes: 5)),
        to: baseTime.add(const Duration(minutes: 15)),
      );
      final result = query.apply(testLocations);
      expect(result.length, 3);
    });

    test('should filter by minimum accuracy', () {
      final query = LocationQuery(minAccuracy: 10);
      final result = query.apply(testLocations);
      // Locations with accuracy <= 10
      expect(result.length, 4);
    });

    test('should filter by maximum accuracy', () {
      final query = LocationQuery(maxAccuracy: 10);
      final result = query.apply(testLocations);
      // Locations with accuracy >= 10
      expect(result.length, 2);
    });

    test('should filter by accuracy range', () {
      // minAccuracy=8 means accuracy <= 8, maxAccuracy=10 means accuracy >= 10
      // So looking for 8 <= accuracy <= 10, which should be accuracy=8 and accuracy=10
      // But the logic is minAccuracy filters accuracy > minAccuracy (excludes)
      // and maxAccuracy filters accuracy < maxAccuracy (excludes)
      // So if minAccuracy=10, it keeps accuracy <= 10
      // If maxAccuracy=8, it keeps accuracy >= 8
      // Combined: minAccuracy=50, maxAccuracy=10 keeps 10 <= accuracy <= 50
      final query = LocationQuery(minAccuracy: 50, maxAccuracy: 10);
      final result = query.apply(testLocations);
      // Locations with 10 <= accuracy <= 50 are: accuracy=10, accuracy=50
      expect(result.length, 2);
    });

    test('should filter by bounding box', () {
      final query = LocationQuery(
        bounds: LocationBounds(
          southwest: Coords(
            latitude: 37.4,
            longitude: -122.1,
            accuracy: 0,
          ),
          northeast: Coords(
            latitude: 37.5,
            longitude: -122.0,
            accuracy: 0,
          ),
        ),
      );
      final result = query.apply(testLocations);
      // Only SF area locations (first 4)
      expect(result.length, 4);
    });

    test('should respect limit', () {
      final query = LocationQuery(limit: 2);
      final result = query.apply(testLocations);
      expect(result.length, 2);
    });

    test('should respect offset', () {
      final query = LocationQuery(offset: 2);
      final result = query.apply(testLocations);
      expect(result.length, 3);
    });

    test('should respect limit and offset together', () {
      final query = LocationQuery(
        limit: 2,
        offset: 1,
        sortOrder: LocationSortOrder.oldestFirst,
      );
      final result = query.apply(testLocations);
      expect(result.length, 2);
      expect(result.first.coords.latitude, 37.4220);
    });

    test('should combine multiple filters', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final query = LocationQuery(
        from: baseTime,
        to: baseTime.add(const Duration(minutes: 15)),
        minAccuracy: 10,
        limit: 2,
      );
      final result = query.apply(testLocations);
      expect(result.length, 2);
    });

    test('should create query for last hours', () {
      final query = LocationQuery.lastHours(2);
      expect(query.from, isNotNull);
      expect(query.to, isNotNull);
    });

    test('should create query for today', () {
      final query = LocationQuery.today();
      expect(query.from, isNotNull);
      expect(query.to, isNotNull);
    });
  });

  group('LocationBounds', () {
    test('should correctly identify point inside bounds', () {
      final bbox = LocationBounds(
        southwest: Coords(latitude: 37.4, longitude: -122.1, accuracy: 0),
        northeast: Coords(latitude: 37.5, longitude: -122.0, accuracy: 0),
      );
      final point = Coords(latitude: 37.45, longitude: -122.05, accuracy: 0);
      expect(bbox.contains(point), true);
    });

    test('should correctly identify point outside bounds', () {
      final bbox = LocationBounds(
        southwest: Coords(latitude: 37.4, longitude: -122.1, accuracy: 0),
        northeast: Coords(latitude: 37.5, longitude: -122.0, accuracy: 0),
      );
      final point = Coords(latitude: 40.0, longitude: -74.0, accuracy: 0);
      expect(bbox.contains(point), false);
    });

    test('should handle edge cases on boundary', () {
      final bbox = LocationBounds(
        southwest: Coords(latitude: 37.4, longitude: -122.1, accuracy: 0),
        northeast: Coords(latitude: 37.5, longitude: -122.0, accuracy: 0),
      );
      final onNorthEdge =
          Coords(latitude: 37.5, longitude: -122.05, accuracy: 0);
      final onSouthEdge =
          Coords(latitude: 37.4, longitude: -122.05, accuracy: 0);
      expect(bbox.contains(onNorthEdge), true);
      expect(bbox.contains(onSouthEdge), true);
    });
  });

  group('LocationHistoryCalculator', () {
    test('should return empty summary for empty locations', () {
      final summary = LocationHistoryCalculator.calculateSummary([]);
      expect(summary.locationCount, 0);
      expect(summary.totalDistanceMeters, 0);
      expect(summary.movingDuration, Duration.zero);
      expect(summary.stationaryDuration, Duration.zero);
    });

    test('should calculate total distance between locations', () {
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: DateTime(2024, 1, 15, 12, 0, 0),
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: DateTime(2024, 1, 15, 12, 5, 0),
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.locationCount, 2);
      // Approximately 140 meters between these points
      expect(summary.totalDistanceMeters, greaterThan(100));
      expect(summary.totalDistanceMeters, lessThan(200));
    });

    test('should calculate moving vs stationary duration', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      // The implementation classifies a segment as moving if EITHER endpoint is moving
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: baseTime,
          isMoving: true,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 5)),
          isMoving: true,
        ),
        // Segment from here (moving=true) to next (moving=false) is still counted as moving
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 10)),
          isMoving: false,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 15)),
          isMoving: false,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      // Segment 1-2: both moving = 5 min moving
      // Segment 2-3: prev moving = 5 min moving
      // Segment 3-4: both stationary = 5 min stationary
      expect(summary.movingDuration.inMinutes, 10);
      expect(summary.stationaryDuration.inMinutes, 5);
    });

    test('should calculate average speed', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: baseTime,
          speed: 5.0,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 5)),
          speed: 10.0,
        ),
        _createLocation(
          latitude: 37.4239,
          longitude: -122.0860,
          timestamp: baseTime.add(const Duration(minutes: 10)),
          speed: 15.0,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.averageSpeedMps, 10.0);
    });

    test('should exclude zero speeds from average', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: baseTime,
          speed: 0.0,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 5)),
          speed: 10.0,
        ),
        _createLocation(
          latitude: 37.4239,
          longitude: -122.0860,
          timestamp: baseTime.add(const Duration(minutes: 10)),
          speed: 20.0,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.averageSpeedMps, 15.0);
    });

    test('should calculate max speed', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: baseTime,
          speed: 5.0,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: baseTime.add(const Duration(minutes: 5)),
          speed: 25.0,
        ),
        _createLocation(
          latitude: 37.4239,
          longitude: -122.0860,
          timestamp: baseTime.add(const Duration(minutes: 10)),
          speed: 10.0,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.maxSpeedMps, 25.0);
    });

    test('should identify frequent locations', () {
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      // Create locations clustered around two points - must be stationary
      final locations = [
        // Cluster 1: Home
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: baseTime,
          isMoving: false,
        ),
        _createLocation(
          latitude: 37.4220,
          longitude: -122.0841,
          timestamp: baseTime.add(const Duration(minutes: 5)),
          isMoving: false,
        ),
        _createLocation(
          latitude: 37.4218,
          longitude: -122.0839,
          timestamp: baseTime.add(const Duration(minutes: 10)),
          isMoving: false,
        ),
        // Cluster 2: Work
        _createLocation(
          latitude: 37.5000,
          longitude: -122.2000,
          timestamp: baseTime.add(const Duration(minutes: 30)),
          isMoving: false,
        ),
        _createLocation(
          latitude: 37.5001,
          longitude: -122.2001,
          timestamp: baseTime.add(const Duration(minutes: 35)),
          isMoving: false,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.frequentLocations, isNotEmpty);
    });

    test('should include time range in summary', () {
      final startTime = DateTime(2024, 1, 15, 12, 0, 0);
      final endTime = DateTime(2024, 1, 15, 14, 0, 0);
      final locations = [
        _createLocation(
          latitude: 37.4219,
          longitude: -122.0840,
          timestamp: startTime,
        ),
        _createLocation(
          latitude: 37.4229,
          longitude: -122.0850,
          timestamp: endTime,
        ),
      ];
      final summary = LocationHistoryCalculator.calculateSummary(locations);
      expect(summary.periodStart, startTime);
      expect(summary.periodEnd, endTime);
    });
  });

  group('FrequentLocation', () {
    test('should serialize to map correctly', () {
      final freq = FrequentLocation(
        center: Coords(
          latitude: 37.4219,
          longitude: -122.0840,
          accuracy: 0,
        ),
        visitCount: 5,
        totalDuration: const Duration(hours: 2),
        name: 'Home',
      );
      final map = freq.toMap();
      expect(map['center']['latitude'], 37.4219);
      expect(map['visitCount'], 5);
      expect(map['totalDurationSeconds'], 7200);
      expect(map['name'], 'Home');
    });
  });

  group('LocationSummary', () {
    test('should serialize to map correctly', () {
      final summary = LocationSummary(
        locationCount: 100,
        totalDistanceMeters: 5000.0,
        movingDuration: const Duration(hours: 1),
        stationaryDuration: const Duration(hours: 2),
        averageSpeedMps: 5.5,
        maxSpeedMps: 15.0,
        frequentLocations: [],
        periodStart: DateTime(2024, 1, 15, 12, 0),
        periodEnd: DateTime(2024, 1, 15, 15, 0),
      );
      final map = summary.toMap();
      expect(map['locationCount'], 100);
      expect(map['totalDistanceMeters'], 5000.0);
      expect(map['movingDurationSeconds'], 3600);
      expect(map['stationaryDurationSeconds'], 7200);
      expect(map['averageSpeedMps'], 5.5);
      expect(map['maxSpeedMps'], 15.0);
    });

    test('should calculate derived properties correctly', () {
      final summary = LocationSummary(
        locationCount: 100,
        totalDistanceMeters: 5000.0,
        movingDuration: const Duration(hours: 1),
        stationaryDuration: const Duration(hours: 2),
      );
      expect(summary.totalDuration.inHours, 3);
      expect(summary.totalDistanceKm, 5.0);
      expect(summary.movingPercent, closeTo(33.33, 0.1));
    });
  });
}

Location _createLocation({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double accuracy = 10.0,
  double speed = 0.0,
  bool isMoving = false,
}) {
  return Location(
    uuid: 'test-${timestamp.millisecondsSinceEpoch}',
    coords: Coords(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
    ),
    timestamp: timestamp,
    isMoving: isMoving,
  );
}
