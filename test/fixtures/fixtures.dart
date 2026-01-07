/// Test fixtures - sample data for testing.
///
/// This library provides realistic sample data for locations, geofences,
/// configurations, and other locus models.
library;

import 'package:locus/locus.dart';

/// Sample locations for testing.
class LocationFixtures {
  /// San Francisco, CA (downtown)
  static Location sanFrancisco({
    bool isMoving = false,
    double? speed,
    DateTime? timestamp,
  }) {
    return Location(
      uuid: 'sf-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 10,
        speed: speed ?? (isMoving ? 5.0 : 0.0),
        heading: 0,
        altitude: 15,
      ),
      isMoving: isMoving,
      activity: Activity(
        type: isMoving ? ActivityType.walking : ActivityType.still,
        confidence: 85,
      ),
    );
  }

  /// Mountain View, CA (Googleplex)
  static Location mountainView({
    bool isMoving = false,
    double? speed,
    DateTime? timestamp,
  }) {
    return Location(
      uuid: 'mv-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: 37.4219,
        longitude: -122.0840,
        accuracy: 12,
        speed: speed ?? (isMoving ? 10.0 : 0.0),
        heading: 90,
        altitude: 10,
      ),
      isMoving: isMoving,
      activity: Activity(
        type: isMoving ? ActivityType.inVehicle : ActivityType.still,
        confidence: 90,
      ),
    );
  }

  /// New York City (Times Square)
  static Location newYork({
    bool isMoving = false,
    double? speed,
    DateTime? timestamp,
  }) {
    return Location(
      uuid: 'ny-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: 40.7580,
        longitude: -73.9855,
        accuracy: 15,
        speed: speed ?? (isMoving ? 3.0 : 0.0),
        heading: 180,
        altitude: 5,
      ),
      isMoving: isMoving,
      activity: Activity(
        type: isMoving ? ActivityType.walking : ActivityType.still,
        confidence: 80,
      ),
    );
  }

  /// London, UK (Big Ben)
  static Location london({
    bool isMoving = false,
    double? speed,
    DateTime? timestamp,
  }) {
    return Location(
      uuid: 'ldn-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: 51.5007,
        longitude: -0.1246,
        accuracy: 8,
        speed: speed ?? (isMoving ? 7.0 : 0.0),
        heading: 270,
        altitude: 8,
      ),
      isMoving: isMoving,
      activity: Activity(
        type: isMoving ? ActivityType.onBicycle : ActivityType.still,
        confidence: 75,
      ),
    );
  }

  /// Tokyo, Japan (Shibuya)
  static Location tokyo({
    bool isMoving = false,
    double? speed,
    DateTime? timestamp,
  }) {
    return Location(
      uuid: 'tyo-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: 35.6595,
        longitude: 139.7004,
        accuracy: 10,
        speed: speed ?? (isMoving ? 15.0 : 0.0),
        heading: 45,
        altitude: 40,
      ),
      isMoving: isMoving,
      activity: Activity(
        type: isMoving ? ActivityType.inVehicle : ActivityType.still,
        confidence: 88,
      ),
    );
  }

  /// A location with poor GPS accuracy (simulates weak signal)
  static Location poorAccuracy({DateTime? timestamp}) {
    return Location(
      uuid: 'poor-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: const Coords(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 50, // Poor accuracy
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      isMoving: false,
    );
  }

  /// A high-accuracy location (good GPS signal)
  static Location highAccuracy({DateTime? timestamp}) {
    return Location(
      uuid: 'high-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: const Coords(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 3, // High accuracy
        speed: 0,
        heading: 0,
        altitude: 15,
      ),
      isMoving: false,
    );
  }

  /// Null Island (0, 0) - often indicates invalid GPS data
  static Location nullIsland({DateTime? timestamp}) {
    return Location(
      uuid: 'null-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: const Coords(
        latitude: 0,
        longitude: 0,
        accuracy: 10,
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      isMoving: false,
    );
  }
}

/// Sample geofences for testing.
class GeofenceFixtures {
  /// Home geofence (residential area)
  static Geofence home() {
    return const Geofence(
      identifier: 'home',
      latitude: 37.7749,
      longitude: -122.4194,
      radius: 100,
      notifyOnEntry: true,
      notifyOnExit: true,
    );
  }

  /// Office/work geofence
  static Geofence office() {
    return const Geofence(
      identifier: 'office',
      latitude: 37.4219,
      longitude: -122.0840,
      radius: 150,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: true,
      loiteringDelay: 300000, // 5 minutes
    );
  }

  /// Store/shop geofence (small radius)
  static Geofence store() {
    return const Geofence(
      identifier: 'store',
      latitude: 37.7750,
      longitude: -122.4180,
      radius: 50,
      notifyOnEntry: true,
      notifyOnExit: false,
    );
  }

  /// Large city zone geofence
  static Geofence cityZone() {
    return const Geofence(
      identifier: 'city-zone',
      latitude: 37.7749,
      longitude: -122.4194,
      radius: 5000, // 5km radius
      notifyOnEntry: true,
      notifyOnExit: true,
    );
  }

  /// Airport geofence
  static Geofence airport() {
    return const Geofence(
      identifier: 'airport',
      latitude: 37.6213,
      longitude: -122.3790,
      radius: 500,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: true,
      loiteringDelay: 600000, // 10 minutes
    );
  }
}

/// Sample configurations for testing.
class ConfigFixtures {
  /// High-accuracy configuration (fitness/tracking use case)
  static Config highAccuracy() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.high,
      distanceFilter: 10,
      locationUpdateInterval: 5000,
      stopTimeout: 5,
      enableHeadless: true,
      stopOnTerminate: false,
    );
  }

  /// Balanced configuration (default)
  static Config balanced() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.medium,
      distanceFilter: 30,
      locationUpdateInterval: 10000,
      stopTimeout: 5,
      enableHeadless: true,
      stopOnTerminate: false,
    );
  }

  /// Low-power configuration (battery-conscious)
  static Config lowPower() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.low,
      distanceFilter: 100,
      locationUpdateInterval: 60000,
      stopTimeout: 15,
      enableHeadless: false,
      stopOnTerminate: true,
    );
  }

  /// Passive configuration (minimal power, only significant changes)
  static Config passive() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.low,
      distanceFilter: 500,
      useSignificantChangesOnly: true,
      disableMotionActivityUpdates: true,
      disableStopDetection: true,
      stopOnTerminate: true,
    );
  }

  /// Geofence-only configuration
  static Config geofenceOnly() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.low,
      distanceFilter: 50,
      stopTimeout: 1,
      enableHeadless: true,
    );
  }
}

/// Sample activities for testing.
class ActivityFixtures {
  /// Still/stationary activity
  static Activity still({int confidence = 100}) {
    return Activity(
      type: ActivityType.still,
      confidence: confidence,
    );
  }

  /// Walking activity
  static Activity walking({int confidence = 85}) {
    return Activity(
      type: ActivityType.walking,
      confidence: confidence,
    );
  }

  /// Running activity
  static Activity running({int confidence = 80}) {
    return Activity(
      type: ActivityType.running,
      confidence: confidence,
    );
  }

  /// Cycling activity
  static Activity cycling({int confidence = 75}) {
    return Activity(
      type: ActivityType.onBicycle,
      confidence: confidence,
    );
  }

  /// In vehicle activity
  static Activity inVehicle({int confidence = 90}) {
    return Activity(
      type: ActivityType.inVehicle,
      confidence: confidence,
    );
  }

  /// Unknown activity (low confidence)
  static Activity unknown() {
    return const Activity(
      type: ActivityType.unknown,
      confidence: 0,
    );
  }
}

/// Sample battery states for testing.
class BatteryFixtures {
  /// Full battery
  static Battery full({bool charging = false}) {
    return Battery(
      level: 100,
      isCharging: charging,
    );
  }

  /// High battery
  static Battery high({bool charging = false}) {
    return Battery(
      level: 85,
      isCharging: charging,
    );
  }

  /// Medium battery
  static Battery medium({bool charging = false}) {
    return Battery(
      level: 50,
      isCharging: charging,
    );
  }

  /// Low battery
  static Battery low({bool charging = false}) {
    return Battery(
      level: 15,
      isCharging: charging,
    );
  }

  /// Critical battery
  static Battery critical({bool charging = false}) {
    return Battery(
      level: 5,
      isCharging: charging,
    );
  }
}
