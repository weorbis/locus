library;

import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';

/// Utility for mapping native platform events to typed Dart events.
class EventMapper {
  const EventMapper._();

  /// Converts a raw native event to a typed [GeolocationEvent].
  static GeolocationEvent<dynamic> mapToEvent(dynamic raw) {
    if (raw is Map) {
      final map = deepMap(raw);
      if (map.containsKey('type')) {
        return GeolocationEvent.fromMap(map);
      }
      if (map.containsKey('coords')) {
        return GeolocationEvent<Location>(
          type: EventType.location,
          data: Location.fromMap(map),
        );
      }
    }
    return GeolocationEvent<dynamic>(type: EventType.unknown, data: raw);
  }

  /// Recursively converts a dynamic map to a typed [JsonMap].
  static JsonMap deepMap(Map<dynamic, dynamic> raw) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      map[key.toString()] = _deepCast(value);
    });
    return map;
  }

  static dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return deepMap(Map<dynamic, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }
}
