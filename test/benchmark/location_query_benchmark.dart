/// Benchmark for LocationQuery.apply() performance.
///
/// Tests the impact of reducing list allocations in location filtering.
library;

import 'package:locus/src/features/location/models/location_history.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/shared/models/coords.dart';

/// Generates test locations for benchmarking.
List<Location> generateTestLocations(int count) {
  final baseTime = DateTime(2024, 1, 15, 12, 0, 0);
  return List.generate(count, (i) {
    return Location(
      uuid: 'loc-$i',
      coords: Coords(
        latitude: 37.0 + (i % 1000) * 0.0001,
        longitude: -122.0 + (i % 1000) * 0.0001,
        accuracy: (i % 100).toDouble() + 1,
        speed: (i % 20).toDouble(),
      ),
      timestamp: baseTime.add(Duration(seconds: i * 10)),
      isMoving: i % 3 != 0,
    );
  });
}

/// Runs a single benchmark iteration and returns elapsed microseconds.
int runQueryBenchmark(
  LocationQuery query,
  List<Location> locations,
  int iterations,
) {
  // Warmup
  for (var i = 0; i < 5; i++) {
    query.apply(locations);
  }

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    query.apply(locations);
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

/// Benchmark results holder.
class BenchmarkResults {
  BenchmarkResults({
    required this.name,
    required this.locationCount,
    required this.iterations,
    required this.totalMicroseconds,
  });

  final String name;
  final int locationCount;
  final int iterations;
  final int totalMicroseconds;

  double get averageMicroseconds => totalMicroseconds / iterations;
  double get opsPerSecond => 1000000 / averageMicroseconds;

  @override
  String toString() {
    return '$name: ${averageMicroseconds.toStringAsFixed(2)}µs/op '
        '(${opsPerSecond.toStringAsFixed(0)} ops/sec) '
        '[$locationCount locations, $iterations iterations]';
  }
}

void main() {
  print('=== LocationQuery.apply() Benchmark ===\n');

  // Test different dataset sizes
  final sizes = [100, 1000, 5000, 10000];
  const iterations = 100;

  for (final size in sizes) {
    print('--- $size locations ---');
    final locations = generateTestLocations(size);

    // Test 1: No filters (worst case for allocation)
    final noFilterQuery = const LocationQuery();
    final noFilterTime =
        runQueryBenchmark(noFilterQuery, locations, iterations);
    print(BenchmarkResults(
      name: 'No filters',
      locationCount: size,
      iterations: iterations,
      totalMicroseconds: noFilterTime,
    ));

    // Test 2: With pagination (offset + limit) - triggers sublist copies
    final paginatedQuery = LocationQuery(
      offset: size ~/ 4,
      limit: size ~/ 2,
    );
    final paginatedTime =
        runQueryBenchmark(paginatedQuery, locations, iterations);
    print(BenchmarkResults(
      name: 'With pagination',
      locationCount: size,
      iterations: iterations,
      totalMicroseconds: paginatedTime,
    ));

    // Test 3: With accuracy filter + pagination
    final filteredQuery = LocationQuery(
      minAccuracy: 50,
      offset: 10,
      limit: 50,
    );
    final filteredTime =
        runQueryBenchmark(filteredQuery, locations, iterations);
    print(BenchmarkResults(
      name: 'Filtered + paginated',
      locationCount: size,
      iterations: iterations,
      totalMicroseconds: filteredTime,
    ));

    // Test 4: With time range filter
    final timeFilterQuery = LocationQuery(
      from: DateTime(2024, 1, 15, 12, 0, 0).add(Duration(seconds: size * 2)),
      to: DateTime(2024, 1, 15, 12, 0, 0).add(Duration(seconds: size * 8)),
    );
    final timeFilterTime =
        runQueryBenchmark(timeFilterQuery, locations, iterations);
    print(BenchmarkResults(
      name: 'Time range filter',
      locationCount: size,
      iterations: iterations,
      totalMicroseconds: timeFilterTime,
    ));

    print('');
  }

  print('Benchmark complete.\n');
}
