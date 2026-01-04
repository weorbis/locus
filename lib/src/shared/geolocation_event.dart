library;

import 'package:locus/src/shared/event_type.dart';
import 'package:locus/src/models.dart';

/// A generic geolocation event with typed payload.
class GeolocationEvent<T> {
  /// The type of event.
  final EventType type;

  /// The event payload data.
  final T data;

  const GeolocationEvent({
    required this.type,
    required this.data,
  });

  static EventType _parseType(String? raw) {
    switch (raw) {
      case 'location':
        return EventType.location;
      case 'motionchange':
        return EventType.motionChange;
      case 'providerchange':
        return EventType.providerChange;
      case 'activitychange':
        return EventType.activityChange;
      case 'geofence':
        return EventType.geofence;
      case 'geofenceschange':
        return EventType.geofencesChange;
      case 'heartbeat':
        return EventType.heartbeat;
      case 'schedule':
        return EventType.schedule;
      case 'connectivitychange':
        return EventType.connectivityChange;
      case 'powersavechange':
        return EventType.powerSaveChange;
      case 'enabledchange':
        return EventType.enabledChange;
      case 'notificationaction':
        return EventType.notificationAction;
      case 'http':
        return EventType.http;
      default:
        return EventType.unknown;
    }
  }

  static GeolocationEvent<dynamic> fromMap(JsonMap map) {
    final type = _parseType(map['type'] as String?);
    final payload = map['data'];

    switch (type) {
      case EventType.location:
        return GeolocationEvent<Location>(
          type: type,
          data: Location.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.motionChange:
      case EventType.heartbeat:
      case EventType.schedule:
        return GeolocationEvent<Location>(
          type: type,
          data: Location.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.activityChange:
        if (payload is Map && payload['activity'] is Map) {
          return GeolocationEvent<Activity>(
            type: type,
            data: Activity.fromMap(
              Map<String, dynamic>.from(payload['activity'] as Map),
            ),
          );
        }
        return GeolocationEvent<Activity>(
          type: type,
          data: Activity.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.providerChange:
        return GeolocationEvent<ProviderChangeEvent>(
          type: type,
          data: ProviderChangeEvent.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.geofence:
        return GeolocationEvent<GeofenceEvent>(
          type: type,
          data: GeofenceEvent.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.connectivityChange:
        return GeolocationEvent<ConnectivityChangeEvent>(
          type: type,
          data: ConnectivityChangeEvent.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.http:
        return GeolocationEvent<HttpEvent>(
          type: type,
          data: HttpEvent.fromMap(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      case EventType.notificationAction:
      case EventType.powerSaveChange:
      case EventType.enabledChange:
      case EventType.geofencesChange:
      case EventType.unknown:
        return GeolocationEvent<dynamic>(
          type: type,
          data: payload,
        );
    }
  }
}
