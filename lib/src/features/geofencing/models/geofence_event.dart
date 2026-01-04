import 'package:locus/src/shared/models/enums.dart';
import 'package:locus/src/features/geofencing/models/geofence.dart';
import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/location/models/location.dart';

class GeofenceEvent {
  final Geofence geofence;
  final GeofenceAction action;
  final Location? location;

  const GeofenceEvent({
    required this.geofence,
    required this.action,
    this.location,
  });

  JsonMap toMap() => {
        'geofence': geofence.toMap(),
        'action': action.name,
        if (location != null) 'location': location!.toMap(),
      };

  factory GeofenceEvent.fromMap(JsonMap map) {
    final geofenceData = map['geofence'];
    final locationData = map['location'];

    return GeofenceEvent(
      geofence: geofenceData is Map
          ? Geofence.fromMap(Map<String, dynamic>.from(geofenceData))
          : const Geofence(
              identifier: '',
              radius: 0,
              latitude: 0,
              longitude: 0,
            ),
      action: GeofenceAction.values.firstWhere(
        (value) => value.name == map['action'],
        orElse: () => GeofenceAction.unknown,
      ),
      location: locationData is Map
          ? Location.fromMap(Map<String, dynamic>.from(locationData))
          : null,
    );
  }

  @override
  String toString() => 'GeofenceEvent(${action.name}: ${geofence.identifier})';
}
