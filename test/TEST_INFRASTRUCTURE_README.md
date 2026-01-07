# Locus Test Infrastructure

Comprehensive test utilities and mocks for the locus Flutter package.

## Overview

This test infrastructure provides production-quality test utilities to make testing locus-based applications easy and reliable. It includes:

- **Factories** - Builder-pattern APIs for creating test data
- **Fixtures** - Pre-configured sample data
- **Helpers** - Async utilities and base test classes
- **Matchers** - Custom test matchers
- **Mocks** - Service mocks (use MockLocus from main package)

## Quick Start

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import '../helpers/helpers.dart';
import '../fixtures/fixtures.dart';

void main() {
  test('example test', () async {
    // Create a location
    final location = LocationFactory()
      .at(37.7749, -122.4194)
      .moving()
      .withAccuracy(10)
      .build();

    // Use fixtures
    final geofence = GeofenceFixtures.home();

    // Custom matchers
    expect(location, isLocationAt(37.7749, -122.4194));
    expect(location, isInsideGeofence(geofence));
  });
}
```

## Factories

### LocationFactory

Build custom locations with a fluent API:

```dart
// Simple location
final location = LocationFactory()
  .at(37.7749, -122.4194)
  .withAccuracy(10)
  .build();

// Moving location
final moving = LocationFactory()
  .at(37.7749, -122.4194)
  .moving()
  .withSpeed(5.0)
  .withActivityType(ActivityType.walking)
  .build();

// Create a route
final route = LocationFactory.route([
  (37.7749, -122.4194),
  (37.7750, -122.4195),
  (37.7751, -122.4196),
], speed: 5.0, interval: Duration(seconds: 5));

// Heartbeat sequence
final heartbeats = LocationFactory.stationarySequence(
  37.7749,
  -122.4194,
  count: 5,
  interval: Duration(minutes: 1),
);
```

### GeofenceFactory

Build custom geofences:

```dart
// Simple geofence
final geofence = GeofenceFactory()
  .named('home')
  .at(37.7749, -122.4194)
  .withRadius(100)
  .notifyOnEntry()
  .notifyOnExit()
  .build();

// Geofence around location
final location = LocationFixtures.sanFrancisco();
final geofence = GeofenceFactory.around(
  location,
  identifier: 'current-location',
  radius: 50,
);

// Preset sizes
final small = GeofenceFactory().named('store').small().build(); // 50m
final large = GeofenceFactory().named('city').large().build(); // 500m
```

### PolygonGeofenceFactory

Build polygon geofences:

```dart
// Custom polygon
final polygon = PolygonGeofenceFactory()
  .named('campus')
  .addVertex(37.42, -122.08)
  .addVertex(37.43, -122.08)
  .addVertex(37.43, -122.07)
  .addVertex(37.42, -122.07)
  .build();

// Rectangle
final rect = PolygonGeofenceFactory()
  .named('parking-lot')
  .rectangle(37.7749, -122.4194, 200, 100) // center, width, height
  .build();
```

### ConfigFactory

Build custom configurations:

```dart
// Preset configs
final highAccuracy = ConfigFactory().highAccuracy().build();
final balanced = ConfigFactory().balanced().build();
final lowPower = ConfigFactory().lowPower().build();

// Custom config
final config = ConfigFactory()
  .withAccuracy(DesiredAccuracy.high)
  .withDistanceFilter(10)
  .withUpdateInterval(5000)
  .enableHeadless()
  .withUrl('https://api.example.com/locations')
  .batchSync(maxBatchSize: 50)
  .build();
```

## Fixtures

Pre-configured sample data for common test scenarios:

### Location Fixtures

```dart
// Major cities
LocationFixtures.sanFrancisco(isMoving: false);
LocationFixtures.mountainView(isMoving: true, speed: 10.0);
LocationFixtures.newYork();
LocationFixtures.london();
LocationFixtures.tokyo();

// Special cases
LocationFixtures.highAccuracy(); // 3m accuracy
LocationFixtures.poorAccuracy(); // 50m accuracy
LocationFixtures.nullIsland(); // (0, 0)
```

### Geofence Fixtures

```dart
GeofenceFixtures.home();
GeofenceFixtures.office();
GeofenceFixtures.store();
GeofenceFixtures.cityZone();
GeofenceFixtures.airport();
```

### Config Fixtures

```dart
ConfigFixtures.highAccuracy();
ConfigFixtures.balanced();
ConfigFixtures.lowPower();
ConfigFixtures.passive();
ConfigFixtures.geofenceOnly();
```

### Activity & Battery Fixtures

```dart
ActivityFixtures.still();
ActivityFixtures.walking();
ActivityFixtures.running();
ActivityFixtures.inVehicle();

BatteryFixtures.full(charging: true);
BatteryFixtures.medium();
BatteryFixtures.low();
BatteryFixtures.critical();
```

## Async Helpers

### Wait for Stream Events

```dart
// Wait for a specific value
final location = await waitForStreamValue(
  mock.locationStream,
  (loc) => loc.coords.latitude > 37.0,
  timeout: Duration(seconds: 5),
);

// Wait for N events
final locations = await waitForStreamCount(
  mock.locationStream,
  count: 5,
  timeout: Duration(seconds: 10),
);

// Collect events for duration
final events = await collectStreamEvents(
  mock.locationStream,
  duration: Duration(seconds: 2),
);
```

### Polling

```dart
// Poll a condition
await pollUntil(
  () => mock.isReady,
  interval: Duration(milliseconds: 100),
  timeout: Duration(seconds: 5),
);

// Poll async condition
await pollUntilAsync(
  () async => (await mock.getState()).enabled,
  interval: Duration(milliseconds: 100),
  timeout: Duration(seconds: 5),
);
```

### Timeouts

```dart
// Wrap any future with timeout
final result = await waitForFuture(
  someOperation(),
  timeout: Duration(seconds: 5),
);

// Verify no events occur
await expectNoStreamEvents(
  mock.locationStream,
  duration: Duration(seconds: 2),
);
```

## Custom Matchers

Expressive assertions for locus models:

```dart
// Location matchers
expect(location, isLocationAt(37.7749, -122.4194));
expect(location, isLocationAt(37.7749, -122.4194, tolerance: 0.001));
expect(location, isMoving);
expect(location, isStationary);
expect(location, hasGoodAccuracy); // < 20m

// Geofence matchers
expect(geofence, hasIdentifier('home'));
expect(location, isInsideGeofence(geofence));

// Config matchers
expect(config, hasAccuracy(DesiredAccuracy.high));
```

## Base Test Classes

### ServiceTestGroup

Convenient wrapper for service tests:

```dart
serviceTestGroup<MyService>(
  'MyService',
  (getMock, getService) {
    test('does something', () {
      final mock = getMock();
      final service = getService();
      
      // Test logic here
    });
  },
  createService: (mock) => MyService(mock),
);
```

### BaseServiceTest

Extend for service unit tests:

```dart
class MyServiceTest extends BaseServiceTest {
  late MyService service;

  @override
  void additionalSetup() {
    service = MyService(mockLocus);
  }

  @override
  void additionalTearDown() {
    service.dispose();
  }
}

void main() {
  final testHarness = MyServiceTest();

  testHarness.serviceTest('test something', () async {
    // mockLocus is automatically available
    // setup and teardown handled automatically
  });
}
```

### BaseIntegrationTest

Extend for integration tests:

```dart
class MyIntegrationTest extends BaseIntegrationTest {
  @override
  Config createTestConfig() {
    return const Config(
      distanceFilter: 10,
      desiredAccuracy: DesiredAccuracy.high,
    );
  }
}

void main() {
  final testHarness = MyIntegrationTest();

  testHarness.integrationTest('integration test', () async {
    // mockLocus is initialized with testConfig
    // Full SDK integration available
  });
}
```

## MockLocus

The main package provides `MockLocus` which you should use for testing. It provides:

```dart
final mock = MockLocus();

// Emit events
mock.emitLocation(location);
mock.emitMotionChange(location);
mock.emitGeofenceEvent(event);
mock.emitHeartbeat(location);

// Simulate sequences
await mock.simulateLocationSequence([loc1, loc2, loc3]);

// State management
mock.setMockState(GeolocationState(...));
await mock.ready(config);
await mock.start();

// Geofences
await mock.addGeofence(geofence);
await mock.removeGeofence('home');

// Queue
await mock.enqueue({'data': 'value'});
await mock.clearQueue();

// Method tracking
expect(mock.methodCalls, contains('start'));
mock.clearMethodCalls();
```

## Complete Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

import '../helpers/helpers.dart';
import '../fixtures/fixtures.dart';

void main() {
  serviceTestGroup<LocationServiceImpl>(
    'LocationServiceImpl Integration',
    (getMock, getService) {
      test('tracks route correctly', () async {
        final mock = getMock();
        final service = getService();

        // Create a route
        final route = LocationFactory.route([
          (37.7749, -122.4194),
          (37.7750, -122.4195),
          (37.7751, -122.4196),
        ], interval: Duration(milliseconds: 100));

        // Emit route locations
        for (final location in route) {
          mock.emitLocation(location);
          await Future.delayed(Duration(milliseconds: 100));
        }

        // Wait for all locations to be processed
        await waitForStreamCount(
          service.stream,
          count: route.length,
        );

        // Get summary
        final summary = await service.getSummary();

        expect(summary.locationCount, route.length);
        expect(summary.totalDistanceMeters, greaterThan(0));
      });

      test('geofence triggers correctly', () async {
        final mock = getMock();
        
        // Add geofence
        final geofence = GeofenceFixtures.home();
        await mock.addGeofence(geofence);

        // Create location inside geofence
        final inside = LocationFactory()
          .at(geofence.latitude, geofence.longitude)
          .build();

        expect(inside, isInsideGeofence(geofence));

        // Simulate entering geofence
        mock.emitLocation(inside);

        // Wait for geofence event
        final event = await waitForStreamValue(
          mock.geofenceStream,
          (e) => e.action == GeofenceAction.enter,
        );

        expect(event.geofence, hasIdentifier('home'));
      });
    },
    createService: (mock) => LocationServiceImpl(() => mock),
  );
}
```

## Directory Structure

```
test/
├── fixtures/
│   └── fixtures.dart          # Sample data fixtures
├── helpers/
│   ├── async_helpers.dart     # Async test utilities
│   ├── base_test.dart         # Base test classes
│   ├── config_factory.dart    # Config builder
│   ├── geofence_factory.dart  # Geofence builder
│   ├── location_factory.dart  # Location builder
│   ├── test_matchers.dart     # Custom matchers
│   ├── helpers.dart           # Barrel file
│   └── usage_examples_test.dart  # Examples
└── mocks/
    └── services/
        └── services.dart      # Service mocks (use MockLocus instead)
```

## Tips & Best Practices

1. **Use Factories for Custom Data** - Factories provide type-safe, fluent APIs
2. **Use Fixtures for Common Cases** - Fixtures save time for standard scenarios
3. **Use Async Helpers** - Don't write custom stream waiting logic
4. **Use Custom Matchers** - Make assertions more readable
5. **Use Base Classes** - Reduce boilerplate in test setup/teardown
6. **Use MockLocus** - Complete mock of SDK behavior

## Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/helpers/usage_examples_test.dart

# Run with coverage
flutter test --coverage

# Run with verbose output
flutter test --verbose
```

## Contributing

When adding new test utilities:

1. Add appropriate documentation
2. Include usage examples
3. Follow existing patterns
4. Keep utilities focused and simple
5. Add tests for test utilities (meta-testing)

## License

Same as locus package - see LICENSE file.
