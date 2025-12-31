import '../common/json_map.dart';
import '../location/location.dart';

class GeolocationState {
  final bool enabled;
  final bool isMoving;
  final bool? schedulerEnabled;
  final double? odometer;
  final Location? location;
  final JsonMap? extras;

  const GeolocationState({
    required this.enabled,
    this.isMoving = false,
    this.schedulerEnabled,
    this.odometer,
    this.location,
    this.extras,
  });

  /// Creates a copy of this state with the given fields replaced.
  GeolocationState copyWith({
    bool? enabled,
    bool? isMoving,
    bool? schedulerEnabled,
    double? odometer,
    Location? location,
    JsonMap? extras,
  }) {
    return GeolocationState(
      enabled: enabled ?? this.enabled,
      isMoving: isMoving ?? this.isMoving,
      schedulerEnabled: schedulerEnabled ?? this.schedulerEnabled,
      odometer: odometer ?? this.odometer,
      location: location ?? this.location,
      extras: extras ?? this.extras,
    );
  }

  JsonMap toMap() => {
        'enabled': enabled,
        'isMoving': isMoving,
        if (schedulerEnabled != null) 'schedulerEnabled': schedulerEnabled,
        if (odometer != null) 'odometer': odometer,
        if (location != null) 'location': location!.toMap(),
        if (extras != null) 'extras': extras,
      };

  factory GeolocationState.fromMap(JsonMap map) {
    final locationData = map['location'];
    final extrasData = map['extras'];

    return GeolocationState(
      enabled: map['enabled'] as bool? ?? false,
      isMoving: map['isMoving'] as bool? ?? false,
      schedulerEnabled: map['schedulerEnabled'] as bool?,
      odometer: (map['odometer'] as num?)?.toDouble(),
      location: locationData is Map
          ? Location.fromMap(Map<String, dynamic>.from(locationData))
          : null,
      extras: extrasData is Map ? Map<String, dynamic>.from(extrasData) : null,
    );
  }
}
