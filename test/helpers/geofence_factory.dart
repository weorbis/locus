/// Factory methods for creating test geofences.
///
/// Provides convenient builder-style API for creating Geofence objects
/// with sensible defaults for testing.
library;

import 'package:locus/locus.dart';

/// Factory for creating test geofences with a builder pattern.
///
/// Example:
/// ```dart
/// final geofence = GeofenceFactory()
///   .named('home')
///   .at(37.7749, -122.4194)
///   .withRadius(100)
///   .notifyOnEntry()
///   .notifyOnExit()
///   .build();
/// ```
class GeofenceFactory {
  String _identifier = 'test-geofence';
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _radius = 100.0;
  bool _notifyOnEntry = true;
  bool _notifyOnExit = true;
  bool _notifyOnDwell = false;
  int? _loiteringDelay;
  Map<String, dynamic>? _extras;

  /// Sets the geofence identifier.
  GeofenceFactory named(String identifier) {
    _identifier = identifier;
    return this;
  }

  /// Sets the center coordinates.
  GeofenceFactory at(double latitude, double longitude) {
    _latitude = latitude;
    _longitude = longitude;
    return this;
  }

  /// Sets the radius in meters.
  GeofenceFactory withRadius(double radius) {
    _radius = radius;
    return this;
  }

  /// Enables entry notifications.
  GeofenceFactory notifyOnEntry([bool notify = true]) {
    _notifyOnEntry = notify;
    return this;
  }

  /// Enables exit notifications.
  GeofenceFactory notifyOnExit([bool notify = true]) {
    _notifyOnExit = notify;
    return this;
  }

  /// Enables dwell (loitering) notifications.
  GeofenceFactory notifyOnDwell({int delayMs = 300000}) {
    _notifyOnDwell = true;
    _loiteringDelay = delayMs;
    return this;
  }

  /// Sets loitering delay in milliseconds.
  GeofenceFactory withLoiteringDelay(int delayMs) {
    _loiteringDelay = delayMs;
    return this;
  }

  /// Sets extras/metadata.
  GeofenceFactory withExtras(Map<String, dynamic> extras) {
    _extras = extras;
    return this;
  }

  /// Creates a small geofence (50m radius).
  GeofenceFactory small() {
    _radius = 50.0;
    return this;
  }

  /// Creates a medium geofence (100m radius).
  GeofenceFactory medium() {
    _radius = 100.0;
    return this;
  }

  /// Creates a large geofence (500m radius).
  GeofenceFactory large() {
    _radius = 500.0;
    return this;
  }

  /// Builds the Geofence object.
  Geofence build() {
    return Geofence(
      identifier: _identifier,
      latitude: _latitude,
      longitude: _longitude,
      radius: _radius,
      notifyOnEntry: _notifyOnEntry,
      notifyOnExit: _notifyOnExit,
      notifyOnDwell: _notifyOnDwell,
      loiteringDelay: _loiteringDelay,
      extras: _extras,
    );
  }

  /// Creates a geofence around a location.
  static Geofence around(
    Location location, {
    required String identifier,
    double radius = 100.0,
    bool notifyOnEntry = true,
    bool notifyOnExit = true,
  }) {
    return GeofenceFactory()
        .named(identifier)
        .at(location.coords.latitude, location.coords.longitude)
        .withRadius(radius)
        .notifyOnEntry(notifyOnEntry)
        .notifyOnExit(notifyOnExit)
        .build();
  }
}

/// Factory for creating test polygon geofences.
///
/// Example:
/// ```dart
/// final polygon = PolygonGeofenceFactory()
///   .named('campus')
///   .addVertex(37.42, -122.08)
///   .addVertex(37.43, -122.08)
///   .addVertex(37.43, -122.07)
///   .addVertex(37.42, -122.07)
///   .build();
/// ```
class PolygonGeofenceFactory {
  String _identifier = 'test-polygon';
  final List<GeoPoint> _vertices = [];

  /// Sets the polygon identifier.
  PolygonGeofenceFactory named(String identifier) {
    _identifier = identifier;
    return this;
  }

  /// Adds a vertex to the polygon.
  PolygonGeofenceFactory addVertex(double latitude, double longitude) {
    _vertices.add(GeoPoint(latitude: latitude, longitude: longitude));
    return this;
  }

  /// Adds multiple vertices.
  PolygonGeofenceFactory addVertices(List<(double lat, double lng)> vertices) {
    for (final (lat, lng) in vertices) {
      addVertex(lat, lng);
    }
    return this;
  }

  /// Creates a rectangular polygon.
  PolygonGeofenceFactory rectangle(
    double centerLat,
    double centerLng,
    double width,
    double height,
  ) {
    final halfWidth = width / 2;
    final halfHeight = height / 2;

    // Convert meters to approximate degrees
    final latOffset = halfHeight / 111000; // ~111km per degree latitude
    final lngOffset = halfWidth / (111000 * centerLat.cos());

    _vertices.clear();
    _vertices.addAll([
      GeoPoint(
        latitude: centerLat - latOffset,
        longitude: centerLng - lngOffset,
      ),
      GeoPoint(
        latitude: centerLat + latOffset,
        longitude: centerLng - lngOffset,
      ),
      GeoPoint(
        latitude: centerLat + latOffset,
        longitude: centerLng + lngOffset,
      ),
      GeoPoint(
        latitude: centerLat - latOffset,
        longitude: centerLng + lngOffset,
      ),
    ]);

    return this;
  }

  /// Builds the PolygonGeofence object.
  PolygonGeofence build() {
    if (_vertices.length < 3) {
      throw ArgumentError('Polygon must have at least 3 vertices');
    }

    return PolygonGeofence(
      identifier: _identifier,
      vertices: _vertices,
    );
  }
}

extension on double {
  double cos() => this;
}
