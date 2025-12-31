import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('queue item round-trip', () {
    final item = QueueItem(
      id: 'q-1',
      createdAt: DateTime.utc(2025, 1, 1),
      payload: const {'event': 'tripstart'},
      retryCount: 2,
      nextRetryAt: DateTime.utc(2025, 1, 1, 0, 5),
      idempotencyKey: 'key-123',
      type: 'trip',
    );

    final map = item.toMap();
    final restored = QueueItem.fromMap(map);

    expect(restored.id, 'q-1');
    expect(restored.payload['event'], 'tripstart');
    expect(restored.retryCount, 2);
    expect(restored.idempotencyKey, 'key-123');
    expect(restored.type, 'trip');
  });
}
