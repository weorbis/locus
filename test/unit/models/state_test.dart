import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('parses geolocation state with odometer and location', () {
    final state = GeolocationState.fromMap({
      'enabled': true,
      'isMoving': false,
      'odometer': 123.4,
      'location': {
        'uuid': 'loc-1',
        'timestamp': DateTime.utc(2025, 1, 2).toIso8601String(),
        'coords': {
          'latitude': 12.34,
          'longitude': 56.78,
          'accuracy': 5.0,
        },
        'activity': {'type': 'walking', 'confidence': 80},
      }
    });

    expect(state.enabled, true);
    expect(state.isMoving, false);
    expect(state.odometer, 123.4);
    expect(state.location?.coords.latitude, 12.34);
    expect(state.location?.activity?.type, ActivityType.walking);
  });

  test('maps activitychange event payload to Activity', () {
    final event = GeolocationEvent.fromMap({
      'type': 'activitychange',
      'data': {
        'activity': {'type': 'running', 'confidence': 90}
      }
    });

    expect(event.type, EventType.activityChange);
    final activity = event.data as Activity;
    expect(activity.type, ActivityType.running);
    expect(activity.confidence, 90);
  });
}
