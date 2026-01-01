import '../common/json_map.dart';
import '../location/location.dart';
import 'trip_summary.dart';

enum TripEventType {
  tripStart,
  tripUpdate,
  tripEnd,
  dwell,
  routeDeviation,
  diagnostic,
}

class TripEvent {
  final TripEventType type;
  final String tripId;
  final DateTime timestamp;
  final Location? location;
  final TripSummary? summary;
  final double? distanceFromRouteMeters;
  final bool? isMoving;
  final String? message;
  final JsonMap? data;

  const TripEvent({
    required this.type,
    required this.tripId,
    required this.timestamp,
    this.location,
    this.summary,
    this.distanceFromRouteMeters,
    this.isMoving,
    this.message,
    this.data,
  });

  /// Creates a diagnostic event for internal trip engine issues.
  factory TripEvent.diagnostic({
    required String tripId,
    required String message,
    JsonMap? data,
  }) {
    return TripEvent(
      type: TripEventType.diagnostic,
      tripId: tripId,
      timestamp: DateTime.now().toUtc(),
      message: message,
      data: data,
    );
  }

  JsonMap toMap() => {
        'type': type.name,
        'tripId': tripId,
        'timestamp': timestamp.toIso8601String(),
        if (location != null) 'location': location!.toMap(),
        if (summary != null) 'summary': summary!.toMap(),
        if (distanceFromRouteMeters != null)
          'distanceFromRouteMeters': distanceFromRouteMeters,
        if (isMoving != null) 'isMoving': isMoving,
        if (message != null) 'message': message,
        if (data != null) 'data': data,
      };
}
