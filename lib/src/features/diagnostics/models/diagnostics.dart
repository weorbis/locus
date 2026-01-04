import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/shared/models/geolocation_state.dart';
import 'package:locus/src/features/sync/models/queue_item.dart';

class DiagnosticsSnapshot {
  final DateTime capturedAt;
  final GeolocationState? state;
  final JsonMap? config;
  final List<QueueItem> queue;
  final JsonMap? metadata;

  const DiagnosticsSnapshot({
    required this.capturedAt,
    required this.state,
    required this.config,
    required this.queue,
    required this.metadata,
  });

  JsonMap toMap() => {
        'capturedAt': capturedAt.toIso8601String(),
        if (state != null) 'state': state!.toMap(),
        if (config != null) 'config': config,
        'queue': queue.map((item) => item.toMap()).toList(),
        if (metadata != null) 'metadata': metadata,
      };
}

enum RemoteCommandType {
  setConfig,
  syncQueue,
  emailLog,
  setOdometer,
  resetOdometer,
}

class RemoteCommand {
  final String id;
  final RemoteCommandType type;
  final JsonMap? payload;

  const RemoteCommand({
    required this.id,
    required this.type,
    this.payload,
  });

  factory RemoteCommand.fromMap(JsonMap map) {
    return RemoteCommand(
      id: map['id'] as String? ?? '',
      type: RemoteCommandType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => RemoteCommandType.syncQueue,
      ),
      payload: map['payload'] != null
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : null,
    );
  }
}
