library;

import 'dart:math' as math;

import 'package:locus/src/models.dart';

/// Shared utility functions for location calculations.
class LocationUtils {
  const LocationUtils._();

  /// Calculates the Haversine distance in meters between two coordinates.
  static double calculateDistance(Coords a, Coords b) {
    return calculateDistanceFromCoords(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  /// Calculates the Haversine distance in meters between two coordinate pairs.
  static double calculateDistanceFromCoords(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters

    final lat1Rad = toRadians(lat1);
    final lat2Rad = toRadians(lat2);
    final dLat = toRadians(lat2 - lat1);
    final dLon = toRadians(lon2 - lon1);

    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);

    final aVal = sinLat * sinLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) * sinLon * sinLon;
    final c = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));

    return earthRadius * c;
  }

  /// Calculates speed in km/h given distance in meters and time duration.
  static double calculateSpeedKph(double distanceMeters, Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) {
      return 0;
    }
    return (distanceMeters / seconds) * 3.6;
  }

  /// Converts degrees to radians.
  static double toRadians(double degrees) => degrees * (math.pi / 180.0);
}
