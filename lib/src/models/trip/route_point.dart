import '../common/json_map.dart';

class RoutePoint {
  final double latitude;
  final double longitude;

  const RoutePoint({
    required this.latitude,
    required this.longitude,
  });

  JsonMap toMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory RoutePoint.fromMap(JsonMap map) {
    return RoutePoint(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }
}
