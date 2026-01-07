# Frequently Asked Questions (FAQ)

Answers to common questions about the Locus Flutter background geolocation SDK.

## Table of Contents

1. [General Questions](#general-questions)
2. [Features & Capabilities](#features--capabilities)
3. [Configuration & Setup](#configuration--setup)
4. [Platform Differences](#platform-differences)
5. [Performance & Battery](#performance--battery)
6. [Privacy & Security](#privacy--security)
7. [Debugging & Troubleshooting](#debugging--troubleshooting)
8. [Limitations](#limitations)
9. [Best Practices](#best-practices)

---

## General Questions

### What is Locus?

Locus is a battle-tested background geolocation SDK for Flutter. It provides reliable location tracking, geofencing, motion recognition, and automated data synchronization for both Android and iOS platforms.

### Is Locus free?

Locus uses the **PolyForm Small Business License**. It's free for:
- Small businesses (under $1M annual revenue)
- Personal projects
- Open-source projects
- Educational use

Larger businesses require a commercial license. See [LICENSING.md](../../LICENSING.md) for details.

### Which platforms are supported?

- **Android**: API 21+ (Android 5.0 Lollipop)
- **iOS**: 11.0+

Desktop platforms (macOS, Windows, Linux) and web are not supported.

### Can I use Locus in production?

Yes! Locus is production-ready and battle-tested in fleet management, fitness, delivery, and social apps. It includes comprehensive error handling, offline persistence, and automatic recovery mechanisms.

### How is Locus different from other location plugins?

Locus is a **complete solution**, not just a location plugin:
- Built-in HTTP synchronization with retry logic
- Native geofencing (circular and polygon)
- Motion recognition and activity detection
- Trip tracking and route recording
- Privacy zones
- Adaptive battery optimization
- Offline SQLite persistence
- Headless background execution
- Comprehensive debugging tools

### Does Locus require a backend server?

No, Locus can work standalone. However, it provides optional HTTP sync for sending locations to your backend. You configure the URL and headers, and Locus handles retries, batching, and offline queueing.

---

## Features & Capabilities

### Can Locus track location when the app is killed?

**Android**: Yes, when configured with `stopOnTerminate: false` and `startOnBoot: true`. Tracking continues via foreground service.

**iOS**: Partially. iOS allows limited background processing after app termination, but cannot guarantee continuous tracking without the app running.

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  stopOnTerminate: false,
  startOnBoot: true,
  enableHeadless: true,
));
```

### Does Locus work offline?

Yes! Locations are persisted to SQLite when network is unavailable and automatically synced when connectivity resumes. Queue size is configurable:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  queueMaxDays: 7,
  queueMaxRecords: 10000,
));
```

### Can I customize the HTTP sync payload?

Yes, use a custom sync body builder:

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'device_id': extras['deviceId'],
    'user_id': extras['userId'],
    'batch': locations.map((l) => {
      'lat': l.coords.latitude,
      'lng': l.coords.longitude,
      'timestamp': l.timestamp.toIso8601String(),
      'accuracy': l.coords.accuracy,
    }).toList(),
  };
});
```

### How accurate are the locations?

Accuracy depends on configuration and device GPS:
- **Navigation preset**: 1-5 meters (highest accuracy)
- **Tracking preset**: 5-15 meters
- **Balanced preset**: 10-25 meters
- **Low power preset**: 50-100 meters

Real-world accuracy varies based on:
- GPS signal quality
- Device hardware
- Environment (urban canyon, indoors)
- Motion speed

### Can I detect if location is spoofed/mocked?

Yes, enable spoof detection:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  spoofDetection: SpoofDetectionConfig(
    action: SpoofDetectionAction.flag, // or ignore, stop
    strictMode: true,
  ),
));

Locus.location.stream.listen((location) {
  if (location.isSpoofed) {
    print('Warning: Location may be spoofed');
  }
});
```

### Does Locus support polygon geofences?

Yes! In addition to circular geofences, Locus supports polygon geofences with arbitrary vertices:

```dart
await Locus.geofencing.addPolygon(PolygonGeofence(
  identifier: 'campus',
  vertices: [
    GeoPoint(latitude: 37.7749, longitude: -122.4194),
    GeoPoint(latitude: 37.7759, longitude: -122.4184),
    GeoPoint(latitude: 37.7769, longitude: -122.4204),
  ],
));
```

### Can Locus detect trips automatically?

Yes, configure trip detection:

```dart
await Locus.trips.start(TripConfig(
  tripId: 'auto_trip',
  startOnMoving: true,
  startDistanceMeters: 50,
  stopOnStationary: true,
  stopTimeoutMinutes: 5,
));

Locus.trips.events.listen((event) {
  if (event.type == TripEventType.tripEnd) {
    print('Trip distance: ${event.summary?.distanceMeters}m');
  }
});
```

### Does Locus recognize motion activity?

Yes, Locus detects:
- `still` - Stationary
- `on_foot` - Walking
- `walking` - Walking (Android)
- `running` - Running
- `on_bicycle` - Cycling
- `in_vehicle` - Driving

```dart
Locus.location.stream.listen((location) {
  print('Activity: ${location.activity.type}');
  print('Confidence: ${location.activity.confidence}%');
});
```

---

## Configuration & Setup

### Which configuration preset should I use?

Choose based on your use case:

| Use Case | Preset | Accuracy | Battery Impact |
|----------|--------|----------|----------------|
| Fitness tracking, running apps | `ConfigPresets.trail` | Highest | High |
| Delivery, fleet tracking | `ConfigPresets.tracking` | High | Medium-High |
| Social, general tracking | `ConfigPresets.balanced` | Medium | Medium |
| Passive tracking | `ConfigPresets.lowPower` | Low | Low |

Customize any preset:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 25,
  url: 'https://api.example.com/locations',
));
```

### How do I enable background tracking?

**Android**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true,
  notification: NotificationConfig(
    title: 'Location Tracking',
    text: 'Tracking active',
  ),
));
```

**iOS**: Enable background modes in Xcode and Info.plist. See [Platform-Specific Setup](../setup/platform-specific.md).

### What is headless mode?

Headless mode allows your Dart code to execute when the app is terminated. Useful for:
- Processing location updates when app is killed
- Handling geofence events in background
- Custom sync logic

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  // Your background logic
}

await Locus.registerHeadlessTask(headlessCallback);
```

See [Headless Execution Guide](../advanced/headless-execution.md).

### How do I auto-sync locations to my server?

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json',
  },
  autoSync: true,
  batchSync: true,
  maxBatchSize: 50,
));
```

Locations are automatically synced in batches when queue reaches threshold.

---

## Platform Differences

### What are the key differences between Android and iOS?

| Feature | Android | iOS |
|---------|---------|-----|
| Max geofences | 100 | 20 |
| Background tracking after kill | Yes (with foreground service) | Limited |
| Headless execution | Yes | Limited |
| Motion activity | Google Play Services | Core Motion |
| Battery optimization | Aggressive (Doze mode) | Moderate |
| Permission flow | Multi-step (10+) | Two-step |
| Precise location | Default | Optional (iOS 14+) |

### How do background permissions differ?

**Android 10+**: Three-step process
1. Grant "While using app"
2. Grant "Allow all the time" (separate dialog)
3. Disable battery optimization (optional but recommended)

**iOS 13+**: Two-step process
1. Grant "When in Use"
2. Grant "Always" (shown after some usage)

Use `PermissionAssistant` for guided flow:
```dart
await PermissionAssistant.requestBackgroundWorkflow(
  config: myConfig,
  delegate: MyPermissionDelegate(),
);
```

### Why does iOS show a blue location indicator?

iOS 13+ shows a blue bar when app uses background location. This is a privacy indicator.

You can hide it (not recommended for transparency):
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  showsBackgroundLocationIndicator: false,
));
```

### Can I use more geofences on iOS?

No, iOS has a hard limit of 20 geofences. Solutions:
- Use larger geofence radii
- Dynamically swap geofences based on user location
- Use polygon geofences to cover larger areas

---

## Performance & Battery

### How much battery does Locus use?

Depends on configuration:

| Preset | Typical Battery Drain |
|--------|----------------------|
| `trail` | 10-20%/hour |
| `tracking` | 5-10%/hour |
| `balanced` | 2-5%/hour |
| `lowPower` | 0.5-2%/hour |

Factors affecting battery:
- GPS vs network location
- Update frequency (`distanceFilter`)
- Desired accuracy
- Motion activity
- Background vs foreground

### How can I reduce battery consumption?

1. **Use adaptive tracking**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  adaptiveTracking: AdaptiveTrackingConfig.balanced,
));
```

2. **Enable stop detection**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  stopTimeout: 5, // Power down after 5 minutes stationary
));
```

3. **Increase distance filter**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 100, // Only update every 100 meters
));
```

4. **Lower desired accuracy**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.low, // Use cell/WiFi instead of GPS
));
```

5. **Use tracking profiles**:
```dart
await Locus.setTrackingProfiles({
  TrackingProfile.standby: ConfigPresets.lowPower,
  TrackingProfile.enRoute: ConfigPresets.balanced,
});
```

### How do I estimate remaining tracking time?

```dart
final runway = await Locus.battery.estimateRunway();
print('Estimated hours remaining: ${runway.hours}');
print('Current drain: ${runway.drainRatePerHour}%/hour');

if (runway.hours < 2) {
  // Switch to low-power mode
  await Locus.switchProfile(TrackingProfile.standby);
}
```

### Does Locus track while device is sleeping?

**Android**: Yes, when using a foreground service.

**iOS**: Limited. iOS restricts background processing to save battery. Significant location changes are still detected.

### What is adaptive tracking?

Adaptive tracking automatically adjusts location accuracy and update frequency based on:
- Battery level
- Charging state
- Motion activity (stationary, walking, driving)
- Speed

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  adaptiveTracking: AdaptiveTrackingConfig(
    speedTiers: SpeedTiers.driving,
    batteryThresholds: BatteryThresholds.conservative,
    stationaryGpsOff: true,
  ),
));
```

---

## Privacy & Security

### How does Locus handle user privacy?

Locus provides **Privacy Zones** to exclude or obfuscate locations in sensitive areas:

```dart
// Exclude home location completely
await Locus.privacy.add(PrivacyZone.create(
  identifier: 'home',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 150,
  action: PrivacyZoneAction.exclude,
));

// Obfuscate work location
await Locus.privacy.add(PrivacyZone.create(
  identifier: 'work',
  latitude: 37.7849,
  longitude: -122.4094,
  radius: 200,
  action: PrivacyZoneAction.obfuscate,
  obfuscationRadius: 100,
));
```

### Is location data stored locally?

Yes, locations are persisted to SQLite for offline reliability. Storage duration is configurable:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  maxDaysToPersist: 7,
  maxRecordsToPersist: 10000,
));
```

### Can I encrypt location data?

Locus stores data in plain SQLite. For encryption:
1. Use Flutter's `sqflite_cipher` or similar
2. Encrypt location payload before sending to server
3. Use secure storage for sensitive extras

### How do I comply with GDPR?

1. **Request explicit consent** before tracking
2. **Provide clear privacy policy** explaining data usage
3. **Allow users to delete data**:
```dart
await Locus.clearDatabase();
```
4. **Use privacy zones** for sensitive locations
5. **Allow opt-out** at any time:
```dart
await Locus.stop();
await Locus.destroy();
```

### Can I anonymize location data?

Yes, several approaches:
- Remove or hash device identifiers in `extras`
- Use privacy zones to obfuscate sensitive areas
- Reduce location precision before sending to server
- Implement custom sync builder with data anonymization

---

## Debugging & Troubleshooting

### How do I enable debug logging?

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  logLevel: LogLevel.verbose,
));
```

View logs:
```dart
final logs = await Locus.getLog();
for (final entry in logs) {
  print('[${entry.level}] ${entry.message}');
}
```

### How do I test location tracking?

**Option 1: Use MockLocus**
```dart
import 'package:locus/testing.dart';

setUp(() {
  Locus.setMockInstance(MockLocus());
});

test('location tracking', () async {
  final mock = Locus.instance as MockLocus;
  mock.simulateLocation(testLocation);
  // Assertions
});
```

**Option 2: Simulator/Emulator**
- **Android Studio**: Extended controls → Location
- **Xcode**: Debug → Simulate Location

**Option 3: Real device** with GPS spoofing apps (for testing only)

### Why aren't location updates being received?

See comprehensive [Troubleshooting Guide](troubleshooting.md#location-updates-not-received).

Common causes:
- Permissions not granted
- Location services disabled
- High `distanceFilter`
- Stop detection active
- GPS signal poor

### How do I debug geofence issues?

1. **Verify geofence is registered**:
```dart
final exists = await Locus.geofencing.exists('my_geofence');
```

2. **Check geofence limits**: Android (100), iOS (20)

3. **Enable high-accuracy mode**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  geofenceModeHighAccuracy: true,
));
```

4. **Use debug overlay**:
```dart
LocusDebugOverlay()
```

### How can I monitor SDK health?

```dart
// Get diagnostics snapshot
final diagnostics = await Locus.getDiagnostics();
print('State: ${diagnostics.state}');
print('Queue size: ${diagnostics.queue.length}');
print('Last location: ${diagnostics.lastLocation}');

// Monitor errors
Locus.errors.listen((error) {
  print('Error: ${error.type} - ${error.message}');
});
```

---

## Limitations

### What are the geofence limits?

- **Android**: 100 circular or polygon geofences
- **iOS**: 20 circular geofences (polygons count toward this limit)

### Can I track indoor locations?

Locus relies on GPS, cell towers, and WiFi. Indoor accuracy is typically 20-50 meters. For better indoor accuracy, consider beacon-based solutions.

### Does Locus work on web or desktop?

No, Locus only supports mobile platforms (Android, iOS). Web and desktop don't have equivalent native geolocation APIs.

### Can I use Locus in a background isolate?

No, Locus communicates with native platform code via method channels, which require the main isolate. Use headless mode for background execution.

### What is the minimum update interval?

**Android**: ~1 second (1000ms) for `locationUpdateInterval`
**iOS**: ~1 second

More frequent updates may drain battery significantly.

### Can I customize the notification on Android?

Yes:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  notification: NotificationConfig(
    title: 'Tracking Active',
    text: 'App is monitoring your location',
    color: '#FF0000',
    smallIcon: 'ic_notification',
    largeIcon: 'ic_large_notification',
    priority: 2, // HIGH
    channelName: 'Location Tracking',
  ),
));
```

---

## Best Practices

### Should I use autoSync or manual sync?

**Use autoSync** if:
- You want locations sent immediately or in batches
- Network availability is generally good
- You don't need custom sync logic

**Use manual sync** if:
- You need full control over sync timing
- You batch with other API calls
- You implement custom retry logic

```dart
// Auto sync
await Locus.ready(ConfigPresets.balanced.copyWith(
  autoSync: true,
  batchSync: true,
));

// Manual sync
await Locus.sync.now();
```

### How often should I call getCurrentPosition()?

Avoid calling `getCurrentPosition()` repeatedly. Instead, subscribe to the location stream:

```dart
// ❌ Don't do this
Timer.periodic(Duration(seconds: 10), (timer) async {
  final location = await Locus.location.getCurrentPosition();
});

// ✅ Do this
Locus.location.stream.listen((location) {
  // Process location
});
```

### Should I use stop detection?

**Enable stop detection** if:
- Battery life is critical
- User is frequently stationary
- You're okay with delayed updates after stopping

**Disable stop detection** if:
- You need consistent update intervals
- Real-time tracking is critical
- User is rarely stationary

### When should I use headless mode?

Use headless mode when:
- You need background processing after app termination
- You handle geofence events while app is killed
- You implement custom sync logic in background

**Note**: iOS has limited headless capabilities.

### How do I handle permission denials?

1. **Show rationale before requesting**:
```dart
await showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Location Permission'),
    content: Text('We need your location to track trips...'),
  ),
);

final granted = await Locus.requestPermission();
```

2. **Handle denial gracefully**:
```dart
if (!granted) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Permission Required'),
      content: Text('Location tracking requires permission.'),
      actions: [
        TextButton(
          onPressed: () => Locus.openSettings(),
          child: Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

### Should I validate location accuracy?

Yes, especially for critical applications:
```dart
Locus.location.stream.listen((location) {
  if (location.coords.accuracy > 50) {
    // Poor accuracy, consider discarding
    print('Warning: Accuracy ${location.coords.accuracy}m');
    return;
  }
  
  // Use location
  processLocation(location);
});
```

---

## Still Have Questions?

- **Check the documentation**: [Full Documentation Index](../DOCUMENTATION_INDEX.md)
- **Search existing issues**: [GitHub Issues](https://github.com/koksalmehmet/locus/issues)
- **Create a new issue**: Provide details, logs, and reproduction steps
- **Review examples**: Check `example/` directory in the repository

---

**Related Documentation:**
- [Troubleshooting Guide](troubleshooting.md)
- [Error Codes Reference](../api/error-codes.md)
- [Configuration Reference](../core/configuration-reference.md)
- [Best Practices](../guides/quickstart.md)
