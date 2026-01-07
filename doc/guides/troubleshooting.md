# Troubleshooting Guide

This comprehensive guide addresses common issues, debugging techniques, and solutions for the Locus SDK. Use this guide to diagnose and resolve tracking, permission, background execution, and synchronization problems.

## Table of Contents

1. [Enabling Debug Mode](#enabling-debug-mode)
2. [Common Issues](#common-issues)
   - [Tracking Not Starting](#tracking-not-starting)
   - [Location Updates Not Received](#location-updates-not-received)
   - [Background Tracking Stops](#background-tracking-stops)
   - [Geofences Not Triggering](#geofences-not-triggering)
   - [Location Drift or Inaccuracy](#location-drift-or-inaccuracy)
   - [Battery Drain](#battery-drain)
   - [HTTP Sync Failures](#http-sync-failures)
   - [Permissions Issues](#permissions-issues)
3. [Platform-Specific Issues](#platform-specific-issues)
   - [Android Issues](#android-issues)
   - [iOS Issues](#ios-issues)
4. [Analyzing Logs](#analyzing-logs)
5. [Debug Overlay](#debug-overlay)
6. [Error Recovery](#error-recovery)

---

## Enabling Debug Mode

Enable verbose logging to diagnose issues:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  logLevel: LogLevel.verbose,
));
```

### Log Levels

- `LogLevel.off` - No logging
- `LogLevel.error` - Only errors
- `LogLevel.warning` - Warnings and errors
- `LogLevel.info` - General information (default)
- `LogLevel.debug` - Detailed debugging information
- `LogLevel.verbose` - Everything including platform events

### Accessing Logs

```dart
// Get all logs
final logs = await Locus.getLog();
for (final entry in logs) {
  print('[${entry.level}] ${entry.timestamp}: ${entry.message}');
}

// Get diagnostics snapshot
final diagnostics = await Locus.getDiagnostics();
print('Queue size: ${diagnostics.queue.length}');
print('State: ${diagnostics.state}');
```

---

## Common Issues

### Tracking Not Starting

#### Symptom
Calling `Locus.start()` completes successfully but no location updates are received.

#### Potential Causes & Solutions

**1. Permissions Not Granted**

Check permission status:

```dart
final status = await Locus.requestPermission();
if (!status) {
  print('Location permission denied');
}
```

Solution: Request permissions before starting tracking. See [Permissions Issues](#permissions-issues) below.

**2. Location Services Disabled**

```dart
final state = await Locus.getState();
if (state.locationServicesEnabled == false) {
  // Guide user to system settings
  print('Location services are disabled');
}
```

Solution: Prompt the user to enable location services in system settings.

**3. Locus Not Initialized**

```dart
try {
  await Locus.start();
} catch (e) {
  if (e is NotInitializedException) {
    print('Call Locus.ready() first');
  }
}
```

Solution: Always call `Locus.ready()` before any other Locus methods.

**4. Stop-Detection Preventing Updates**

If the device is stationary, Locus may enter low-power mode.

```dart
// Force an update
await Locus.location.changePace(true);
```

Solution: Configure `stopTimeout` or disable stop detection:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableStopDetection: true,
));
```

**5. Android Foreground Service Not Configured**

On Android, background tracking requires a foreground service with notification:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true,
  notification: NotificationConfig(
    title: 'Location Tracking',
    text: 'App is tracking your location',
    channelId: 'locus_tracking',
  ),
));
```

---

### Location Updates Not Received

#### Symptom
Tracking started successfully, but the location stream produces no events.

#### Solutions

**1. Subscribe to the Correct Stream**

```dart
// Correct: All location updates
Locus.location.stream.listen((location) {
  print('Location: ${location.coords.latitude}, ${location.coords.longitude}');
});

// Motion changes only (less frequent)
Locus.location.motionChanges.listen((location) {
  print('Motion changed: ${location.isMoving}');
});
```

**2. Check Distance Filter**

If `distanceFilter` is too high, you won't receive updates for small movements:

```dart
// Reduce distance filter for more frequent updates
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 10, // meters
));
```

**3. Check Update Interval**

On Android, `locationUpdateInterval` controls minimum time between updates:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  locationUpdateInterval: 5000, // 5 seconds (milliseconds)
));
```

**4. Verify GPS Signal**

Poor GPS signal can prevent location acquisition. Check accuracy:

```dart
Locus.location.stream.listen((location) {
  if (location.coords.accuracy > 50) {
    print('Warning: Poor GPS accuracy (${location.coords.accuracy}m)');
  }
});
```

Solution: Test outdoors with clear sky view.

**5. Check for Errors**

```dart
Locus.errors.listen((error) {
  print('Locus error: ${error.message}');
});
```

---

### Background Tracking Stops

#### Symptom
Tracking works while app is in foreground but stops when app is backgrounded or device is locked.

#### Android Solutions

**1. Battery Optimization Disabled**

Android may kill background services for battery optimization:

```dart
// Check if battery optimization is disabled
final state = await Locus.getState();
if (state.batteryOptimizationEnabled == true) {
  // Prompt user to disable battery optimization
  print('Battery optimization may stop background tracking');
}
```

Prompt the user to disable battery optimization for your app in system settings.

**2. Foreground Service Required**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true,
  notification: NotificationConfig(
    title: 'Tracking Active',
    text: 'App is tracking in background',
    priority: 2, // HIGH
    channelId: 'locus_tracking',
  ),
));
```

**3. Doze Mode Interference**

Android Doze mode restricts background activity. Use:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true,
  preventSuspend: true,
));
```

**4. App Task Removed**

Configure `stopOnTerminate`:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  stopOnTerminate: false, // Continue tracking after app is killed
  startOnBoot: true,      // Restart on device reboot
));
```

#### iOS Solutions

**1. Background Modes Not Enabled**

Verify in `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>
```

**2. Background Location Permission**

iOS requires "Always" permission for background tracking:

```dart
final status = await Locus.requestPermission();
// User must select "Always" in permission dialog
```

**3. iOS Background Task Identifier**

Configure background task ID:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  bgTaskId: 'com.yourapp.refresh',
));
```

Register in `Info.plist`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.yourapp.refresh</string>
</array>
```

**4. Prevent Auto-Pause**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  pausesLocationUpdatesAutomatically: false,
  preventSuspend: true,
));
```

---

### Geofences Not Triggering

#### Symptom
Geofences added successfully but enter/exit events are not received.

#### Solutions

**1. Start Geofence Monitoring**

Geofences may require explicit start:

```dart
await Locus.geofencing.add(geofence);
await Locus.start(); // Starts both tracking and geofencing
```

**2. Check Geofence Radius**

Minimum radius varies by platform:
- **Android**: 100 meters minimum
- **iOS**: 100 meters recommended

```dart
await Locus.geofencing.add(Geofence(
  identifier: 'office',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 150, // Use >= 100m
  notifyOnEntry: true,
  notifyOnExit: true,
));
```

**3. Verify Geofence Limit**

- **Android**: 100 geofences max
- **iOS**: 20 geofences max

```dart
final geofences = await Locus.geofencing.getAll();
print('Active geofences: ${geofences.length}');
```

**4. Subscribe to Events**

```dart
Locus.geofencing.events.listen((event) {
  print('Geofence ${event.geofence.identifier}: ${event.action}');
});
```

**5. Enable High-Accuracy Mode**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  geofenceModeHighAccuracy: true,
));
```

**6. Check Proximity Radius**

iOS geofences trigger slightly before/after boundary:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  geofenceProximityRadius: 50, // Start monitoring 50m early
));
```

**7. Verify Location Permission**

Geofencing requires background location permission on both platforms.

---

### Location Drift or Inaccuracy

#### Symptom
Locations are inaccurate, jump around, or drift while stationary.

#### Solutions

**1. Increase Desired Accuracy**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.navigation, // Highest accuracy
));
```

**2. Enable Speed Jump Filter**

Filters out impossible speed changes:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  speedJumpFilter: 50, // Reject locations requiring > 50 m/s speed
));
```

**3. Check Accuracy in Real-Time**

```dart
Locus.location.stream.listen((location) {
  if (location.coords.accuracy > 100) {
    print('Warning: Low accuracy ${location.coords.accuracy}m');
    // Optionally discard or flag the location
  }
});
```

**4. Enable Spoof Detection**

Detect and flag spoofed/mocked locations:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  spoofDetection: SpoofDetectionConfig(
    action: SpoofDetectionAction.flag,
    strictMode: true,
  ),
));
```

**5. Adjust Stationary Radius**

Prevents drift while stationary:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  stationaryRadius: 25, // meters
));
```

**6. Use Motion Activity**

Filter locations based on activity:

```dart
Locus.location.stream.listen((location) {
  if (location.activity.type == ActivityType.still && location.coords.speed > 5) {
    // Likely a GPS drift while stationary
  }
});
```

---

### Battery Drain

#### Symptom
Excessive battery consumption during tracking.

#### Solutions

**1. Use Battery-Optimized Presets**

```dart
// Lowest power consumption
await Locus.ready(ConfigPresets.lowPower);

// Balanced power/accuracy
await Locus.ready(ConfigPresets.balanced);
```

**2. Enable Adaptive Tracking**

Automatically adjusts tracking based on conditions:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  adaptiveTracking: AdaptiveTrackingConfig(
    speedTiers: SpeedTiers.driving,
    batteryThresholds: BatteryThresholds.conservative,
    stationaryGpsOff: true,
  ),
));
```

**3. Increase Distance Filter**

Reduce update frequency:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 100, // Only update every 100 meters
));
```

**4. Reduce Location Accuracy**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.low, // Use cell tower + WiFi
));
```

**5. Enable Stop Detection**

Power down GPS when stationary:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableStopDetection: false,
  stopTimeout: 5, // Stop after 5 minutes of no motion
));
```

**6. Monitor Battery Consumption**

```dart
final runway = await Locus.battery.estimateRunway();
print('Estimated hours remaining: ${runway.formattedDuration}');
print('Drain rate: ${runway.drainRatePerHour}%/hour');

if (runway.drainRatePerHour > 10) {
  print('Warning: High battery drain');
}
```

**7. Use Tracking Profiles**

Switch between profiles based on context:

```dart
await Locus.setTrackingProfiles({
  TrackingProfile.standby: ConfigPresets.lowPower,
  TrackingProfile.enRoute: ConfigPresets.balanced,
}, initialProfile: TrackingProfile.standby);

// Switch to low-power when not moving
await Locus.switchProfile(TrackingProfile.standby);
```

---

### HTTP Sync Failures

#### Symptom
Locations not syncing to server, or sync errors in logs.

#### Solutions

**1. Verify URL Configuration**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  method: 'POST',
));
```

**2. Check Network Connectivity**

```dart
Locus.sync.events.listen((event) {
  if (event.type == SyncEventType.failure) {
    print('Sync failed: ${event.error}');
  }
});
```

**3. Inspect Queue**

```dart
final diagnostics = await Locus.getDiagnostics();
print('Queued locations: ${diagnostics.queue.length}');

// Manually trigger sync
await Locus.sync.now();
```

**4. Configure Retry Logic**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  maxRetry: 5,
  retryDelay: 10000, // 10 seconds
  retryDelayMultiplier: 2.0, // Exponential backoff
  maxRetryDelay: 300000, // 5 minutes max
));
```

**5. Enable Batch Sync**

Reduce HTTP requests:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 50,
  autoSyncThreshold: 20, // Sync when 20+ locations queued
));
```

**6. Check Authorization**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json',
  },
));
```

If you receive 401 Unauthorized, sync is automatically paused:

```dart
// After refreshing token:
await Locus.sync.resume();
```

**7. Custom Sync Body Builder**

For complex payloads:

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'device_id': extras['deviceId'],
    'locations': locations.map((l) => {
      'lat': l.coords.latitude,
      'lon': l.coords.longitude,
      'timestamp': l.timestamp.toIso8601String(),
    }).toList(),
  };
});
```

**8. Disable Cellular Sync**

To save data:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableAutoSyncOnCellular: true,
));
```

---

### Permissions Issues

#### Symptom
Permission dialogs not showing, or permissions denied.

#### Android Permissions

**1. Background Permission (Android 10+)**

Android 10+ requires separate background permission:

```dart
final status = await Locus.requestPermission();
// User must grant "Allow all the time"
```

**2. Manifest Permissions**

Verify in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

**3. Multi-Step Permission Flow**

Use `PermissionAssistant` for guided flow:

```dart
final status = await PermissionAssistant.requestBackgroundWorkflow(
  config: myConfig,
  delegate: MyPermissionDelegate(),
);
```

#### iOS Permissions

**1. Always Permission**

Background tracking requires "Always" permission:

```dart
// Request "When In Use" first
await Locus.requestPermission();

// Then request "Always" (iOS will show dialog after some time)
```

**2. Info.plist Descriptions**

Verify usage descriptions:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to track trips in the background.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your trips.</string>
```

**3. Precise Location (iOS 14+)**

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableLocationAuthorizationAlert: false,
));
```

---

## Platform-Specific Issues

### Android Issues

#### Doze Mode & App Standby

**Problem**: Android Doze mode restricts background activity.

**Solution**: Request battery optimization exemption or use foreground service:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true,
  preventSuspend: true,
));
```

Guide users to disable battery optimization:
Settings → Apps → Your App → Battery → Unrestricted

#### Manufacturer-Specific Issues

Some manufacturers (Xiaomi, Huawei, Samsung) have aggressive battery management.

**Solution**: Guide users to manufacturer-specific settings:
- **Xiaomi**: Settings → Battery → App battery saver → Your App → No restrictions
- **Huawei**: Settings → Battery → App launch → Your App → Manual
- **Samsung**: Settings → Device care → Battery → Background usage limits → Never sleeping apps

#### Location Provider Changes

**Problem**: Switching between GPS, WiFi, and cell tower can cause gaps.

**Solution**: Enable provider change records:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableProviderChangeRecord: false,
));
```

### iOS Issues

#### Location Services Must Be Enabled

iOS won't show permission dialog if location services are disabled system-wide.

**Solution**: Check and guide user:

```dart
final state = await Locus.getState();
if (!state.locationServicesEnabled) {
  // Show dialog: "Enable Location Services in Settings"
}
```

#### Reduced Accuracy Mode (iOS 14+)

User can select "Precise: Off" which reduces accuracy to ~1-5km.

**Solution**: Detect and prompt:

```dart
Locus.location.stream.listen((location) {
  if (location.coords.accuracy > 1000) {
    // Likely reduced accuracy mode
    print('Prompt user to enable Precise Location in Settings');
  }
});
```

#### Background App Refresh

Must be enabled for background sync:

Settings → General → Background App Refresh → Your App → On

#### Background Location Indicator

iOS 13+ shows blue indicator when app uses background location.

**Solution**: Hide or customize indicator:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  showsBackgroundLocationIndicator: false, // Hides blue bar (iOS 11+)
));
```

---

## Analyzing Logs

### Retrieving Logs

```dart
final logs = await Locus.getLog();
for (final entry in logs) {
  print('[${entry.level}] ${entry.timestamp}: ${entry.message}');
}
```

### Common Log Patterns

**"Location services disabled"**
- User disabled location in system settings
- Guide user to enable location services

**"Permission denied"**
- Location permission not granted
- Call `Locus.requestPermission()`

**"Timeout acquiring location"**
- Poor GPS signal or location services slow
- Increase `locationTimeout` or test outdoors

**"Sync failed: 401"**
- Authorization token expired
- Refresh token and call `Locus.sync.resume()`

**"Geofence limit exceeded"**
- Too many geofences registered
- Remove unused geofences

**"Service disconnected"**
- Background service killed by OS
- Enable foreground service, disable battery optimization

---

## Debug Overlay

Visualize SDK state in real-time during development:

```dart
import 'package:flutter/foundation.dart';
import 'package:locus/locus.dart';

@override
Widget build(BuildContext context) {
  return Stack(
    children: [
      MyApp(),
      if (kDebugMode) const LocusDebugOverlay(),
    ],
  );
}
```

**Features**:
- Current location and accuracy
- Motion state and activity
- Queue size
- Sync status
- Error count
- Battery impact

---

## Error Recovery

Configure automatic error recovery:

```dart
Locus.setErrorHandler(ErrorRecoveryConfig(
  onError: (error, context) {
    // Log to analytics
    analytics.logError(error.type.name, error.message);
    
    // Return recovery action
    return error.suggestedRecovery ?? RecoveryAction.retry;
  },
  onResolved: (error, attempts) {
    print('Error resolved after $attempts attempts');
  },
  onExhausted: (error) {
    print('Error recovery failed: ${error.message}');
    // Notify user
  },
  maxRetries: 3,
  retryDelay: Duration(seconds: 5),
  retryBackoff: 2.0,
  autoRestart: true,
));
```

Listen for errors:

```dart
Locus.errors.listen((error) {
  print('Error: ${error.type.name} - ${error.message}');
  
  switch (error.type) {
    case LocusErrorType.permissionDenied:
      // Show permission rationale
      break;
    case LocusErrorType.servicesDisabled:
      // Prompt to enable location services
      break;
    case LocusErrorType.networkError:
      // Show "offline" indicator
      break;
    default:
      break;
  }
});
```

---

## Getting Help

If you've tried these solutions and still have issues:

1. **Enable verbose logging**: Set `logLevel: LogLevel.verbose`
2. **Collect diagnostics**: Call `Locus.getDiagnostics()` and save output
3. **Check logs**: Review logs for error messages
4. **Create an issue**: Visit [GitHub Issues](https://github.com/koksalmehmet/locus/issues) with:
   - Device info (model, OS version)
   - Locus version
   - Configuration (anonymize sensitive data)
   - Relevant logs
   - Steps to reproduce

---

**Related Documentation:**
- [Error Codes Reference](../api/error-codes.md)
- [FAQ](faq.md)
- [Configuration Reference](../core/configuration-reference.md)
- [Platform-Specific Setup](../setup/platform-specific.md)
