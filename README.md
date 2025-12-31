# Locus Background Geolocation

[![CI](https://github.com/koksalmehmet/locus/actions/workflows/ci.yml/badge.svg)](https://github.com/koksalmehmet/locus/actions/workflows/ci.yml)
[![License: Locus Community](https://img.shields.io/badge/license-Locus%20Community-blue)](LICENSE)

A Flutter background geolocation SDK for Android and iOS. This package provides continuous location tracking, motion/activity updates, geofencing, schedule-based tracking, and HTTP auto-sync so you can build apps with background location features without a paid license.

---

## Features

- Continuous location tracking with motion state changes.
- Activity recognition updates (walking, running, in-vehicle, etc.).
- Geofencing with enter/exit events and stored geofence management.
- Configurable accuracy, distance filters, and update intervals.
- Optional HTTP auto-sync with custom headers and params.
- Batch sync with persisted locations when enabled.
- Configurable HTTP retries with exponential backoff.
- Odometer tracking and basic log capture.
- Foreground service notification controls on Android.
- Connectivity, power-save, enabled-change, and geofences-change events.
- Heartbeat events (interval-based) and schedule windows (HH:mm-HH:mm).
- Headless execution with start-on-boot (Android) and background relaunch handling.
- Motion tuning: stationary radius and motion trigger/stop timeouts.
- Log levels with basic retention (`logMaxDays`).
- Activity filters (`triggerActivities`), and state diagnostics via `getState()`.
- Config presets for common tracking profiles.
- Location anomaly detection helpers for implausible jumps.
- Offline-first queue for custom payload sync with idempotency.
- Trip lifecycle events (start/update/end) with route deviation detection.
- Adaptive tracking profiles for job states (off-duty/standby/en-route/arrived).
- Geofence workflows with sequencing and cooldown enforcement.
- Diagnostics snapshot and remote command helpers.
- Location quality scoring with spoof-suspicion flags.
- **Battery optimization** with adaptive tracking, sync policies, and power state monitoring.
- **Speed-based GPS tuning** to reduce updates when stationary or walking.
- **Network-aware sync policies** for WiFi, cellular, and metered connections.
- **Battery benchmarking** for measuring power consumption during testing.
- **Enhanced spoof detection** with multi-factor analysis and confidence scoring.
- **Significant location changes** for ultra-low power monitoring (~500m movements).
- **Error recovery API** with automatic retries, exponential backoff, and custom handlers.

---

## Platform Support

| Platform | Minimum Version      |
| -------- | -------------------- |
| Android  | API 26 (Android 8.0) |
| iOS      | iOS 14.0             |

---

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  locus: ^1.0.0
```

Then run `flutter pub get`.

### Quick Setup with CLI

After adding the package, run the setup wizard to automatically configure your Android and iOS project:

```bash
dart run locus:setup
```

To verify your configuration is correct:

```bash
dart run locus:doctor
```

If issues are found, the doctor can auto-fix most of them:

```bash
dart run locus:doctor --fix
```

---

## CLI Tools

Locus includes command-line tools to simplify project setup and debugging:

### Setup Wizard

```bash
dart run locus:setup [options]

Options:
  --android-only       Only configure Android
  --ios-only           Only configure iOS
  --with-activity      Include activity recognition permissions
  -h, --help           Show usage information
```

The setup wizard automatically:

- Adds required permissions to `AndroidManifest.xml`
- Configures `Info.plist` with location usage descriptions
- Adds `UIBackgroundModes` for background location
- Checks `minSdkVersion` and iOS deployment target

### Doctor Command

```bash
dart run locus:doctor [options]

Options:
  --fix                Attempt to auto-fix any issues found
  -h, --help           Show usage information
```

The doctor command checks:

- All required Android permissions
- Android `minSdkVersion >= 26`
- iOS location usage description keys
- iOS `UIBackgroundModes` contains `location`
- iOS deployment target >= 14.0

---

## Configuration

### Android

The plugin declares required permissions and components via manifest merging. For Android 10+ you must request runtime background location and activity recognition permissions.

If you need to override or explicitly declare them, add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### iOS

Add the following keys to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to track your route.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs background location access to track your route.</string>
<key>NSMotionUsageDescription</key>
<string>This app uses motion data to improve activity detection.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>dev.locus.motionDetector.refresh</string>
</array>
```

If you override `bgTaskId` in `Config`, make sure the same identifier is listed in `BGTaskSchedulerPermittedIdentifiers`.

---

## Usage

### 1. Request Permissions

```dart
import 'package:locus/locus.dart';

final granted = await Locus.requestPermission();
if (!granted) {
  // Handle denied permissions.
}
```

### 2. Configure and Start Tracking

```dart
final state = await Locus.ready(const Config(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 25,
  heartbeatInterval: 60,
  activityRecognitionInterval: 10000,
  stopTimeout: 5,
  stationaryRadius: 25,
  motionTriggerDelay: 15000,
  enableHeadless: true,
  startOnBoot: true,
  stopOnTerminate: false,
  autoSync: true,
  disableAutoSyncOnCellular: true,
  maxRetry: 3,
  retryDelay: 5000,
  retryDelayMultiplier: 2.0,
  maxRetryDelay: 60000,
  logLevel: LogLevel.info,
  logMaxDays: 7,
  url: 'https://example.com/locations',
  notification: NotificationConfig(
    title: 'Tracking enabled',
    text: 'Locus is tracking your location',
    actions: ['PAUSE', 'STOP'],
  ),
));

if (!state.enabled) {
  await Locus.start();
}
```

### 2a. Use Config Presets

```dart
final config = ConfigPresets.tracking.copyWith(
  url: 'https://example.com/locations',
  notification: const NotificationConfig(
    title: 'Tracking enabled',
    text: 'Locus is tracking your location',
  ),
);
await Locus.ready(config);
```

### 3. Subscribe to Events

```dart
final locationSub = Locus.onLocation((location) {
  print('Location: ${location.coords.latitude}, ${location.coords.longitude}');
});

final motionSub = Locus.onMotionChange((location) {
  print('Motion change: ${location.isMoving}');
});

final providerSub = Locus.onProviderChange((event) {
  print('Provider: ${event.authorizationStatus}');
});
```

### 3a. Detect Location Anomalies

```dart
Locus.onLocationAnomaly((anomaly) {
  print('Anomalous speed: ${anomaly.speedKph} kph');
});
```

### 3b. Queue Custom Payloads

```dart
final id = await Locus.enqueue({
  'event': 'tripstart',
  'tripId': 'trip-123',
});

await Locus.syncQueue();
```

### 3c. Trip Lifecycle Events

```dart
await Locus.startTrip(TripConfig(
  startOnMoving: true,
  route: const [
    RoutePoint(latitude: 37.42, longitude: -122.08),
    RoutePoint(latitude: 37.43, longitude: -122.09),
  ],
));

Locus.onTripEvent((event) {
  print('Trip event: ${event.type}');
});
```

### 3d. Adaptive Tracking Profiles

```dart
await Locus.setTrackingProfiles(
  {
    TrackingProfile.offDuty: ConfigPresets.lowPower,
    TrackingProfile.standby: ConfigPresets.balanced,
    TrackingProfile.enRoute: ConfigPresets.tracking,
    TrackingProfile.arrived: ConfigPresets.trail,
  },
  initialProfile: TrackingProfile.standby,
);

await Locus.setTrackingProfile(TrackingProfile.enRoute);
```

### 3e. Geofence Workflows

```dart
Locus.registerGeofenceWorkflows(const [
  GeofenceWorkflow(
    id: 'pickup_dropoff',
    steps: [
      GeofenceWorkflowStep(
        id: 'pickup',
        geofenceIdentifier: 'pickup_zone',
        action: GeofenceAction.enter,
      ),
      GeofenceWorkflowStep(
        id: 'dropoff',
        geofenceIdentifier: 'dropoff_zone',
        action: GeofenceAction.enter,
      ),
    ],
  ),
]);

Locus.onWorkflowEvent((event) {
  print('Workflow ${event.workflowId} ${event.status}');
});
```

### 3f. Diagnostics + Remote Commands

```dart
final snapshot = await Locus.getDiagnostics();
print(snapshot.toMap());

await Locus.applyRemoteCommand(
  RemoteCommand(
    id: 'cmd-1',
    type: RemoteCommandType.syncQueue,
  ),
);
```

### 3g. Location Quality Scoring

```dart
Locus.onLocationQuality((quality) {
  print('Quality score: ${quality.overallScore}');
  if (quality.isSpoofSuspected) {
    print('Potential spoof detected');
  }
});
```

### 4. Geofencing

```dart
await Locus.addGeofence(const Geofence(
  identifier: 'home',
  radius: 100,
  latitude: 37.4219983,
  longitude: -122.084,
  notifyOnEntry: true,
  notifyOnExit: true,
));

final geofenceSub = Locus.onGeofence((event) {
  print('Geofence ${event.geofence.identifier} ${event.action}');
});
```

### 5. Stop Tracking

```dart
await Locus.stop();
await locationSub.cancel();
```

### 6. Schedule Windows

Schedule strings are in `HH:mm-HH:mm` format (24-hour), and can span midnight.

```dart
await Locus.ready(const Config(
  schedule: ['08:00-12:00', '13:00-18:00'],
));
await Locus.startSchedule();
```

### 7. Headless Tasks (Android)

Register a top-level callback to receive events while the app is terminated.

```dart
@pragma('vm:entry-point')
Future<void> backgroundGeolocationHeadlessTask(HeadlessEvent event) async {
  if (event.name == 'boot') {
    await Locus.ready(const Config(
      enableHeadless: true,
      startOnBoot: true,
      stopOnTerminate: false,
    ));
    await Locus.start();
  }
}

await Locus.registerHeadlessTask(
  backgroundGeolocationHeadlessTask,
);
```

### 8. Background Tasks

```dart
final taskId = await Locus.startBackgroundTask();
// Do short background work here.
await Locus.stopBackgroundTask(taskId);
```

### 9. Stored Locations

```dart
final stored = await Locus.getLocations(limit: 50);
await Locus.destroyLocations();
```

### 10. Diagnostics

```dart
final state = await Locus.getState();
```

---

## API Reference

For detailed documentation of all classes and methods, please refer to the [official documentation](https://pub.dev/documentation/locus/latest/).

### Core Classes

- `Locus`: Main SDK entry point.
- `Config`: Global configuration options.
- `Location`: Recorded location data point.
- `Geofence`: Geofence definition and state.
- `TripConfig`: configuration for the Trip Lifestyle engine.
- `MockLocus`: Testing mock for unit tests.
- `ConfigValidator`: Configuration validation utility.

---

## Testing

Locus provides testing utilities to enable unit testing without platform channels.

### MockLocus

```dart
import 'package:locus/locus.dart';

void main() {
  late MockLocus mock;

  setUp(() {
    mock = MockLocus();
  });

  tearDown(() {
    mock.dispose();
  });

  test('handles location updates', () async {
    final locations = <Location>[];
    mock.locationStream.listen(locations.add);

    // Emit a mock location
    mock.emitLocation(MockLocationExtension.mock(
      latitude: 37.4219,
      longitude: -122.084,
      speed: 15.5,
    ));

    await Future.delayed(Duration.zero);
    expect(locations.length, 1);
    expect(locations.first.coords.latitude, 37.4219);
  });

  test('tracks method calls', () async {
    await mock.ready(const Config());
    await mock.start();
    await mock.getCurrentPosition();

    expect(mock.methodCalls, ['ready', 'start', 'getCurrentPosition']);
  });
}
```

### Mock Extensions

```dart
// Create mock locations easily
final location = MockLocationExtension.mock(
  latitude: 40.7128,
  longitude: -74.006,
  activityType: ActivityType.inVehicle,
);

// Create mock geofences
final geofence = MockGeofenceExtension.mock(
  identifier: 'home',
  latitude: 37.4219,
  longitude: -122.084,
  radius: 100,
);
```

---

## Debug Overlay

Add a visual debug overlay during development to monitor location tracking:

```dart
import 'package:flutter/foundation.dart';
import 'package:locus/locus.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Stack(
        children: [
          YourMainWidget(),
          // Only show in debug mode
          if (kDebugMode)
            const LocusDebugOverlay(
              position: DebugOverlayPosition.bottomRight,
              expanded: false,
            ),
        ],
      ),
    );
  }
}
```

The debug overlay shows:

- Tracking status (ON/OFF)
- Current location coordinates
- Accuracy, speed, heading, altitude
- Activity recognition state
- Odometer distance
- Recent location history
- Start/Stop controls

---

## State-Agnostic Streams

Locus provides stream getters that work with any state management solution:

### With Riverpod

```dart
final locationProvider = StreamProvider.autoDispose((ref) {
  return Locus.locationStream;
});

final activityProvider = StreamProvider.autoDispose((ref) {
  return Locus.activityStream;
});
```

### With BLoC

```dart
class LocationBloc extends Bloc<LocationEvent, LocationState> {
  StreamSubscription? _subscription;

  LocationBloc() : super(LocationInitial()) {
    _subscription = Locus.locationStream.listen((location) {
      emit(LocationLoaded(location));
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
```

### Available Streams

| Stream               | Type                              | Description               |
| -------------------- | --------------------------------- | ------------------------- |
| `locationStream`     | `Stream<Location>`                | Location updates          |
| `motionChangeStream` | `Stream<Location>`                | Motion state changes      |
| `activityStream`     | `Stream<Activity>`                | Activity recognition      |
| `geofenceStream`     | `Stream<GeofenceEvent>`           | Geofence crossings        |
| `providerStream`     | `Stream<ProviderChangeEvent>`     | GPS/authorization changes |
| `connectivityStream` | `Stream<ConnectivityChangeEvent>` | Network changes           |
| `heartbeatStream`    | `Stream<Location>`                | Heartbeat pings           |
| `httpStream`         | `Stream<HttpEvent>`               | HTTP sync events          |
| `enabledStream`      | `Stream<bool>`                    | Tracking enabled/disabled |
| `powerSaveStream`    | `Stream<bool>`                    | Power save mode changes   |

---

## Dynamic HTTP Headers

Add authentication tokens or session IDs that change at runtime:

```dart
// Set a callback that provides fresh headers before each request
Locus.setHeadersCallback(() async {
  final token = await authService.getAccessToken();
  return {
    'Authorization': 'Bearer $token',
    'X-Session-Id': sessionId,
    'X-Device-Id': deviceId,
  };
});

// Manually refresh headers after login/token refresh
await Locus.refreshHeaders();

// Clear the callback on logout
Locus.clearHeadersCallback();
```

---

## Config Validation

Validate configurations before applying them:

```dart
final config = Config(
  distanceFilter: -10, // Invalid!
  autoSync: true,      // No URL set!
);

final result = ConfigValidator.validate(config);
if (!result.isValid) {
  for (final error in result.errors) {
    print('${error.field}: ${error.message}');
    if (error.suggestion != null) {
      print('  Suggestion: ${error.suggestion}');
    }
  }
}

// Or throw on invalid config
try {
  ConfigValidator.assertValid(config);
} on ConfigValidationException catch (e) {
  print('Invalid config: $e');
}
```

---

## Battery Optimization

Locus includes comprehensive battery optimization features to minimize power consumption while maintaining tracking quality.

### Adaptive Tracking

Automatically adjusts GPS settings based on speed, battery level, and motion state:

```dart
// Enable adaptive tracking
await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

// Or use aggressive power saving
await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);

// Custom configuration
await Locus.setAdaptiveTracking(AdaptiveTrackingConfig(
  enabled: true,
  speedTiers: SpeedTiers.driving,
  batteryThresholds: BatteryThresholds.conservative,
  stationaryGpsOff: true,
  stationaryDelay: Duration(seconds: 30),
  smartHeartbeat: true,
));
```

### Speed-Based Tuning

GPS polling frequency adjusts based on current speed:

| Speed (km/h)     | Update Interval | Distance Filter | Rationale           |
| ---------------- | --------------- | --------------- | ------------------- |
| 0 (stationary)   | 60s             | 50m             | Minimal movement    |
| <5 (walking)     | 20s             | 15m             | Slow movement       |
| 5-30 (city)      | 10s             | 10m             | Turns, stops        |
| 30-80 (suburban) | 7s              | 15m             | Consistent movement |
| >80 (highway)    | 5s              | 25m             | Need route accuracy |

### Sync Policies

Control when location data is synchronized based on network and battery:

```dart
// Use a preset policy
await Locus.setSyncPolicy(SyncPolicy.balanced);

// Custom policy
await Locus.setSyncPolicy(SyncPolicy(
  onWifi: SyncBehavior.immediate,
  onCellular: SyncBehavior.batch,
  onMetered: SyncBehavior.manual,
  batchSize: 50,
  batchInterval: Duration(minutes: 5),
  lowBatteryThreshold: 20,
  lowBatteryBehavior: SyncBehavior.manual,
));
```

### Power State Monitoring

React to battery and charging state changes:

```dart
// Get current power state
final power = await Locus.getPowerState();
print('Battery: ${power.batteryLevel}%');
print('Charging: ${power.isCharging}');
print('Power save: ${power.isPowerSaveMode}');

// Listen to power state changes
Locus.onPowerStateChange((event) {
  if (event.current.isCriticalBattery) {
    Locus.stop();
  }
});
```

### Battery Statistics

Monitor tracking impact on battery:

```dart
final stats = await Locus.getBatteryStats();
print('GPS active: ${stats.gpsOnTimePercent.toStringAsFixed(1)}%');
print('Updates: ${stats.locationUpdatesCount}');
print('Drain rate: ${stats.estimatedDrainPerHour}%/hr');
```

### Battery Benchmarking

Compare battery usage between configurations:

```dart
await Locus.startBatteryBenchmark();
// ... run tracking test ...
final result = await Locus.stopBatteryBenchmark();
print('Drain per hour: ${result?.drainPerHour.toStringAsFixed(1)}%/hr');
```

---

## Advanced Features

### Spoof Detection

Multi-factor detection of mock/spoofed locations:

```dart
// Enable spoof detection
await Locus.setSpoofDetection(SpoofDetectionConfig.balanced);

// High security mode
await Locus.setSpoofDetection(SpoofDetectionConfig(
  enabled: true,
  blockMockLocations: true,
  sensitivity: SpoofSensitivity.high,
  onSpoofDetected: (event) {
    logSecurityEvent('Spoof detected: ${event.factors}');
  },
));

// Manually analyze a location
final event = Locus.analyzeForSpoofing(location, isMockProvider: false);
if (event != null) {
  print('Confidence: ${event.confidence}');
  print('Factors: ${event.factors.map((f) => f.description)}');
}
```

Detection factors include: mock provider, impossible speed, altitude anomalies, repeated coordinates, timestamp mismatches, and more.

### Significant Location Changes

Ultra-low power monitoring for large movements (~500m):

```dart
// Start monitoring
await Locus.startSignificantChangeMonitoring(
  SignificantChangeConfig(
    minDisplacementMeters: 500,
    onSignificantChange: (location) {
      print('Significant move: ${location.coords.latitude}');
    },
  ),
);

// Or use preset for maximum battery savings
await Locus.startSignificantChangeMonitoring(
  SignificantChangeConfig.ultraLowPower,
);

// Check status
if (Locus.isSignificantChangeMonitoringActive) {
  // Listen to stream
  Locus.significantChangeStream?.listen((event) {
    print('Moved ${event.displacementMeters}m');
  });
}

// Stop monitoring
await Locus.stopSignificantChangeMonitoring();
```

### Error Recovery

Centralized error handling with automatic retries:

```dart
// Configure error handling
Locus.setErrorHandler(ErrorRecoveryConfig(
  maxRetries: 3,
  retryDelay: Duration(seconds: 5),
  retryBackoff: 2.0,
  onError: (error, context) {
    if (error.type == LocusErrorType.permissionDenied) {
      showPermissionDialog();
      return RecoveryAction.requestUserAction;
    }
    return error.suggestedRecovery ?? RecoveryAction.retry;
  },
  onExhausted: (error) {
    analytics.logError(error);
  },
));

// Handle errors manually
try {
  await Locus.start();
} catch (e) {
  final action = await Locus.handleError(LocusError.fromException(e));
  if (action == RecoveryAction.retry) {
    // Retry logic
  }
}

// Listen to error stream
Locus.errorStream?.listen((error) {
  print('Error: ${error.type} - ${error.message}');
});
```

Error types: `permissionDenied`, `servicesDisabled`, `locationTimeout`, `networkError`, `serviceDisconnected`, `configError`, and more.

---

## Example

A complete example application is available in the [example](example/) directory, demonstrating:

- Real-time location updates
- Geofence management
- Trip tracking
- Configuration UI
- Log viewing

To run the example:

```bash
cd example
flutter run
```

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](doc/CONTRIBUTING.md) for guidelines.

---

## Security

For security policy and vulnerability reporting, please see [SECURITY.md](doc/SECURITY.md).

---

## License

Locus Community License v1.0 (see `LICENSE` and [`doc/LICENSING.md`](doc/LICENSING.md)).

**Licensing summary**

- Individuals: free to use for any purpose, including commercial and closed-source.
- Enterprises (USD 250k+ revenue): free only if the part of the product that includes or links to this package is open-sourced under an OSI-approved license.
- Closed-source enterprise use requires a commercial license (contact: hello@mkoksal.dev).
