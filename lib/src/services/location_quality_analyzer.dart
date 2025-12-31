library;

import 'dart:async';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/utils/location_utils.dart';

class LocationQualityConfig {
  final double maxAccuracyMeters;
  final double maxSpeedKph;
  final double jitterThresholdMeters;
  final int windowSize;

  const LocationQualityConfig({
    this.maxAccuracyMeters = 50,
    this.maxSpeedKph = 200,
    this.jitterThresholdMeters = 30,
    this.windowSize = 5,
  });
}

class LocationQualityAnalyzer {
  const LocationQualityAnalyzer._();

  static Stream<LocationQuality> analyze(
    Stream<Location> source, {
    LocationQualityConfig config = const LocationQualityConfig(),
  }) {
    final window = <Location>[];
    Location? previous;

    return source.asyncExpand((location) async* {
      window.add(location);
      if (window.length > config.windowSize) {
        window.removeAt(0);
      }

      final accuracyScore = _accuracyScore(location, config);
      final speedScore = _speedScore(previous, location, config);
      final jitterScore = _jitterScore(window, config);

      final overallScore =
          (accuracyScore * 0.4) + (speedScore * 0.4) + (jitterScore * 0.2);

      final isSpoofSuspected = _isSpoofSuspected(
        previous,
        location,
        accuracyScore,
        speedScore,
      );

      previous = location;

      yield LocationQuality(
        location: location,
        accuracyScore: accuracyScore,
        speedScore: speedScore,
        jitterScore: jitterScore,
        overallScore: overallScore,
        isSpoofSuspected: isSpoofSuspected,
      );
    });
  }

  static double _accuracyScore(
      Location location, LocationQualityConfig config) {
    final accuracy = location.coords.accuracy;
    if (accuracy <= 0) {
      return 0;
    }
    final ratio = accuracy / config.maxAccuracyMeters;
    return (1.0 - ratio).clamp(0.0, 1.0).toDouble();
  }

  static double _speedScore(
    Location? previous,
    Location current,
    LocationQualityConfig config,
  ) {
    if (previous == null) {
      return 1.0;
    }
    final distance =
        LocationUtils.calculateDistance(previous.coords, current.coords);
    final duration = current.timestamp.difference(previous.timestamp);
    final speedKph = LocationUtils.calculateSpeedKph(distance, duration);
    if (speedKph <= config.maxSpeedKph) {
      return 1.0 - (speedKph / config.maxSpeedKph).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  static double _jitterScore(
    List<Location> window,
    LocationQualityConfig config,
  ) {
    if (window.length < 2) {
      return 1.0;
    }
    double total = 0;
    for (var i = 1; i < window.length; i++) {
      total += LocationUtils.calculateDistance(
          window[i - 1].coords, window[i].coords);
    }
    final average = total / (window.length - 1);
    if (average <= config.jitterThresholdMeters) {
      return 1.0 - (average / config.jitterThresholdMeters).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  static bool _isSpoofSuspected(
    Location? previous,
    Location current,
    double accuracyScore,
    double speedScore,
  ) {
    if (previous == null) {
      return false;
    }
    final distance =
        LocationUtils.calculateDistance(previous.coords, current.coords);
    final duration = current.timestamp.difference(previous.timestamp);
    final speedKph = LocationUtils.calculateSpeedKph(distance, duration);

    final identicalCoords = distance < 1;
    final highAccuracy = accuracyScore > 0.8;
    final extremeSpeed = speedKph > 300;

    return (identicalCoords && highAccuracy) ||
        extremeSpeed ||
        speedScore < 0.1;
  }
}
