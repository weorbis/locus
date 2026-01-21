/// Benchmark for location clustering algorithm performance.
///
/// Run with: dart test test/benchmark/location_clustering_benchmark.dart
// ignore_for_file: avoid_print

library;

import 'dart:math' as math;
import 'package:locus/src/features/location/models/location_history.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/shared/models/coords.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generates a list of stationary test locations clustered around random centers.
List<Location> generateClusteredLocations({
  required int count,
  int numClusters = 10,
  double clusterSpreadMeters = 50,
  int seed = 42,
}) {
  final random = math.Random(seed);
  final locations = <Location>[];
  final baseTime = DateTime(2024, 1, 15, 12, 0, 0);

  // Generate cluster centers (spread across a city-sized area)
  final clusterCenters = <({double lat, double lng})>[];
  const baseLat = 37.4219;
  const baseLng = -122.0840;
  const areaSpreadDegrees = 0.1; // ~10km spread

  for (var i = 0; i < numClusters; i++) {
    clusterCenters.add((
      lat: baseLat + (random.nextDouble() - 0.5) * areaSpreadDegrees,
      lng: baseLng + (random.nextDouble() - 0.5) * areaSpreadDegrees,
    ));
  }

  // Convert cluster spread from meters to degrees (approximate)
  final clusterSpreadDegrees =
      clusterSpreadMeters / 111000; // ~111km per degree

  // Generate points around cluster centers
  for (var i = 0; i < count; i++) {
    final clusterIndex = random.nextInt(numClusters);
    final center = clusterCenters[clusterIndex];

    // Add some randomness around the cluster center
    final lat = center.lat + (random.nextDouble() - 0.5) * clusterSpreadDegrees;
    final lng = center.lng + (random.nextDouble() - 0.5) * clusterSpreadDegrees;

    locations.add(
      Location(
        uuid: 'bench-$i',
        coords: Coords(
          latitude: lat,
          longitude: lng,
          accuracy: 10.0,
        ),
        timestamp: baseTime.add(Duration(seconds: i * 30)),
        isMoving: false, // All stationary to test clustering
      ),
    );
  }

  return locations;
}

/// Generates uniformly spread locations (worst case for clustering).
///
/// Each point is spread far enough that it creates its own cluster,
/// stressing the O(N²) behavior of naive clustering.
List<Location> generateUniformlySpreadLocations({
  required int count,
  int seed = 42,
}) {
  final locations = <Location>[];
  final baseTime = DateTime(2024, 1, 15, 12, 0, 0);

  // Spread points at least 200m apart (> clusterRadiusMeters which is 100m)
  // 200m in degrees ≈ 0.0018
  const spacingDegrees = 0.002;
  final gridSize = math.sqrt(count).ceil();

  const baseLat = 37.0;
  const baseLng = -122.0;

  for (var i = 0; i < count; i++) {
    final row = i ~/ gridSize;
    final col = i % gridSize;

    locations.add(
      Location(
        uuid: 'uniform-$i',
        coords: Coords(
          latitude: baseLat + row * spacingDegrees,
          longitude: baseLng + col * spacingDegrees,
          accuracy: 10.0,
        ),
        timestamp: baseTime.add(Duration(seconds: i * 30)),
        isMoving: false,
      ),
    );
  }

  return locations;
}

/// Measures execution time in microseconds for a function.
int measureMicroseconds(void Function() fn,
    {int warmupRuns = 2, int runs = 5}) {
  // Warmup runs
  for (var i = 0; i < warmupRuns; i++) {
    fn();
  }

  // Measured runs
  final times = <int>[];
  for (var i = 0; i < runs; i++) {
    final stopwatch = Stopwatch()..start();
    fn();
    stopwatch.stop();
    times.add(stopwatch.elapsedMicroseconds);
  }

  // Return median
  times.sort();
  return times[times.length ~/ 2];
}

void main() {
  group('Location Clustering Benchmark', () {
    test('benchmark clustering performance at various scales', () {
      final sizes = [100, 500, 1000, 2500, 5000, 10000];
      final results = <({int size, int microseconds, double msPerPoint})>[];

      print('\n${'=' * 60}');
      print('Location Clustering Performance Benchmark');
      print('=' * 60);

      for (final size in sizes) {
        final locations = generateClusteredLocations(count: size);

        final timeUs = measureMicroseconds(() {
          LocationHistoryCalculator.calculateSummary(locations);
        });

        final msPerPoint = timeUs / 1000 / size;
        results.add((size: size, microseconds: timeUs, msPerPoint: msPerPoint));

        print('Size: ${size.toString().padLeft(5)} | '
            'Time: ${(timeUs / 1000).toStringAsFixed(2).padLeft(10)} ms | '
            'Per point: ${(msPerPoint * 1000).toStringAsFixed(3).padLeft(8)} μs');
      }

      print('=' * 60);

      // Calculate scaling factor (should be ~1 for O(N), ~size ratio for O(N²))
      if (results.length >= 2) {
        final first = results.first;
        final last = results.last;
        final sizeRatio = last.size / first.size;
        final timeRatio = last.microseconds / first.microseconds;
        final scalingExponent = math.log(timeRatio) / math.log(sizeRatio);

        print('Scaling analysis:');
        print('  Size ratio: ${sizeRatio.toStringAsFixed(1)}x');
        print('  Time ratio: ${timeRatio.toStringAsFixed(1)}x');
        print(
            '  Estimated complexity exponent: ${scalingExponent.toStringAsFixed(2)}');
        print('  (1.0 = O(N), 2.0 = O(N²))');
        print('=' * 60);
      }

      // This test always passes - it's for measurement only
      expect(results, isNotEmpty);
    });

    test('benchmark worst-case clustering (uniformly spread points)', () {
      // This test creates points that are uniformly spread so each creates its own cluster
      // This stresses the O(N²) behavior of the current algorithm
      final sizes = [100, 250, 500, 1000, 2000, 3000];
      final results = <({int size, int microseconds, double msPerPoint})>[];

      print('\n${'=' * 60}');
      print('WORST-CASE: Uniformly Spread Points (Many Clusters)');
      print('=' * 60);

      for (final size in sizes) {
        final locations = generateUniformlySpreadLocations(count: size);

        final timeUs = measureMicroseconds(() {
          LocationHistoryCalculator.calculateSummary(locations);
        }, warmupRuns: 1, runs: 3);

        final msPerPoint = timeUs / 1000 / size;
        results.add((size: size, microseconds: timeUs, msPerPoint: msPerPoint));

        print('Size: ${size.toString().padLeft(5)} | '
            'Time: ${(timeUs / 1000).toStringAsFixed(2).padLeft(10)} ms | '
            'Per point: ${(msPerPoint * 1000).toStringAsFixed(3).padLeft(8)} μs');
      }

      print('=' * 60);

      // Calculate scaling factor (should be ~2 for O(N²))
      if (results.length >= 2) {
        final first = results.first;
        final last = results.last;
        final sizeRatio = last.size / first.size;
        final timeRatio = last.microseconds / first.microseconds;
        final scalingExponent = math.log(timeRatio) / math.log(sizeRatio);

        print('Scaling analysis (worst case):');
        print('  Size ratio: ${sizeRatio.toStringAsFixed(1)}x');
        print('  Time ratio: ${timeRatio.toStringAsFixed(1)}x');
        print(
            '  Estimated complexity exponent: ${scalingExponent.toStringAsFixed(2)}');
        print('  (1.0 = O(N), 2.0 = O(N²))');
        print('=' * 60);
      }

      expect(results, isNotEmpty);
    });

    test('validate clustering correctness with known data', () {
      print('\n${'=' * 60}');
      print('Clustering Correctness Validation');
      print('=' * 60);

      // Create locations with 3 well-separated clusters
      final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
      final locations = <Location>[];

      // Cluster 1: 5 points around (37.42, -122.08)
      for (var i = 0; i < 5; i++) {
        locations.add(Location(
          uuid: 'c1-$i',
          coords: Coords(
            latitude: 37.4200 + i * 0.00001,
            longitude: -122.0800 + i * 0.00001,
            accuracy: 10.0,
          ),
          timestamp: baseTime.add(Duration(minutes: i)),
          isMoving: false,
        ));
      }

      // Cluster 2: 3 points around (37.50, -122.20)
      for (var i = 0; i < 3; i++) {
        locations.add(Location(
          uuid: 'c2-$i',
          coords: Coords(
            latitude: 37.5000 + i * 0.00001,
            longitude: -122.2000 + i * 0.00001,
            accuracy: 10.0,
          ),
          timestamp: baseTime.add(Duration(minutes: 10 + i)),
          isMoving: false,
        ));
      }

      // Cluster 3: 4 points around (37.60, -122.30)
      for (var i = 0; i < 4; i++) {
        locations.add(Location(
          uuid: 'c3-$i',
          coords: Coords(
            latitude: 37.6000 + i * 0.00001,
            longitude: -122.3000 + i * 0.00001,
            accuracy: 10.0,
          ),
          timestamp: baseTime.add(Duration(minutes: 20 + i)),
          isMoving: false,
        ));
      }

      final summary = LocationHistoryCalculator.calculateSummary(locations);

      print(
          'Input: ${locations.length} locations in 3 clusters (5, 3, 4 points)');
      print(
          'Output: ${summary.frequentLocations.length} frequent locations found');
      for (final freq in summary.frequentLocations) {
        print('  - Visits: ${freq.visitCount}, '
            'Center: (${freq.center.latitude.toStringAsFixed(4)}, '
            '${freq.center.longitude.toStringAsFixed(4)})');
      }
      print('=' * 60);

      // Validate we found the expected clusters (all have >= 2 visits)
      expect(summary.frequentLocations.length, greaterThanOrEqualTo(2));
      expect(
        summary.frequentLocations.first.visitCount,
        greaterThanOrEqualTo(3),
      );
    });
  });
}
