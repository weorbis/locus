/// Factory methods for creating test locations.
///
/// Provides convenient builder-style API for creating Location objects
/// with sensible defaults for testing.
library;

import 'package:locus/locus.dart';

/// Factory for creating test locations with a builder pattern.
///
/// Example:
/// ```dart
/// final location = LocationFactory()
///   .at(37.7749, -122.4194)
///   .withAccuracy(10)
///   .moving()
///   .withSpeed(5.0)
///   .build();
/// ```
class LocationFactory {
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _accuracy = 10.0;
  double _speed = 0.0;
  double _heading = 0.0;
  double _altitude = 0.0;
  bool? _isMoving;
  bool? _isHeartbeat;
  String? _event;
  DateTime? _timestamp;
  Activity? _activity;
  Battery? _battery;
  Geofence? _geofence;
  double? _odometer;
  Map<String, dynamic>? _extras;
  bool _isMock = false;

  /// Sets the coordinates.
  LocationFactory at(double latitude, double longitude) {
    _latitude = latitude;
    _longitude = longitude;
    return this;
  }

  /// Sets accuracy in meters.
  LocationFactory withAccuracy(double accuracy) {
    _accuracy = accuracy;
    return this;
  }

  /// Sets speed in m/s.
  LocationFactory withSpeed(double speed) {
    _speed = speed;
    return this;
  }

  /// Sets heading in degrees.
  LocationFactory withHeading(double heading) {
    _heading = heading;
    return this;
  }

  /// Sets altitude in meters.
  LocationFactory withAltitude(double altitude) {
    _altitude = altitude;
    return this;
  }

  /// Marks location as moving.
  LocationFactory moving() {
    _isMoving = true;
    _activity ??= const Activity(
        type: ActivityType.walking,
        confidence: 80,
      );
    return this;
  }

  /// Marks location as stationary.
  LocationFactory stationary() {
    _isMoving = false;
    _speed = 0.0;
    _activity ??= const Activity(
        type: ActivityType.still,
        confidence: 100,
      );
    return this;
  }

  /// Marks as a heartbeat location.
  LocationFactory heartbeat() {
    _isHeartbeat = true;
    return this;
  }

  /// Sets the event name.
  LocationFactory withEvent(String event) {
    _event = event;
    return this;
  }

  /// Sets the timestamp.
  LocationFactory withTimestamp(DateTime timestamp) {
    _timestamp = timestamp;
    return this;
  }

  /// Sets activity.
  LocationFactory withActivity(Activity activity) {
    _activity = activity;
    return this;
  }

  /// Sets activity type with default confidence.
  LocationFactory withActivityType(ActivityType type, {int confidence = 80}) {
    _activity = Activity(type: type, confidence: confidence);
    return this;
  }

  /// Sets battery info.
  LocationFactory withBattery(Battery battery) {
    _battery = battery;
    return this;
  }

  /// Sets battery level.
  LocationFactory withBatteryLevel(int level, {bool charging = false}) {
    _battery = Battery(level: level.toDouble(), isCharging: charging);
    return this;
  }

  /// Associates with a geofence.
  LocationFactory inGeofence(Geofence geofence) {
    _geofence = geofence;
    return this;
  }

  /// Sets odometer reading.
  LocationFactory withOdometer(double odometer) {
    _odometer = odometer;
    return this;
  }

  /// Sets extras/metadata.
  LocationFactory withExtras(Map<String, dynamic> extras) {
    _extras = extras;
    return this;
  }

  /// Marks as a mock location.
  LocationFactory mock() {
    _isMock = true;
    return this;
  }

  /// Sets high accuracy values (good GPS signal).
  LocationFactory highAccuracy() {
    _accuracy = 3.0;
    return this;
  }

  /// Sets poor accuracy values (weak GPS signal).
  LocationFactory poorAccuracy() {
    _accuracy = 50.0;
    return this;
  }

  /// Builds the Location object.
  Location build() {
    return Location(
      uuid: 'test-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: _timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: _latitude,
        longitude: _longitude,
        accuracy: _accuracy,
        speed: _speed,
        heading: _heading,
        altitude: _altitude,
      ),
      isMoving: _isMoving,
      isHeartbeat: _isHeartbeat,
      isMock: _isMock,
      event: _event,
      activity: _activity,
      battery: _battery,
      geofence: _geofence,
      odometer: _odometer,
      extras: _extras,
    );
  }

  /// Creates a sequence of locations along a path.
  static List<Location> route(
    List<(double lat, double lng)> waypoints, {
    Duration interval = const Duration(seconds: 5),
    double speed = 5.0,
    double accuracy = 10.0,
    DateTime? startTime,
  }) {
    final locations = <Location>[];
    var timestamp = startTime ?? DateTime.now();
    
    for (final (lat, lng) in waypoints) {
      locations.add(
        LocationFactory()
            .at(lat, lng)
            .withAccuracy(accuracy)
            .withSpeed(speed)
            .moving()
            .withTimestamp(timestamp)
            .build(),
      );
      timestamp = timestamp.add(interval);
    }
    
    return locations;
  }

  /// Creates a stationary sequence (heartbeats).
  static List<Location> stationarySequence(
    double latitude,
    double longitude, {
    int count = 5,
    Duration interval = const Duration(minutes: 1),
    double accuracy = 10.0,
    DateTime? startTime,
  }) {
    final locations = <Location>[];
    var timestamp = startTime ?? DateTime.now();
    
    for (var i = 0; i < count; i++) {
      locations.add(
        LocationFactory()
            .at(latitude, longitude)
            .withAccuracy(accuracy)
            .stationary()
            .heartbeat()
            .withTimestamp(timestamp)
            .build(),
      );
      timestamp = timestamp.add(interval);
    }
    
    return locations;
  }
}
