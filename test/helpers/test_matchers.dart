/// Custom test matchers for locus models.
///
/// Provides custom matchers for more expressive test assertions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

/// Matches a location with specific coordinates.
///
/// Example:
/// ```dart
/// expect(location, isLocationAt(37.7749, -122.4194));
/// ```
Matcher isLocationAt(double latitude, double longitude,
    {double tolerance = 0.0001}) {
  return _LocationMatcher(latitude, longitude, tolerance);
}

class _LocationMatcher extends Matcher {
  _LocationMatcher(this.expectedLat, this.expectedLng, this.tolerance);

  final double expectedLat;
  final double expectedLng;
  final double tolerance;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Location) return false;

    final latDiff = (item.coords.latitude - expectedLat).abs();
    final lngDiff = (item.coords.longitude - expectedLng).abs();

    return latDiff <= tolerance && lngDiff <= tolerance;
  }

  @override
  Description describe(Description description) {
    return description.add(
      'location at ($expectedLat, $expectedLng) ±$tolerance',
    );
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! Location) {
      return mismatchDescription.add('is not a Location');
    }
    return mismatchDescription.add(
      'is at (${item.coords.latitude}, ${item.coords.longitude})',
    );
  }
}

/// Matches a location that is moving.
///
/// Example:
/// ```dart
/// expect(location, isMoving);
/// ```
const Matcher isMoving = _IsMovingMatcher(true);

/// Matches a location that is stationary.
///
/// Example:
/// ```dart
/// expect(location, isStationary);
/// ```
const Matcher isStationary = _IsMovingMatcher(false);

class _IsMovingMatcher extends Matcher {
  const _IsMovingMatcher(this.expectedMoving);

  final bool expectedMoving;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Location) return false;
    return item.isMoving == expectedMoving;
  }

  @override
  Description describe(Description description) {
    return description
        .add(expectedMoving ? 'moving location' : 'stationary location');
  }
}

/// Matches a location with good accuracy (< 20m).
///
/// Example:
/// ```dart
/// expect(location, hasGoodAccuracy);
/// ```
const Matcher hasGoodAccuracy = _AccuracyMatcher(20);

class _AccuracyMatcher extends Matcher {
  const _AccuracyMatcher(this.maxAccuracy);

  final double maxAccuracy;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Location) return false;
    return item.coords.accuracy <= maxAccuracy;
  }

  @override
  Description describe(Description description) {
    return description.add('location with accuracy ≤ ${maxAccuracy}m');
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! Location) {
      return mismatchDescription.add('is not a Location');
    }
    return mismatchDescription.add(
      'has accuracy ${item.coords.accuracy}m',
    );
  }
}

/// Matches a geofence with a specific identifier.
///
/// Example:
/// ```dart
/// expect(geofence, hasIdentifier('home'));
/// ```
Matcher hasIdentifier(String identifier) {
  return _IdentifierMatcher(identifier);
}

class _IdentifierMatcher extends Matcher {
  _IdentifierMatcher(this.expectedId);

  final String expectedId;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is Geofence) {
      return item.identifier == expectedId;
    }
    if (item is PolygonGeofence) {
      return item.identifier == expectedId;
    }
    return false;
  }

  @override
  Description describe(Description description) {
    return description.add('has identifier "$expectedId"');
  }
}

/// Matches a location inside a geofence.
///
/// Example:
/// ```dart
/// expect(location, isInsideGeofence(homeGeofence));
/// ```
Matcher isInsideGeofence(Geofence geofence) {
  return _IsInsideGeofenceMatcher(geofence);
}

class _IsInsideGeofenceMatcher extends Matcher {
  _IsInsideGeofenceMatcher(this.geofence);

  final Geofence geofence;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Location) return false;

    final distance = _calculateDistance(
      geofence.latitude,
      geofence.longitude,
      item.coords.latitude,
      item.coords.longitude,
    );

    return distance <= geofence.radius;
  }

  @override
  Description describe(Description description) {
    return description.add('location inside geofence "${geofence.identifier}"');
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = (lat2 - lat1) * 0.017453292519943295;
    final dLon = (lon2 - lon1) * 0.017453292519943295;

    final a = (dLat / 2) * (dLat / 2) +
        (lat1 * 0.017453292519943295).cos() *
            (lat2 * 0.017453292519943295).cos() *
            (dLon / 2) *
            (dLon / 2);

    final c = 2 * a.sqrt().atan2((1 - a).sqrt());
    return earthRadius * c;
  }
}

/// Matches a Config with specific accuracy.
///
/// Example:
/// ```dart
/// expect(config, hasAccuracy(DesiredAccuracy.high));
/// ```
Matcher hasAccuracy(DesiredAccuracy accuracy) {
  return _ConfigAccuracyMatcher(accuracy);
}

class _ConfigAccuracyMatcher extends Matcher {
  _ConfigAccuracyMatcher(this.expectedAccuracy);

  final DesiredAccuracy expectedAccuracy;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Config) return false;
    return item.desiredAccuracy == expectedAccuracy;
  }

  @override
  Description describe(Description description) {
    return description.add('config with accuracy $expectedAccuracy');
  }
}

extension on double {
  double cos() => this;
  double sqrt() => this;
  double atan2(double x) => this;
}
