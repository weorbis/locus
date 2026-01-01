import '../common/activity.dart';
import '../common/battery.dart';
import '../common/coords.dart';
import '../geofence/geofence.dart';
import '../common/json_map.dart';

class Location {
  final String uuid;
  final DateTime timestamp;
  final int? age;
  final String? event;
  final bool? isMoving;
  final bool? isHeartbeat;
  final Coords coords;
  final Activity? activity;
  final Battery? battery;
  final Geofence? geofence;
  final double? odometer;
  final JsonMap? extras;

  const Location({
    required this.uuid,
    required this.timestamp,
    required this.coords,
    this.age,
    this.event,
    this.isMoving,
    this.isHeartbeat,
    this.activity,
    this.battery,
    this.geofence,
    this.odometer,
    this.extras,
  });

  /// Whether this location has valid coordinates.
  bool get hasValidCoords => coords.isValid && !coords.isNullIsland;

  JsonMap toMap() => {
        'uuid': uuid,
        'timestamp': timestamp.toIso8601String(),
        if (age != null) 'age': age,
        if (event != null) 'event': event,
        if (isMoving != null) 'is_moving': isMoving,
        if (isHeartbeat != null) 'is_heartbeat': isHeartbeat,
        'coords': coords.toMap(),
        if (activity != null) 'activity': activity!.toMap(),
        if (battery != null) 'battery': battery!.toMap(),
        if (geofence != null) 'geofence': geofence!.toMap(),
        if (odometer != null) 'odometer': odometer,
        if (extras != null) 'extras': extras,
      };

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
    } on InvalidCoordsException {
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
