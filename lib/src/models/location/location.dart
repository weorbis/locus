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

    return Location(
      uuid: map['uuid'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      age: (map['age'] as num?)?.toInt(),
      event: map['event'] as String?,
      isMoving: map['is_moving'] as bool?,
      isHeartbeat: map['is_heartbeat'] as bool?,
      coords: Coords.fromMap(
        coordsMap is Map ? Map<String, dynamic>.from(coordsMap) : const {},
      ),
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
}
