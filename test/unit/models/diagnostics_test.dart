import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('diagnostics snapshot serializes fields', () {
    final snapshot = DiagnosticsSnapshot(
      capturedAt: DateTime.utc(2025, 1, 1),
      state: const GeolocationState(enabled: true, isMoving: false),
      config: const {'distanceFilter': 10},
      queue: const [],
      metadata: const {'platform': 'test'},
    );

    final map = snapshot.toMap();
    expect(map['state'], isNotNull);
    expect(map['config'], {'distanceFilter': 10});
    expect(map['metadata'], {'platform': 'test'});
  });

  test('remote command parses payload', () {
    final command = RemoteCommand.fromMap({
      'id': 'cmd-1',
      'type': 'syncQueue',
      'payload': {'value': 10}
    });

    expect(command.id, 'cmd-1');
    expect(command.type, RemoteCommandType.syncQueue);
    expect(command.payload?['value'], 10);
  });
}
