# Unit Testing

## Testing Locus Features

Locus provides a comprehensive mock implementation for testing without native platform calls.

## Setup

Import the mock package:

```dart
import 'package:locus/locus.dart';
import 'package:locus/testing.dart';
```

## Using Mock Locus

Replace real Locus with mock in tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import 'package:locus/testing.dart';

void main() {
  late MockLocus mock;

  setUp(() {
    mock = MockLocus();
  });

  test('location tracking works', () async {
    // Simulate location update
    mock.addLocation(Location(
      coords: Coords(latitude: 37.7749, longitude: -122.4194),
      timestamp: DateTime.now(),
      accuracy: 10,
      speedAccuracy: 0,
      speed: 0,
    ));

    // Verify location was recorded
    expect(mock.locations, isNotEmpty);
  });

  test('geofence triggers events', () async {
    // Create geofence
    final geofence = Geofence(
      id: 'test',
      latitude: 37.7749,
      longitude: -122.4194,
      radius: 100,
    );

    // Add to mock
    await mock.geofencing.add(geofence);

    // Simulate entry
    mock.triggerGeofenceEvent(
      GeofenceEvent.enter(geofence: geofence, timestamp: DateTime.now()),
    );

    // Verify event was triggered
    expect(mock.geofenceEvents, isNotEmpty);
  });
}
```

## Simulating Scenarios

### Simulate Location Updates

```dart
mock.addLocation(Location(
  coords: Coords(latitude: 40.7128, longitude: -74.0060),
  timestamp: DateTime.now(),
  accuracy: 5,
));
```

### Simulate Geofence Events

```dart
mock.triggerGeofenceEvent(
  GeofenceEvent.enter(geofence: geofence, timestamp: DateTime.now()),
);

mock.triggerGeofenceEvent(
  GeofenceEvent.exit(geofence: geofence, timestamp: DateTime.now()),
);
```

### Simulate Battery Changes

```dart
mock.battery.updateState(PowerState(
  level: 0.15,
  isLow: true,
  isCharging: false,
));
```

### Simulate Activity Changes

```dart
mock.activity.updateActivity(Activity.walking);
mock.activity.updateActivity(Activity.stationary);
```

## Assertions

Test SDK behavior with custom assertions:

```dart
test('respects privacy zones', () async {
  // Setup
  final zone = PrivacyZone(
    id: 'home',
    latitude: 37.7749,
    longitude: -122.4194,
    radius: 100,
  );
  
  await mock.privacy.add(zone);

  // Simulate location inside zone
  mock.addLocation(Location(
    coords: Coords(latitude: 37.7749, longitude: -122.4194),
    timestamp: DateTime.now(),
    accuracy: 5,
  ));

  // Verify location was filtered
  expect(mock.publicLocations, isEmpty);
});
```

## Testing Async Operations

Properly handle async SDK calls:

```dart
test('initializes locus', () async {
  await mock.ready();
  
  final isStarted = await mock.start();
  expect(isStarted, isTrue);
});
```

## Coverage

Run tests with coverage:

```bash
flutter test --coverage
```

View coverage report:

```bash
lcov --list coverage/lcov.info
```

**Next:** [Contributing](../../CONTRIBUTING.md)
