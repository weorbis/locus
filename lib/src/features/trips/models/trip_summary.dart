import 'package:locus/src/shared/models/json_map.dart';

class TripSummary {
  const TripSummary({
    required this.tripId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.idleSeconds,
    required this.maxSpeedKph,
    required this.averageSpeedKph,
  });

  factory TripSummary.fromMap(JsonMap map) {
    return TripSummary(
      tripId: map['tripId'] as String? ?? '',
      startedAt: DateTime.tryParse(map['startedAt'] as String? ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(map['endedAt'] as String? ?? '') ?? DateTime.now(),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      idleSeconds: (map['idleSeconds'] as num?)?.toInt() ?? 0,
      maxSpeedKph: (map['maxSpeedKph'] as num?)?.toDouble() ?? 0,
      averageSpeedKph: (map['averageSpeedKph'] as num?)?.toDouble() ?? 0,
    );
  }
  final String tripId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final int durationSeconds;
  final int idleSeconds;
  final double maxSpeedKph;
  final double averageSpeedKph;

  JsonMap toMap() => {
        'tripId': tripId,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'idleSeconds': idleSeconds,
        'maxSpeedKph': maxSpeedKph,
        'averageSpeedKph': averageSpeedKph,
      };
}
