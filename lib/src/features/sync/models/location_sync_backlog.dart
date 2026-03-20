import 'package:locus/src/shared/models/json_map.dart';

class LocationSyncBacklogGroup {
  const LocationSyncBacklogGroup({
    required this.ownerId,
    required this.driverId,
    required this.taskId,
    required this.trackingSessionId,
    required this.startedAt,
    required this.pendingLocationCount,
  });

  factory LocationSyncBacklogGroup.fromMap(JsonMap map) {
    return LocationSyncBacklogGroup(
      ownerId: map['ownerId']?.toString() ?? '',
      driverId: map['driverId']?.toString() ?? '',
      taskId: map['taskId']?.toString() ?? '',
      trackingSessionId: map['trackingSessionId']?.toString() ?? '',
      startedAt: map['startedAt'] == null
          ? null
          : DateTime.tryParse(map['startedAt'].toString()),
      pendingLocationCount: (map['pendingLocationCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String ownerId;
  final String driverId;
  final String taskId;
  final String trackingSessionId;
  final DateTime? startedAt;
  final int pendingLocationCount;

  JsonMap toMap() => {
        'ownerId': ownerId,
        'driverId': driverId,
        'taskId': taskId,
        'trackingSessionId': trackingSessionId,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        'pendingLocationCount': pendingLocationCount,
      };
}

class LocationSyncBacklog {
  const LocationSyncBacklog({
    this.pendingLocationCount = 0,
    this.pendingBatchCount = 0,
    this.isPaused = false,
    this.quarantinedLocationCount = 0,
    this.groups = const [],
    this.lastSuccessAt,
    this.lastFailureReason,
  });

  factory LocationSyncBacklog.fromMap(JsonMap map) {
    final groups = (map['groups'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (group) => LocationSyncBacklogGroup.fromMap(
            Map<String, dynamic>.from(group),
          ),
        )
        .toList(growable: false);

    return LocationSyncBacklog(
      pendingLocationCount: (map['pendingLocationCount'] as num?)?.toInt() ?? 0,
      pendingBatchCount: (map['pendingBatchCount'] as num?)?.toInt() ?? 0,
      isPaused: map['isPaused'] == true,
      quarantinedLocationCount:
          (map['quarantinedLocationCount'] as num?)?.toInt() ?? 0,
      lastSuccessAt: map['lastSuccessAt'] == null
          ? null
          : DateTime.tryParse(map['lastSuccessAt'].toString()),
      lastFailureReason: map['lastFailureReason']?.toString(),
      groups: groups,
    );
  }

  final int pendingLocationCount;
  final int pendingBatchCount;
  final bool isPaused;
  final int quarantinedLocationCount;
  final DateTime? lastSuccessAt;
  final String? lastFailureReason;
  final List<LocationSyncBacklogGroup> groups;

  JsonMap toMap() => {
        'pendingLocationCount': pendingLocationCount,
        'pendingBatchCount': pendingBatchCount,
        'isPaused': isPaused,
        'quarantinedLocationCount': quarantinedLocationCount,
        if (lastSuccessAt != null)
          'lastSuccessAt': lastSuccessAt!.toIso8601String(),
        if (lastFailureReason != null) 'lastFailureReason': lastFailureReason,
        'groups': groups.map((group) => group.toMap()).toList(growable: false),
      };
}
