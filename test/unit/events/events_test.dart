import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('config toMap omits null values and maps enums', () {
    const config = Config(
      desiredAccuracy: DesiredAccuracy.high,
      distanceFilter: 25,
      autoSync: true,
      notification: NotificationConfig(
        title: 'Tracking',
        text: 'Background active',
      ),
    );

    final map = config.toMap();
    expect(map['desiredAccuracy'], 'high');
    expect(map['distanceFilter'], 25);
    expect(map['autoSync'], true);
    expect(map['notification'], {
      'title': 'Tracking',
      'text': 'Background active',
    });
    expect(map['maxRetry'], isNull);
    expect(map['heartbeatInterval'], isNull);
    expect(map['bgTaskId'], isNull);
    expect(map.containsKey('httpTimeout'), false);
  });

  test('parses activity payloads', () {
    final activity = Activity.fromMap({'type': 'walking', 'confidence': 72});
    expect(activity.type, ActivityType.walking);
    expect(activity.confidence, 72);
  });

  test('parses location payloads', () {
    final location = Location.fromMap({
      'uuid': 'abc',
      'timestamp': DateTime.utc(2025, 1, 1).toIso8601String(),
      'coords': {
        'latitude': 10.0,
        'longitude': 20.0,
        'accuracy': 5.5,
      },
      'activity': {'type': 'still', 'confidence': 98},
      'battery': {'level': 0.7, 'is_charging': true},
    });

    expect(location.uuid, 'abc');
    expect(location.coords.latitude, 10.0);
    expect(location.coords.longitude, 20.0);
    expect(location.activity?.type, ActivityType.still);
    expect(location.battery?.isCharging, true);
  });

  test('parses geofence events without location payloads', () {
    final event = GeofenceEvent.fromMap({
      'geofence': {
        'identifier': 'home',
        'radius': 100,
        'latitude': 10.0,
        'longitude': 20.0,
        'notifyOnEntry': true,
        'notifyOnExit': false,
        'notifyOnDwell': false,
      },
      'action': 'enter',
    });

    expect(event.geofence.identifier, 'home');
    expect(event.action, GeofenceAction.enter);
    expect(event.location, isNull);
  });

  test('parses connectivity and power save events', () {
    final connectivity = GeolocationEvent.fromMap({
      'type': 'connectivitychange',
      'data': {'connected': true, 'networkType': 'wifi'}
    });
    expect(connectivity.type, EventType.connectivityChange);
    final connectivityData = connectivity.data as ConnectivityChangeEvent;
    expect(connectivityData.connected, true);
    expect(connectivityData.networkType, 'wifi');

    final powerSave =
        GeolocationEvent.fromMap({'type': 'powersavechange', 'data': true});
    expect(powerSave.type, EventType.powerSaveChange);
    expect(powerSave.data, true);
  });

  group('PowerStateChangeEvent.fromMap type safety', () {
    test('handles missing previous state', () {
      final event = PowerStateChangeEvent.fromMap({
        'current': {'batteryLevel': 50, 'isCharging': false},
        'changeType': 'batteryLevel',
      });
      expect(event.previous.batteryLevel, equals(50)); // PowerState.unknown
      expect(event.current.batteryLevel, equals(50));
    });

    test('handles missing current state', () {
      final event = PowerStateChangeEvent.fromMap({
        'previous': {'batteryLevel': 80, 'isCharging': true},
        'changeType': 'chargingState',
      });
      expect(event.previous.batteryLevel, equals(80));
      expect(
          event.current.batteryLevel, equals(50)); // PowerState.unknown default
    });

    test('handles invalid timestamp gracefully', () {
      final event = PowerStateChangeEvent.fromMap({
        'previous': {'batteryLevel': 80, 'isCharging': true},
        'current': {'batteryLevel': 75, 'isCharging': false},
        'changeType': 'chargingState',
        'timestamp': 'not-a-valid-timestamp',
      });
      expect(event.timestamp, isNotNull);
      // Should not throw, uses DateTime.now() as fallback
    });
  });
}
