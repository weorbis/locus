import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/features/trips/models/trip_summary.dart';

class TripState {
  final String tripId;
  final DateTime createdAt;
  final DateTime? startedAt;
  final Location? startLocation;
  final Location? lastLocation;
  final double distanceMeters;
  final int idleSeconds;
  final double maxSpeedKph;
  final bool started;
  final bool ended;

  const TripState({
    required this.tripId,
    required this.createdAt,
    required this.startedAt,
    required this.startLocation,
    required this.lastLocation,
    required this.distanceMeters,
    required this.idleSeconds,
    required this.maxSpeedKph,
    required this.started,
    required this.ended,
  });

  JsonMap toMap() => {
        'tripId': tripId,
        'createdAt': createdAt.toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (startLocation != null) 'startLocation': startLocation!.toMap(),
        if (lastLocation != null) 'lastLocation': lastLocation!.toMap(),
        'distanceMeters': distanceMeters,
        'idleSeconds': idleSeconds,
        'maxSpeedKph': maxSpeedKph,
        'started': started,
        'ended': ended,
      };

  factory TripState.fromMap(JsonMap map) {
    final startLoc = map['startLocation'];
    final lastLoc = map['lastLocation'];

    return TripState(
      tripId: map['tripId'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      startedAt: map['startedAt'] != null
          ? DateTime.tryParse(map['startedAt'] as String)
          : null,
      startLocation: startLoc is Map
          ? Location.fromMap(Map<String, dynamic>.from(startLoc))
          : null,
      lastLocation: lastLoc is Map
          ? Location.fromMap(Map<String, dynamic>.from(lastLoc))
          : null,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      idleSeconds: (map['idleSeconds'] as num?)?.toInt() ?? 0,
      maxSpeedKph: (map['maxSpeedKph'] as num?)?.toDouble() ?? 0,
      started: map['started'] as bool? ?? false,
      ended: map['ended'] as bool? ?? false,
    );
  }

  TripSummary? toSummary(DateTime endedAt) {
    if (startedAt == null) {
      return null;
    }
    final durationSeconds = endedAt.difference(startedAt!).inSeconds;
    final movingSeconds =
        (durationSeconds - idleSeconds).clamp(0, durationSeconds);
    final averageSpeedKph =
        movingSeconds > 0 ? (distanceMeters / movingSeconds) * 3.6 : 0.0;

    return TripSummary(
      tripId: tripId,
      startedAt: startedAt!,
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      idleSeconds: idleSeconds,
      maxSpeedKph: maxSpeedKph,
      averageSpeedKph: averageSpeedKph,
    );
  }

  @override
  String toString() =>
      'TripState($tripId, distance: ${(distanceMeters / 1000).toStringAsFixed(2)}km, '
      'started: $started, ended: $ended)';
}
