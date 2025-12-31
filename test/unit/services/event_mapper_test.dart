import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('maps activitychange payloads to Activity', () {
    final event = GeolocationEvent.fromMap({
      'type': 'activitychange',
      'data': {
        'activity': {'type': 'walking', 'confidence': 55}
      },
    });

    expect(event.type, EventType.activityChange);
    final activity = event.data as Activity;
    expect(activity.type, ActivityType.walking);
    expect(activity.confidence, 55);
  });

  test('maps location payloads with coords', () {
    final event = GeolocationEvent.fromMap({
      'type': 'location',
      'data': {
        'uuid': 'abc',
        'timestamp': DateTime.utc(2025, 1, 1).toIso8601String(),
        'coords': {
          'latitude': 1.0,
          'longitude': 2.0,
          'accuracy': 3.0,
        }
      },
    });

    expect(event.type, EventType.location);
    final location = event.data as Location;
    expect(location.coords.latitude, 1.0);
    expect(location.coords.longitude, 2.0);
  });
}
