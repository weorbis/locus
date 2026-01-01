# Locus

[![License: PolyForm Small Business](https://img.shields.io/badge/license-PolyForm%20Small%20Business-blue)](LICENSE)

A background geolocation SDK for Flutter providing persistent tracking, motion activity recognition, geofencing, and automated data synchronization for Android and iOS.

## Features

- **Continuous Tracking**: Reliable background location updates with configurable accuracy and distance filters.
- **Motion Recognition**: Detects physical activities such as walking, running, driving, and stationary states.
- **Native Geofencing**: High-performance entry, exit, and dwell event detection.
- **Automated Sync**: Built-in HTTP synchronization with configurable retry logic and exponential backoff.
- **Battery Optimization**: Adaptive tracking based on speed and battery level to minimize power consumption.
- **Offline Reliability**: Persistent SQLite storage on iOS and local storage on Android to prevent data loss.
- **Headless Execution**: Support for background events even when the application is terminated.
- **Project Tooling**: CLI utilities for automated project setup and configuration diagnostics.

## Platform Support

| Platform | Minimum Version      |
| :------- | :------------------- |
| Android  | API 26 (Android 8.0) |
| iOS      | iOS 14.0             |

## Installation

Add `locus` to your `pubspec.yaml`:

```yaml
dependencies:
  locus: ^1.1.0
```

### Automated Setup

Locus provides a CLI tool to automate the configuration of native permissions and project settings:

```bash
dart run locus:setup
```

To verify your environment:

```bash
dart run locus:doctor
```

## Quick Start

### 1. Request Permissions

```dart
import 'package:locus/locus.dart';

final granted = await Locus.requestPermission();
```

### 2. Basic Configuration

Initialize the SDK with your desired tracking parameters:

```dart
await Locus.ready(Config.balanced(
  url: 'https://api.yourservice.com/locations',
  notification: NotificationConfig(
    title: 'Location Service',
    text: 'Tracking is active',
  ),
));

await Locus.start();
```

Or use a preset for quick setup:

```dart
// Fitness/High Accuracy
await Locus.ready(Config.fitness());

// Low Power/Passive
await Locus.ready(Config.passive());
```

````

### 3. Handle Events

Subscribe to location updates and platform events:

```dart
Locus.onLocation((location) {
  print('Location: ${location.coords.latitude}, ${location.coords.longitude}');
});

Locus.onMotionChange((location) {
  print('Is Moving: ${location.isMoving}');
});
````

## Advanced Usage

### Adaptive Tracking

Optimize battery usage by automatically adjusting tracking parameters based on the device state:

```dart
await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);
```

### Geofencing

Register geofences directly through the SDK:

```dart
await Locus.addGeofence(const Geofence(
  identifier: 'office_zone',
  radius: 100,
  latitude: 37.7749,
  longitude: -122.4194,
  notifyOnEntry: true,
  notifyOnExit: true,
));
```

### Custom Payloads

Enqueue custom data to be synchronized along with location updates:

```dart
await Locus.enqueue({
  'event_type': 'check_in',
  'user_id': 'user_123',
});
```

### Custom Sync Body (Advanced)

For backends that require a specific JSON structure (e.g., a wrapper object with metadata), use the sync body builder:

```dart
// Set a custom body builder
Locus.setSyncBodyBuilder((locations, extras) async {
  return {
    'ownerId': extras['ownerId'],
    'taskId': extras['taskId'],
    'driverId': extras['driverId'],
    'polygons': locations.map((l) => {
      'lat': l.coords.latitude,
      'lng': l.coords.longitude,
      'speed': l.coords.speed,
      'timestamp': l.timestamp.toIso8601String(),
    }).toList(),
  };
});

// Configure with your metadata in extras
await Locus.ready(Config.balanced(
  url: 'https://api.yourservice.com/v1/tracking',
  extras: {
    'ownerId': 'owner_123',
    'taskId': 'task_456',
    'driverId': 'driver_789',
  },
));
```

For headless (background) operation, register a top-level function:

```dart
@pragma('vm:entry-point')
Future<JsonMap> buildSyncBody(SyncBodyContext context) async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'ownerId': prefs.getString('ownerId') ?? '',
    'locations': context.locations.map((l) => l.toJson()).toList(),
  };
}

// In main()
await Locus.registerHeadlessSyncBodyBuilder(buildSyncBody);
```

### Testing

Locus is designed to be testable. You can inject a mock instance in your tests:

```dart
// In your test file
void main() {
  setUp(() {
    Locus.setMockInstance(MockLocus());
  });

  test('tracking starts correctly', () async {
    await Locus.start();
    // Assert against your mock
  });
}
```

### Production Features

**Structured Logs:**

Retrieve structured logs (backed by SQLite) for debugging in production:

```dart
final logs = await Locus.getLog();
for (final entry in logs) {
  print('[${entry.level}] ${entry.message}');
}
```

**Permission Workflow:**

Use the built-in assistant to handle complex permission flows (Location -> Background -> Notification) with rationales:

```dart
final result = await PermissionAssistant.requestBackgroundWorkflow(
  config: config,
  delegate: PermissionFlowDelegate(
    onShowRationale: (rationale) async {
       // Show your UI dialog here
       return true; // User agreed
    },
    onOpenSettings: () async {
      // Prompt user to open settings
    },
  ),
);
```

**Device Optimization:**

Detect if the app is being stifled by aggressive OEM battery savers (Android):

```dart
final isIgnored = await DeviceOptimizationService.isIgnoringBatteryOptimizations();
if (!isIgnored) {
  // Direct user to instructions for their specific device manufacturer
  await DeviceOptimizationService.showManufacturerInstructions();
}
```

```

## License

This project is licensed under the **PolyForm Small Business License 1.0.0**. It is free for individuals and organizations with less than $250,000 in annual revenue. See the [LICENSE](LICENSE) and [LICENSING.md](LICENSING.md) files for details.

## Related Resources

- [Official Documentation](https://pub.dev/documentation/locus/latest/)
- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
```
