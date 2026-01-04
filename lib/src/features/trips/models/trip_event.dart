import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/features/trips/models/trip_summary.dart';

enum TripEventType {
  tripStart,
  tripUpdate,
  tripEnd,
  dwell,
  routeDeviation,
  diagnostic,
  /// Waypoint reached event.
  waypointReached,
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

  /// Index of reached waypoint (present for waypointReached events).
  final int? waypointIndex;

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
    this.waypointIndex,
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

  /// Creates a waypoint reached event.
  factory TripEvent.waypointReached({
    required String tripId,
    required int waypointIndex,
    required Location location,
  }) {
    return TripEvent(
      type: TripEventType.waypointReached,
      tripId: tripId,
      timestamp: DateTime.now().toUtc(),
      location: location,
      waypointIndex: waypointIndex,
      isMoving: true,
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
        if (waypointIndex != null) 'waypointIndex': waypointIndex,
      };
}
