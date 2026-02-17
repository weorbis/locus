import 'package:flutter/foundation.dart';
import 'package:locus/src/shared/models/activity.dart';
import 'package:locus/src/shared/models/battery.dart';
import 'package:locus/src/shared/models/coords.dart';
import 'package:locus/src/features/geofencing/models/geofence.dart';
import 'package:locus/src/shared/models/json_map.dart';

class Location {
  const Location({
    required this.uuid,
    required this.timestamp,
    required this.coords,
    this.age,
    this.event,
    this.isMoving,
    this.isHeartbeat,
    this.isMock = false,
    this.activity,
    this.battery,
    this.geofence,
    this.odometer,
    this.extras,
  });

  factory Location.fromMap(JsonMap map) {
    final coordsMap = map['coords'];
    final activityMap = map['activity'];
    final batteryMap = map['battery'];
    final geofenceMap = map['geofence'];

    // Use non-strict mode for backward compatibility with existing data
    // but still get range validation
    Coords coords;
    try {
      coords = Coords.fromMap(
        coordsMap is Map ? Map<String, dynamic>.from(coordsMap) : const {},
        strict: false, // Don't throw on missing data for backward compat
      );
    } on InvalidCoordsException catch (e) {
      assert(() {
        debugPrint('[Locus] Invalid coords in location: $e');
        return true;
      }());
      // If range validation fails, use default invalid coords
      coords = const Coords(
        latitude: 0.0,
        longitude: 0.0,
        accuracy: -1, // Mark as invalid with negative accuracy
      );
    }

    return Location(
      uuid: map['uuid'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      age: (map['age'] as num?)?.toInt(),
      event: map['event'] as String?,
      isMoving: map['is_moving'] as bool?,
      isHeartbeat: map['is_heartbeat'] as bool?,
      isMock: map['mock'] as bool? ?? false,
      coords: coords,
      activity: activityMap is Map
          ? Activity.fromMap(Map<String, dynamic>.from(activityMap))
          : null,
      battery: batteryMap is Map
          ? Battery.fromMap(Map<String, dynamic>.from(batteryMap))
          : null,
      geofence: geofenceMap is Map
          ? Geofence.fromMap(Map<String, dynamic>.from(geofenceMap))
          : null,
      odometer: (map['odometer'] as num?)?.toDouble(),
      extras: map['extras'] is Map
          ? Map<String, dynamic>.from(map['extras'] as Map)
          : null,
    );
  }
  final String uuid;
  final DateTime timestamp;
  final int? age;
  final String? event;
  final bool? isMoving;
  final bool? isHeartbeat;
  final bool isMock;
  final Coords coords;
  final Activity? activity;
  final Battery? battery;
  final Geofence? geofence;
  final double? odometer;
  final JsonMap? extras;

  /// Whether this location has valid coordinates.
  bool get hasValidCoords => coords.isValid && !coords.isNullIsland;

  Location copyWith({
    String? uuid,
    DateTime? timestamp,
    int? age,
    String? event,
    bool? isMoving,
    bool? isHeartbeat,
    bool? isMock,
    Coords? coords,
    Activity? activity,
    Battery? battery,
    Geofence? geofence,
    double? odometer,
    JsonMap? extras,
  }) {
    return Location(
      uuid: uuid ?? this.uuid,
      timestamp: timestamp ?? this.timestamp,
      age: age ?? this.age,
      event: event ?? this.event,
      isMoving: isMoving ?? this.isMoving,
      isHeartbeat: isHeartbeat ?? this.isHeartbeat,
      isMock: isMock ?? this.isMock,
      coords: coords ?? this.coords,
      activity: activity ?? this.activity,
      battery: battery ?? this.battery,
      geofence: geofence ?? this.geofence,
      odometer: odometer ?? this.odometer,
      extras: extras ?? this.extras,
    );
  }

  JsonMap toMap() => {
        'uuid': uuid,
        'timestamp': timestamp.toIso8601String(),
        if (age != null) 'age': age,
        if (event != null) 'event': event,
        if (isMoving != null) 'is_moving': isMoving,
        if (isHeartbeat != null) 'is_heartbeat': isHeartbeat,
        'mock': isMock,
        'coords': coords.toMap(),
        if (activity != null) 'activity': activity!.toMap(),
        if (battery != null) 'battery': battery!.toMap(),
        if (geofence != null) 'geofence': geofence!.toMap(),
        if (odometer != null) 'odometer': odometer,
        if (extras != null) 'extras': extras,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Location &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'Location(uuid: $uuid, coords: $coords, event: $event)';
}
