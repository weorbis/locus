library;

import 'dart:math' as math;

import 'package:locus/src/models/models.dart';

/// Shared utility functions for location calculations.
class LocationUtils {
  const LocationUtils._();

  /// Calculates the Haversine distance in meters between two coordinates.
  static double calculateDistance(Coords a, Coords b) {
    const earthRadius = 6371000.0; // meters

    final lat1 = toRadians(a.latitude);
    final lat2 = toRadians(b.latitude);
    final dLat = toRadians(b.latitude - a.latitude);
    final dLon = toRadians(b.longitude - a.longitude);

    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);

    final aVal =
        sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
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
