import '../common/json_map.dart';
import '../location/location.dart';
import 'trip_summary.dart';

enum TripEventType {
  tripStart,
  tripUpdate,
  tripEnd,
  dwell,
  routeDeviation,
}

class TripEvent {
  final TripEventType type;
  final String tripId;
  final DateTime timestamp;
  final Location? location;
  final TripSummary? summary;
  final double? distanceFromRouteMeters;
  final bool? isMoving;

  const TripEvent({
    required this.type,
    required this.tripId,
    required this.timestamp,
    this.location,
    this.summary,
    this.distanceFromRouteMeters,
    this.isMoving,
  });

  JsonMap toMap() => {
        'type': type.name,
        'tripId': tripId,
        'timestamp': timestamp.toIso8601String(),
        if (location != null) 'location': location!.toMap(),
        if (summary != null) 'summary': summary!.toMap(),
        if (distanceFromRouteMeters != null)
          'distanceFromRouteMeters': distanceFromRouteMeters,
        if (isMoving != null) 'isMoving': isMoving,
      };
}
