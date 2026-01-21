/// Location history query API for retrieving and analyzing stored locations.
///
/// Provides filtering, pagination, and aggregation capabilities for
/// historical location data stored by the SDK.
library;

import 'dart:math' as math;
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/shared/models/coords.dart';
import 'package:locus/src/shared/models/json_map.dart';

/// Query parameters for filtering location history.
///
/// Example:
/// ```dart
/// final query = LocationQuery(
///   from: DateTime.now().subtract(Duration(hours: 24)),
///   to: DateTime.now(),
///   minAccuracy: 50.0,
///   limit: 100,
/// );
/// final locations = await Locus.location.queryLocations(query);
/// ```
class LocationQuery {
  const LocationQuery({
    this.from,
    this.to,
    this.minAccuracy,
    this.maxAccuracy,
    this.isMoving,
    this.bounds,
    this.limit,
    this.offset = 0,
    this.sortOrder = LocationSortOrder.newestFirst,
  });

  /// Creates a query for the last N hours.
  factory LocationQuery.lastHours(int hours, {int? limit}) {
    return LocationQuery(
      from: DateTime.now().subtract(Duration(hours: hours)),
      to: DateTime.now(),
      limit: limit,
    );
  }

  /// Creates a query for today.
  factory LocationQuery.today({int? limit}) {
    final now = DateTime.now();
    return LocationQuery(
      from: DateTime(now.year, now.month, now.day),
      to: now,
      limit: limit,
    );
  }

  /// Start of the time range (inclusive).
  final DateTime? from;

  /// End of the time range (inclusive).
  final DateTime? to;

  /// Minimum accuracy in meters (filters out less accurate locations).
  final double? minAccuracy;

  /// Maximum accuracy in meters (filters out more accurate locations).
  final double? maxAccuracy;

  /// Only include locations where user was moving.
  final bool? isMoving;

  /// Bounding box for spatial filtering.
  final LocationBounds? bounds;

  /// Maximum number of results to return.
  final int? limit;

  /// Offset for pagination.
  final int offset;

  /// Sort order for results.
  final LocationSortOrder sortOrder;

  /// Filters a list of locations according to this query.
  List<Location> apply(List<Location> locations) {
    final filtered = locations.where((loc) {
      // Time range filter
      if (from != null && loc.timestamp.isBefore(from!)) return false;
      if (to != null && loc.timestamp.isAfter(to!)) return false;

      // Accuracy filter
      final accuracy = loc.coords.accuracy;
      if (minAccuracy != null && accuracy > minAccuracy!) {
        return false;
      }
      if (maxAccuracy != null && accuracy < maxAccuracy!) {
        return false;
      }

      // Motion filter
      if (isMoving != null && loc.isMoving != isMoving) return false;

      // Bounds filter
      if (bounds != null && !bounds!.contains(loc.coords)) return false;

      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (sortOrder) {
        case LocationSortOrder.newestFirst:
          return b.timestamp.compareTo(a.timestamp);
        case LocationSortOrder.oldestFirst:
          return a.timestamp.compareTo(b.timestamp);
      }
    });

    // Apply pagination (offset + limit) in a single sublist call to avoid
    // redundant allocations. Previously this used two separate sublist() calls.
    final length = filtered.length;
    if (offset >= length) {
      return const [];
    }

    // Calculate the final range for a single sublist operation
    final startIndex = offset;
    final endIndex = limit != null
        ? (startIndex + limit!).clamp(startIndex, length)
        : length;

    // Only create a sublist if we're actually trimming the list
    if (startIndex > 0 || endIndex < length) {
      return filtered.sublist(startIndex, endIndex);
    }

    return filtered;
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        if (from != null) 'from': from!.toIso8601String(),
        if (to != null) 'to': to!.toIso8601String(),
        if (minAccuracy != null) 'minAccuracy': minAccuracy,
        if (maxAccuracy != null) 'maxAccuracy': maxAccuracy,
        if (isMoving != null) 'isMoving': isMoving,
        if (bounds != null) 'bounds': bounds!.toMap(),
        if (limit != null) 'limit': limit,
        'offset': offset,
        'sortOrder': sortOrder.name,
      };
}

/// Sort order for location queries.
enum LocationSortOrder {
  /// Most recent locations first.
  newestFirst,

  /// Oldest locations first.
  oldestFirst,
}

/// Geographic bounding box for spatial filtering.
class LocationBounds {
  /// Creates a bounding box.
  const LocationBounds({
    required this.southwest,
    required this.northeast,
  });

  /// Creates from a map.
  factory LocationBounds.fromMap(JsonMap map) {
    return LocationBounds(
      southwest: Coords.fromMap(
        Map<String, dynamic>.from(map['southwest'] as Map),
      ),
      northeast: Coords.fromMap(
        Map<String, dynamic>.from(map['northeast'] as Map),
      ),
    );
  }

  /// Southwest corner (minimum lat/lng).
  final Coords southwest;

  /// Northeast corner (maximum lat/lng).
  final Coords northeast;

  /// Whether the given coordinates are within this bounding box.
  bool contains(Coords coords) {
    return coords.latitude >= southwest.latitude &&
        coords.latitude <= northeast.latitude &&
        coords.longitude >= southwest.longitude &&
        coords.longitude <= northeast.longitude;
  }

  /// Converts to a map.
  JsonMap toMap() => {
        'southwest': southwest.toMap(),
        'northeast': northeast.toMap(),
      };
}

/// Summary of location history for a time period.
///
/// Provides aggregated statistics about movement and activity.
///
/// Example:
/// ```dart
/// final summary = await Locus.getLocationSummary(date: DateTime.now());
/// print('Total distance: ${summary.totalDistanceMeters}m');
/// print('Moving time: ${summary.movingDuration}');
/// ```
class LocationSummary {
  /// Creates a location summary.
  const LocationSummary({
    required this.totalDistanceMeters,
    required this.movingDuration,
    required this.stationaryDuration,
    required this.locationCount,
    this.averageSpeedMps,
    this.maxSpeedMps,
    this.periodStart,
    this.periodEnd,
    this.frequentLocations = const [],
    this.averageAccuracyMeters,
  });

  /// Creates an empty summary.
  const LocationSummary.empty()
      : totalDistanceMeters = 0,
        movingDuration = Duration.zero,
        stationaryDuration = Duration.zero,
        locationCount = 0,
        averageSpeedMps = null,
        maxSpeedMps = null,
        periodStart = null,
        periodEnd = null,
        frequentLocations = const [],
        averageAccuracyMeters = null;

  /// Total distance traveled in meters.
  final double totalDistanceMeters;

  /// Duration spent moving.
  final Duration movingDuration;

  /// Duration spent stationary.
  final Duration stationaryDuration;

  /// Number of location points.
  final int locationCount;

  /// Average speed in meters per second (while moving).
  final double? averageSpeedMps;

  /// Maximum speed recorded in meters per second.
  final double? maxSpeedMps;

  /// Start of the summarized period.
  final DateTime? periodStart;

  /// End of the summarized period.
  final DateTime? periodEnd;

  /// Most frequently visited locations (clusters).
  final List<FrequentLocation> frequentLocations;

  /// Average accuracy of locations in meters.
  final double? averageAccuracyMeters;

  /// Total duration of the summarized period.
  Duration get totalDuration => movingDuration + stationaryDuration;

  /// Percentage of time spent moving.
  double get movingPercent {
    if (totalDuration.inSeconds == 0) return 0;
    return movingDuration.inSeconds / totalDuration.inSeconds * 100;
  }

  /// Total distance in kilometers.
  double get totalDistanceKm => totalDistanceMeters / 1000;

  /// Total distance in miles.
  double get totalDistanceMiles => totalDistanceMeters / 1609.344;

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'totalDistanceMeters': totalDistanceMeters,
        'movingDurationSeconds': movingDuration.inSeconds,
        'stationaryDurationSeconds': stationaryDuration.inSeconds,
        'locationCount': locationCount,
        if (averageSpeedMps != null) 'averageSpeedMps': averageSpeedMps,
        if (maxSpeedMps != null) 'maxSpeedMps': maxSpeedMps,
        if (periodStart != null) 'periodStart': periodStart!.toIso8601String(),
        if (periodEnd != null) 'periodEnd': periodEnd!.toIso8601String(),
        'frequentLocations': frequentLocations.map((l) => l.toMap()).toList(),
        if (averageAccuracyMeters != null)
          'averageAccuracyMeters': averageAccuracyMeters,
        'totalDistanceKm': totalDistanceKm,
        'movingPercent': movingPercent,
      };
}

/// A frequently visited location (cluster center).
class FrequentLocation {
  /// Creates a frequent location.
  const FrequentLocation({
    required this.center,
    required this.visitCount,
    required this.totalDuration,
    this.name,
  });

  /// Center coordinates of the cluster.
  final Coords center;

  /// Number of visits to this location.
  final int visitCount;

  /// Total time spent at this location.
  final Duration totalDuration;

  /// Optional name or identifier.
  final String? name;

  /// Converts to a map.
  JsonMap toMap() => {
        'center': center.toMap(),
        'visitCount': visitCount,
        'totalDurationSeconds': totalDuration.inSeconds,
        if (name != null) 'name': name,
      };
}

/// Calculator for location history statistics.
class LocationHistoryCalculator {
  /// Calculates a summary from a list of locations.
  static LocationSummary calculateSummary(List<Location> locations) {
    if (locations.isEmpty) {
      return const LocationSummary.empty();
    }

    // Sort by timestamp
    final sorted = List<Location>.from(locations)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    double totalDistance = 0;
    Duration movingDuration = Duration.zero;
    Duration stationaryDuration = Duration.zero;
    double totalSpeed = 0;
    int speedCount = 0;
    double? maxSpeed;
    double totalAccuracy = 0;
    int accuracyCount = 0;

    for (var i = 0; i < sorted.length; i++) {
      final loc = sorted[i];

      // Accumulate accuracy
      totalAccuracy += loc.coords.accuracy;
      accuracyCount++;

      // Process speed
      final speed = loc.coords.speed;
      if (speed != null && speed > 0) {
        totalSpeed += speed;
        speedCount++;
        if (maxSpeed == null || speed > maxSpeed) {
          maxSpeed = speed;
        }
      }

      // Calculate distance and duration to previous point
      if (i > 0) {
        final prevLoc = sorted[i - 1];
        final distance = _haversineDistance(
          prevLoc.coords.latitude,
          prevLoc.coords.longitude,
          loc.coords.latitude,
          loc.coords.longitude,
        );
        totalDistance += distance;

        final duration = loc.timestamp.difference(prevLoc.timestamp);

        // Classify as moving or stationary
        if (loc.isMoving == true || prevLoc.isMoving == true) {
          movingDuration += duration;
        } else {
          stationaryDuration += duration;
        }
      }
    }

    // Calculate frequent locations (simple clustering)
    final frequentLocations = _calculateFrequentLocations(sorted);

    return LocationSummary(
      totalDistanceMeters: totalDistance,
      movingDuration: movingDuration,
      stationaryDuration: stationaryDuration,
      locationCount: locations.length,
      averageSpeedMps: speedCount > 0 ? totalSpeed / speedCount : null,
      maxSpeedMps: maxSpeed,
      periodStart: sorted.first.timestamp,
      periodEnd: sorted.last.timestamp,
      frequentLocations: frequentLocations,
      averageAccuracyMeters:
          accuracyCount > 0 ? totalAccuracy / accuracyCount : null,
    );
  }

  /// Calculates the Haversine distance between two points in meters.
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Optimized clustering to find frequently visited locations.
  ///
  /// Uses a spatial grid (hash) to achieve O(N) complexity instead of O(N²).
  /// The grid divides space into cells of approximately clusterRadiusMeters,
  /// allowing O(1) lookup of nearby clusters instead of linear search.
  static List<FrequentLocation> _calculateFrequentLocations(
    List<Location> locations, {
    double clusterRadiusMeters = 100,
    int minVisits = 2,
    int maxClusters = 5,
  }) {
    if (locations.length < minVisits) return [];

    // Only consider stationary points for clustering
    final stationaryPoints =
        locations.where((l) => l.isMoving != true).toList();
    if (stationaryPoints.length < minVisits) return [];

    // Create spatial grid for O(1) cluster lookups
    final grid = _SpatialGrid(cellSizeMeters: clusterRadiusMeters);

    for (final loc in stationaryPoints) {
      // Find nearest existing cluster using spatial grid (O(1) amortized)
      final nearestCluster = grid.findNearestCluster(
        loc.coords.latitude,
        loc.coords.longitude,
        clusterRadiusMeters,
        _haversineDistance,
      );

      if (nearestCluster != null) {
        nearestCluster.addLocation(loc);
        // Update cluster position in grid after center moves
        grid.updateClusterPosition(nearestCluster);
      } else {
        final newCluster = _Cluster(loc);
        grid.addCluster(newCluster);
      }
    }

    // Collect all clusters from grid
    final clusters = grid.allClusters;

    // Filter and sort clusters
    final validClusters = clusters.where((c) => c.count >= minVisits).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return validClusters.take(maxClusters).map((c) {
      return FrequentLocation(
        center: Coords(
          latitude: c.centerLat,
          longitude: c.centerLng,
          accuracy: 0, // Cluster center, accuracy not applicable
        ),
        visitCount: c.count,
        totalDuration: c.totalDuration,
      );
    }).toList();
  }
}

/// Internal cluster representation for frequent location calculation.
class _Cluster {
  _Cluster(Location initial)
      : centerLat = initial.coords.latitude,
        centerLng = initial.coords.longitude {
    _lastTimestamp = initial.timestamp;
  }
  double centerLat;
  double centerLng;
  int count = 1;
  Duration totalDuration = Duration.zero;
  DateTime? _lastTimestamp;

  void addLocation(Location loc) {
    // Update center (running average)
    centerLat = (centerLat * count + loc.coords.latitude) / (count + 1);
    centerLng = (centerLng * count + loc.coords.longitude) / (count + 1);
    count++;

    // Accumulate duration
    if (_lastTimestamp != null) {
      totalDuration += loc.timestamp.difference(_lastTimestamp!);
    }
    _lastTimestamp = loc.timestamp;
  }
}

/// Spatial hash grid for O(1) cluster lookups.
///
/// Divides the world into a grid of cells sized to match the clustering radius.
/// Each cell contains a list of clusters whose centers fall within it.
/// When searching for nearby clusters, only the 9 adjacent cells need to be
/// checked (the cell containing the query point plus its 8 neighbors).
class _SpatialGrid {
  _SpatialGrid({required double cellSizeMeters})
      : _cellSizeDegrees = _metersToDegreesApprox(cellSizeMeters);

  /// The cell size in degrees (approximate).
  /// At equator: 1 degree ≈ 111km, so 100m ≈ 0.0009 degrees.
  final double _cellSizeDegrees;

  /// Map from cell key to list of clusters in that cell.
  final Map<String, List<_Cluster>> _cells = {};

  /// Track which cell each cluster is in for efficient updates.
  final Map<_Cluster, String> _clusterCells = {};

  /// Convert meters to degrees (approximate, good enough for grid sizing).
  static double _metersToDegreesApprox(double meters) {
    // ~111km per degree at equator, this is approximate but sufficient
    // for grid-based spatial hashing where precision isn't critical
    return meters / 111000;
  }

  /// Get the cell key for a coordinate.
  String _getCellKey(double lat, double lng) {
    final cellLat = (lat / _cellSizeDegrees).floor();
    final cellLng = (lng / _cellSizeDegrees).floor();
    return '$cellLat,$cellLng';
  }

  /// Add a cluster to the grid.
  void addCluster(_Cluster cluster) {
    final key = _getCellKey(cluster.centerLat, cluster.centerLng);
    _cells.putIfAbsent(key, () => []).add(cluster);
    _clusterCells[cluster] = key;
  }

  /// Update cluster position after its center has moved.
  /// Only moves the cluster to a new cell if needed.
  void updateClusterPosition(_Cluster cluster) {
    final oldKey = _clusterCells[cluster];
    final newKey = _getCellKey(cluster.centerLat, cluster.centerLng);

    if (oldKey != newKey) {
      // Remove from old cell
      if (oldKey != null) {
        _cells[oldKey]?.remove(cluster);
        if (_cells[oldKey]?.isEmpty ?? false) {
          _cells.remove(oldKey);
        }
      }
      // Add to new cell
      _cells.putIfAbsent(newKey, () => []).add(cluster);
      _clusterCells[cluster] = newKey;
    }
  }

  /// Find the nearest cluster within maxDistance meters.
  /// Returns null if no cluster is within range.
  ///
  /// Only checks the 9 cells around the query point (current + 8 neighbors)
  /// which gives O(1) amortized lookup instead of O(M) where M is total clusters.
  _Cluster? findNearestCluster(
    double lat,
    double lng,
    double maxDistance,
    double Function(double, double, double, double) distanceFunc,
  ) {
    _Cluster? nearest;
    double nearestDistance = double.infinity;

    // Check the 9 cells around the query point
    final centerCellLat = (lat / _cellSizeDegrees).floor();
    final centerCellLng = (lng / _cellSizeDegrees).floor();

    for (var dLat = -1; dLat <= 1; dLat++) {
      for (var dLng = -1; dLng <= 1; dLng++) {
        final key = '${centerCellLat + dLat},${centerCellLng + dLng}';
        final cellClusters = _cells[key];
        if (cellClusters == null) continue;

        for (final cluster in cellClusters) {
          final dist = distanceFunc(
            lat,
            lng,
            cluster.centerLat,
            cluster.centerLng,
          );
          if (dist < maxDistance && dist < nearestDistance) {
            nearest = cluster;
            nearestDistance = dist;
          }
        }
      }
    }

    return nearest;
  }

  /// Get all clusters from the grid.
  List<_Cluster> get allClusters {
    final all = <_Cluster>[];
    for (final cell in _cells.values) {
      all.addAll(cell);
    }
    return all;
  }
}
