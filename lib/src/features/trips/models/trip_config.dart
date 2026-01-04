import 'package:locus/src/config/constants.dart';
import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/trips/models/route_point.dart';

class TripConfig {
  final String? tripId;
  final bool startOnMoving;
  final double startDistanceMeters;
  final double startSpeedKph;
  final bool stopOnStationary;
  final int stopTimeoutMinutes;
  final double stationarySpeedKph;
  final int updateIntervalSeconds;
  final int dwellMinutes;
  final List<RoutePoint> route;
  final double routeDeviationThresholdMeters;
  final int routeDeviationCooldownSeconds;

  /// Destination point for the trip (optional).
  final RoutePoint? destination;

  /// Waypoints to visit before destination (ordered).
  final List<RoutePoint> waypoints;

  const TripConfig({
    this.tripId,
    this.startOnMoving = true,
    this.startDistanceMeters = 50,
    this.startSpeedKph = 5,
    this.stopOnStationary = true,
    this.stopTimeoutMinutes = 5,
    this.stationarySpeedKph = 1.5,
    this.updateIntervalSeconds = kDefaultUpdateIntervalSeconds,
    this.dwellMinutes = 5,
    this.route = const [],
    this.routeDeviationThresholdMeters = kDefaultRouteDeviationThresholdMeters,
    this.routeDeviationCooldownSeconds = kDefaultUpdateIntervalSeconds,
    this.destination,
    this.waypoints = const [],
  });

  /// Creates a copy with modified values.
  TripConfig copyWith({
    String? tripId,
    bool? startOnMoving,
    double? startDistanceMeters,
    double? startSpeedKph,
    bool? stopOnStationary,
    int? stopTimeoutMinutes,
    double? stationarySpeedKph,
    int? updateIntervalSeconds,
    int? dwellMinutes,
    List<RoutePoint>? route,
    double? routeDeviationThresholdMeters,
    int? routeDeviationCooldownSeconds,
    RoutePoint? destination,
    List<RoutePoint>? waypoints,
  }) {
    return TripConfig(
      tripId: tripId ?? this.tripId,
      startOnMoving: startOnMoving ?? this.startOnMoving,
      startDistanceMeters: startDistanceMeters ?? this.startDistanceMeters,
      startSpeedKph: startSpeedKph ?? this.startSpeedKph,
      stopOnStationary: stopOnStationary ?? this.stopOnStationary,
      stopTimeoutMinutes: stopTimeoutMinutes ?? this.stopTimeoutMinutes,
      stationarySpeedKph: stationarySpeedKph ?? this.stationarySpeedKph,
      updateIntervalSeconds:
          updateIntervalSeconds ?? this.updateIntervalSeconds,
      dwellMinutes: dwellMinutes ?? this.dwellMinutes,
      route: route ?? this.route,
      routeDeviationThresholdMeters:
          routeDeviationThresholdMeters ?? this.routeDeviationThresholdMeters,
      routeDeviationCooldownSeconds:
          routeDeviationCooldownSeconds ?? this.routeDeviationCooldownSeconds,
      destination: destination ?? this.destination,
      waypoints: waypoints ?? this.waypoints,
    );
  }

  JsonMap toMap() => {
        if (tripId != null) 'tripId': tripId,
        'startOnMoving': startOnMoving,
        'startDistanceMeters': startDistanceMeters,
        'startSpeedKph': startSpeedKph,
        'stopOnStationary': stopOnStationary,
        'stopTimeoutMinutes': stopTimeoutMinutes,
        'stationarySpeedKph': stationarySpeedKph,
        'updateIntervalSeconds': updateIntervalSeconds,
        'dwellMinutes': dwellMinutes,
        'route': route.map((point) => point.toMap()).toList(),
        'routeDeviationThresholdMeters': routeDeviationThresholdMeters,
        'routeDeviationCooldownSeconds': routeDeviationCooldownSeconds,
        if (destination != null) 'destination': destination!.toMap(),
        'waypoints': waypoints.map((point) => point.toMap()).toList(),
      };

  factory TripConfig.fromMap(JsonMap map) {
    return TripConfig(
      tripId: map['tripId'] as String?,
      startOnMoving: map['startOnMoving'] as bool? ?? true,
      startDistanceMeters:
          (map['startDistanceMeters'] as num?)?.toDouble() ?? 50,
      startSpeedKph: (map['startSpeedKph'] as num?)?.toDouble() ?? 5,
      stopOnStationary: map['stopOnStationary'] as bool? ?? true,
      stopTimeoutMinutes: (map['stopTimeoutMinutes'] as num?)?.toInt() ?? 5,
      stationarySpeedKph:
          (map['stationarySpeedKph'] as num?)?.toDouble() ?? 1.5,
      updateIntervalSeconds: (map['updateIntervalSeconds'] as num?)?.toInt() ??
          kDefaultUpdateIntervalSeconds,
      dwellMinutes: (map['dwellMinutes'] as num?)?.toInt() ?? 5,
      route: (map['route'] as List?)
              ?.map((item) =>
                  RoutePoint.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList() ??
          const [],
      routeDeviationThresholdMeters:
          (map['routeDeviationThresholdMeters'] as num?)?.toDouble() ??
              kDefaultRouteDeviationThresholdMeters,
      routeDeviationCooldownSeconds:
          (map['routeDeviationCooldownSeconds'] as num?)?.toInt() ??
              kDefaultUpdateIntervalSeconds,
      destination: map['destination'] != null
          ? RoutePoint.fromMap(
              Map<String, dynamic>.from(map['destination'] as Map))
          : null,
      waypoints: (map['waypoints'] as List?)
              ?.map((item) =>
                  RoutePoint.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList() ??
          const [],
    );
  }
}
