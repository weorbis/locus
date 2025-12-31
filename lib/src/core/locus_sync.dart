import 'package:locus/src/models/models.dart';
import 'locus_channels.dart';

/// Sync operations.
class LocusSync {
  /// Triggers an immediate sync of pending locations.
  static Future<bool> sync() async {
    final result = await LocusChannels.methods.invokeMethod('sync');
    return result == true;
  }

  /// Destroys all stored locations.
  static Future<bool> destroyLocations() async {
    final result = await LocusChannels.methods.invokeMethod('destroyLocations');
    return result == true;
  }

  /// Enqueues a custom payload for offline-first delivery.
  static Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) async {
    final result = await LocusChannels.methods.invokeMethod('enqueue', {
      'payload': payload,
      if (type != null) 'type': type,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
    return result is String ? result : '';
  }

  /// Returns queued payloads.
  static Future<List<QueueItem>> getQueue({int? limit}) async {
    final result = await LocusChannels.methods.invokeMethod(
      'getQueue',
      limit == null ? null : {'limit': limit},
    );
    if (result is List) {
      return result
          .map((item) =>
              QueueItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return [];
  }

  /// Clears all queued payloads.
  static Future<void> clearQueue() async {
    await LocusChannels.methods.invokeMethod('clearQueue');
  }

  /// Attempts to sync queued payloads immediately.
  static Future<int> syncQueue({int? limit}) async {
    final result = await LocusChannels.methods.invokeMethod(
      'syncQueue',
      limit == null ? null : {'limit': limit},
    );
    return (result as num?)?.toInt() ?? 0;
  }
}
