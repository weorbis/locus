import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('geofence round-trip preserves fields', () {
    const geofence = Geofence(
      identifier: 'office',
      radius: 120.5,
      latitude: 51.5,
      longitude: -0.1,
      notifyOnEntry: true,
      notifyOnExit: false,
      notifyOnDwell: true,
      loiteringDelay: 300000,
      extras: {'color': 'blue'},
    );

    final map = geofence.toMap();
    final restored = Geofence.fromMap(map);

    expect(restored.identifier, 'office');
    expect(restored.radius, 120.5);
    expect(restored.notifyOnExit, false);
    expect(restored.loiteringDelay, 300000);
    expect(restored.extras?['color'], 'blue');
  });

  test('geofence event preserves location data', () {
    final event = GeofenceEvent.fromMap({
      'geofence': {
        'identifier': 'park',
        'radius': 80,
        'latitude': 40.0,
        'longitude': -70.0,
        'notifyOnEntry': true,
        'notifyOnExit': true,
        'notifyOnDwell': false,
      },
      'action': 'enter',
      'location': {
        'uuid': 'loc-2',
        'timestamp': DateTime.utc(2025, 2, 1).toIso8601String(),
        'coords': {
          'latitude': 40.0,
          'longitude': -70.0,
          'accuracy': 6.0,
        },
      },
    });

    expect(event.action, GeofenceAction.enter);
    expect(event.location?.coords.accuracy, 6.0);
  });

  test('provider change defaults to unknown values', () {
    final event = ProviderChangeEvent.fromMap({
      'enabled': false,
    });

    expect(event.availability, ProviderAvailability.unknown);
    expect(event.authorizationStatus, AuthorizationStatus.unknown);
    expect(event.accuracyAuthorization, LocationAccuracyAuthorization.unknown);
  });

  test('http event round-trip includes response payload', () {
    const httpEvent = HttpEvent(
      status: 201,
      ok: true,
      responseText: 'created',
      response: {'id': 42},
    );

    final map = httpEvent.toMap();
    final restored = HttpEvent.fromMap(map);

    expect(restored.status, 201);
    expect(restored.ok, true);
    expect(restored.response?['id'], 42);
  });

  test('headless event uses fallback type', () {
    final event = HeadlessEvent.fromMap({
      'data': {'value': 1}
    });
    expect(event.name, 'unknown');
    expect(event.data, {'value': 1});
  });

  test('location toMap includes extras and flags', () {
    final location = Location(
      uuid: 'loc-3',
      timestamp: DateTime.utc(2025, 3, 1),
      coords: const Coords(
        latitude: 10.5,
        longitude: 20.5,
        accuracy: 4.2,
      ),
      isMoving: true,
      isHeartbeat: false,
      extras: const {'note': 'sample'},
    );

    final map = location.toMap();
    expect(map['is_moving'], true);
    expect(map['is_heartbeat'], false);
    expect(map['extras'], {'note': 'sample'});
  });

  test('geolocation state includes extras and location', () {
    final state = GeolocationState.fromMap({
      'enabled': true,
      'isMoving': true,
      'extras': {'mode': 'trip'},
      'location': {
        'uuid': 'loc-4',
        'timestamp': DateTime.utc(2025, 3, 2).toIso8601String(),
        'coords': {
          'latitude': 11.0,
          'longitude': 21.0,
          'accuracy': 5.0,
        },
      },
    });

    expect(state.extras?['mode'], 'trip');
    expect(state.location?.coords.latitude, 11.0);
  });

  group('Geofence.isValid', () {
    test('returns true for valid geofence', () {
      const geofence = Geofence(
        identifier: 'test',
        radius: 100,
        latitude: 37.7749,
        longitude: -122.4194,
      );
      expect(geofence.isValid, isTrue);
    });

    test('returns false for empty identifier', () {
      const geofence = Geofence(
        identifier: '',
        radius: 100,
        latitude: 37.7749,
        longitude: -122.4194,
      );
      expect(geofence.isValid, isFalse);
    });

    test('returns false for zero radius', () {
      const geofence = Geofence(
        identifier: 'test',
        radius: 0,
        latitude: 37.7749,
        longitude: -122.4194,
      );
      expect(geofence.isValid, isFalse);
    });

    test('returns false for invalid latitude', () {
      const geofence = Geofence(
        identifier: 'test',
        radius: 100,
        latitude: 91,
        longitude: -122.4194,
      );
      expect(geofence.isValid, isFalse);
    });

    test('returns false for invalid longitude', () {
      const geofence = Geofence(
        identifier: 'test',
        radius: 100,
        latitude: 37.7749,
        longitude: 181,
      );
      expect(geofence.isValid, isFalse);
    });
  });

  group('Geofence.fromMap type safety', () {
    test('handles missing identifier gracefully', () {
      final geofence = Geofence.fromMap({
        'radius': 100,
        'latitude': 37.0,
        'longitude': -122.0,
      });
      expect(geofence.identifier, isEmpty);
      expect(geofence.isValid, isFalse);
    });

    test('handles non-numeric radius gracefully', () {
      final geofence = Geofence.fromMap({
        'identifier': 'test',
        'radius': 'invalid',
        'latitude': 37.0,
        'longitude': -122.0,
      });
      expect(geofence.radius, equals(0.0));
      expect(geofence.isValid, isFalse);
    });

    test('handles nested extras map', () {
      final geofence = Geofence.fromMap({
        'identifier': 'test',
        'radius': 100,
        'latitude': 37.0,
        'longitude': -122.0,
        'extras': {
          'key': 'value',
          'nested': {'a': 1}
        },
      });
      expect(geofence.extras, isNotNull);
      expect(geofence.extras!['key'], equals('value'));
    });
  });
}
