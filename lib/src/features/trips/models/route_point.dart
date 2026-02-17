import 'package:locus/src/shared/models/json_map.dart';

class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
  });

  factory RoutePoint.fromMap(JsonMap map) {
    return RoutePoint(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
  final double latitude;
  final double longitude;

  JsonMap toMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };
}
