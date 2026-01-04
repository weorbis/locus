import 'package:locus/src/shared/models/json_map.dart';

class QueueItem {
  final String id;
  final DateTime createdAt;
  final JsonMap payload;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? idempotencyKey;
  final String? type;

  const QueueItem({
    required this.id,
    required this.createdAt,
    required this.payload,
    required this.retryCount,
    this.nextRetryAt,
    this.idempotencyKey,
    this.type,
  });

  JsonMap toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        'retryCount': retryCount,
        if (nextRetryAt != null) 'nextRetryAt': nextRetryAt!.toIso8601String(),
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        if (type != null) 'type': type,
      };

  factory QueueItem.fromMap(JsonMap map) {
    return QueueItem(
      id: map['id'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const {},
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: map['nextRetryAt'] != null
          ? DateTime.tryParse(map['nextRetryAt'] as String)
          : null,
      idempotencyKey: map['idempotencyKey'] as String?,
      type: map['type'] as String?,
    );
  }
}
