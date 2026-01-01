import 'package:locus/src/config/constants.dart';
import '../common/json_map.dart';
import 'route_point.dart';

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
  });

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
    );
  }
}
