library;

import 'dart:async';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/utils/location_utils.dart';

/// Configuration for detecting anomalous location jumps.
class LocationAnomalyConfig {
  /// Maximum plausible speed in km/h before an anomaly is flagged.
  final double maxSpeedKph;

  /// Ignore locations with accuracy worse than this threshold (meters).
  final double maxAccuracyMeters;

  /// Minimum distance (meters) before evaluating anomalies.
  final double minDistanceMeters;

  /// Minimum time between samples before evaluating anomalies.
  final Duration minTimeDelta;

  const LocationAnomalyConfig({
    this.maxSpeedKph = 200,
    this.maxAccuracyMeters = 100,
    this.minDistanceMeters = 200,
    this.minTimeDelta = const Duration(seconds: 5),
  });
}

/// Represents a detected anomalous movement between two locations.
class LocationAnomaly {
  final Location previous;
  final Location current;
  final double distanceMeters;
  final double speedKph;

  const LocationAnomaly({
    required this.previous,
    required this.current,
    required this.distanceMeters,
    required this.speedKph,
  });
}

/// Detects anomalous location jumps in a [Location] stream.
class LocationAnomalyDetector {
  const LocationAnomalyDetector._();

  /// Creates a stream of anomalies from a location stream.
  static Stream<LocationAnomaly> watch(
    Stream<Location> source, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  }) {
    Location? previous;

    return source.asyncExpand((location) async* {
      final current = location;
      if (previous == null) {
        // Only set initial reference if accuracy is acceptable
        if (_hasAcceptableAccuracy(current, config)) {
          previous = current;
        }
        return;
      }

      final prev = previous!;

      // Check accuracy BEFORE potentially updating reference
      final prevAccuracyOk = _hasAcceptableAccuracy(prev, config);
      final currentAccuracyOk = _hasAcceptableAccuracy(current, config);

      if (!prevAccuracyOk || !currentAccuracyOk) {
        // Only update reference if current has good accuracy
        // This prevents reference drift from poor readings
        if (currentAccuracyOk) {
          previous = current;
        }
        return;
      }

      final timeDelta = current.timestamp.difference(prev.timestamp);
      if (timeDelta <= Duration.zero || timeDelta < config.minTimeDelta) {
        // Update reference for valid time progression
        previous = current;
        return;
      }

      final distance =
          LocationUtils.calculateDistance(prev.coords, current.coords);
      if (distance < config.minDistanceMeters) {
        // Update reference - valid location but not enough distance
        previous = current;
        return;
      }

      final speedKph = LocationUtils.calculateSpeedKph(distance, timeDelta);
      if (speedKph >= config.maxSpeedKph) {
        yield LocationAnomaly(
          previous: prev,
          current: current,
          distanceMeters: distance,
          speedKph: speedKph,
        );
        // After anomaly, update reference to current
        previous = current;
      } else {
        // Normal movement - update reference
        previous = current;
      }
    });
  }

  static bool _hasAcceptableAccuracy(
    Location location,
    LocationAnomalyConfig config,
  ) {
    return location.coords.accuracy <= config.maxAccuracyMeters;
  }
}
