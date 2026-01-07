# Performance Optimization Guide

Comprehensive guide to optimizing Locus for battery life, CPU usage, memory consumption, and location accuracy.

## Table of Contents

1. [Overview](#overview)
2. [Profiling Tools](#profiling-tools)
3. [Battery Optimization](#battery-optimization)
4. [CPU Optimization](#cpu-optimization)
5. [Memory Optimization](#memory-optimization)
6. [Location Accuracy vs Battery Tradeoffs](#location-accuracy-vs-battery-tradeoffs)
7. [Network and Sync Optimization](#network-and-sync-optimization)
8. [Platform-Specific Optimizations](#platform-specific-optimizations)
9. [Monitoring and Metrics](#monitoring-and-metrics)
10. [Best Practices](#best-practices)

---

## Overview

Performance optimization in location tracking involves balancing four key factors:

1. **Battery Life** - How long device can track before charging
2. **Location Accuracy** - How precise locations are
3. **Update Frequency** - How often locations are recorded
4. **Data Reliability** - Ensuring no data loss

Optimizations often involve tradeoffs between these factors.

---

## Profiling Tools

### Built-in Diagnostics

```dart
// Get real-time diagnostics
final diagnostics = await Locus.getDiagnostics();

print('State: ${diagnostics.state}');
print('Queue size: ${diagnostics.queue.length}');
print('Last location: ${diagnostics.lastLocation}');
print('Last sync: ${diagnostics.lastSyncAt}');
print('Error count: ${diagnostics.errorCount}');
```

### Battery Runway Estimation

```dart
final runway = await Locus.battery.estimateRunway();

print('Hours remaining: ${runway.hours}');
print('Drain rate: ${runway.drainRatePerHour}%/hour');
print('Recommendation: ${runway.recommendation}');

if (runway.drainRatePerHour > 10) {
  print('WARNING: High battery drain detected');
  // Consider switching to lower power mode
}
```

### Debug Overlay

Visual real-time monitoring during development:

```dart
import 'package:flutter/foundation.dart';

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

Shows:
- Current location & accuracy
- Motion state & activity
- Queue size
- Sync status
- Battery drain estimate
- Error count

### Platform Profiling Tools

**Android**:
```bash
# Battery usage
adb shell dumpsys batterystats --reset
# Run app for test period
adb shell dumpsys batterystats com.example.app

# CPU usage
adb shell top | grep com.example.app
```

**iOS**:
- Xcode → Debug → Energy Impact
- Instruments → Energy Log
- Settings → Battery → Battery Usage by App

---

## Battery Optimization

### 1. Use Appropriate Configuration Preset

```dart
// ❌ Don't use trail preset for non-fitness apps
await Locus.ready(ConfigPresets.trail); // 10-20%/hour drain

// ✅ Use balanced or lowPower for most apps
await Locus.ready(ConfigPresets.balanced); // 2-5%/hour drain
await Locus.ready(ConfigPresets.lowPower);  // 0.5-2%/hour drain
```

### 2. Enable Adaptive Tracking

Automatically adjusts based on conditions:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  adaptiveTracking: AdaptiveTrackingConfig(
    speedTiers: SpeedTiers.driving,
    batteryThresholds: BatteryThresholds.conservative,
    stationaryGpsOff: true,
    stationaryDelay: Duration(minutes: 2),
    smartHeartbeat: true,
  ),
));
```

**How it works**:
- **Stationary**: Powers down GPS, uses significant location changes
- **Walking**: Medium accuracy, moderate updates
- **Driving**: High accuracy, frequent updates
- **Low Battery**: Automatically switches to power-saving mode

### 3. Optimize Stop Detection

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableStopDetection: false,
  stopTimeout: 5, // Power down after 5 minutes stationary
  stationaryRadius: 25, // meters
));
```

**Battery Impact**: GPS powered down during stops saves 80-90% battery.

### 4. Increase Distance Filter

```dart
// ❌ High frequency = high battery drain
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 5, // Update every 5 meters
));

// ✅ Moderate frequency = balanced battery
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 50, // Update every 50 meters
));

// ✅ Low frequency = best battery
await Locus.ready(ConfigPresets.balanced.copyWith(
  distanceFilter: 200, // Update every 200 meters
));
```

**Battery Impact**: 10x increase in distance filter = ~50% battery savings.

### 5. Reduce Desired Accuracy

```dart
// ❌ Navigation accuracy = continuous GPS
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.navigation,
));

// ✅ Low accuracy = WiFi/cell only
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.low,
));
```

**Accuracy vs Battery**:
- `navigation`: 1-5m accuracy, 100% GPS usage
- `high`: 5-15m accuracy, 80% GPS usage
- `medium`: 10-25m accuracy, 50% GPS usage
- `low`: 50-100m accuracy, 20% GPS usage (WiFi/cell)
- `lowest`: 500m+ accuracy, minimal battery

### 6. Use Tracking Profiles

Switch configurations based on context:

```dart
await Locus.setTrackingProfiles({
  TrackingProfile.standby: ConfigPresets.lowPower,
  TrackingProfile.enRoute: ConfigPresets.balanced,
  TrackingProfile.arrived: Config(
    desiredAccuracy: DesiredAccuracy.low,
    distanceFilter: 100,
  ),
}, initialProfile: TrackingProfile.standby);

// Switch when trip starts
await Locus.switchProfile(TrackingProfile.enRoute);

// Switch back when idle
await Locus.switchProfile(TrackingProfile.standby);
```

### 7. Low Battery Fallback

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  lowBattery: LowBatteryConfig(
    threshold: 15, // At 15% battery
    config: ConfigPresets.lowPower,
  ),
));
```

### 8. Minimize Heartbeat Frequency

```dart
// ❌ Frequent heartbeats
await Locus.ready(ConfigPresets.balanced.copyWith(
  heartbeatInterval: 30, // Every 30 seconds
));

// ✅ Infrequent heartbeats
await Locus.ready(ConfigPresets.balanced.copyWith(
  heartbeatInterval: 300, // Every 5 minutes
));
```

### 9. Disable Unnecessary Features

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableMotionActivityUpdates: true, // Save ~5% battery
  preventSuspend: false, // Allow device sleep
));
```

---

## CPU Optimization

### 1. Reduce Activity Recognition Frequency

```dart
// ❌ High frequency
await Locus.ready(ConfigPresets.balanced.copyWith(
  activityRecognitionInterval: 1000, // Every second
));

// ✅ Moderate frequency
await Locus.ready(ConfigPresets.balanced.copyWith(
  activityRecognitionInterval: 10000, // Every 10 seconds
));
```

### 2. Batch Sync Requests

```dart
// ❌ Sync each location immediately
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: false,
  autoSync: true,
));

// ✅ Batch multiple locations
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 50,
  autoSyncThreshold: 25,
));
```

**CPU Impact**: 50 individual HTTP requests vs 1 batched request = 98% CPU reduction.

### 3. Optimize Location Filtering

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  // Reject physically impossible speeds
  speedJumpFilter: 50, // m/s
  
  // Ignore identical locations
  allowIdenticalLocations: false,
  
  // Minimum accuracy for processing
  desiredOdometerAccuracy: 50,
));
```

### 4. Limit Queue Processing

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  queueMaxRecords: 10000, // Limit queue size
  queueMaxDays: 7, // Purge old data
));
```

### 5. Reduce Log Verbosity in Production

```dart
// Development
await Locus.ready(ConfigPresets.balanced.copyWith(
  logLevel: LogLevel.verbose,
));

// Production
await Locus.ready(ConfigPresets.balanced.copyWith(
  logLevel: LogLevel.error, // Only log errors
  logMaxDays: 1, // Keep logs briefly
));
```

---

## Memory Optimization

### 1. Limit Queue Size

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  queueMaxRecords: 5000, // Limit to 5000 locations
  queueMaxDays: 3, // Auto-purge after 3 days
));
```

**Memory Impact**: 1000 locations ≈ 2-3 MB RAM.

### 2. Manage Geofence Count

```dart
// Monitor geofence count
final geofences = await Locus.geofencing.getAll();
if (geofences.length > 50) {
  // Remove least important geofences
  await Locus.geofencing.remove(oldestGeofence.identifier);
}
```

**Memory Impact**: Each geofence ≈ 100-200 KB.

### 3. Clear Old Data Periodically

```dart
// Clear sync queue after successful sync
Locus.sync.events.listen((event) {
  if (event.type == SyncEventType.success) {
    // Queue is automatically cleared
  }
});

// Or manually clear database
await Locus.clearDatabase();
```

### 4. Optimize Persistence Mode

```dart
// ❌ Persist everything
await Locus.ready(ConfigPresets.balanced.copyWith(
  persistMode: PersistMode.all,
));

// ✅ Persist only necessary data
await Locus.ready(ConfigPresets.balanced.copyWith(
  persistMode: PersistMode.location, // Skip geofence events
  maxRecordsToPersist: 5000,
));
```

### 5. Stream Management

```dart
// ❌ Don't leak subscriptions
StreamSubscription? _subscription;

void startListening() {
  _subscription = Locus.location.stream.listen((location) {
    // Process location
  });
}

// ✅ Cancel subscriptions
@override
void dispose() {
  _subscription?.cancel();
  super.dispose();
}
```

---

## Location Accuracy vs Battery Tradeoffs

### Understanding the Tradeoff Matrix

| Configuration | Accuracy | Update Freq | Battery/Hour | Use Case |
|---------------|----------|-------------|--------------|----------|
| Navigation preset | 1-5m | Very High | 10-20% | Running, cycling |
| Tracking preset | 5-15m | High | 5-10% | Delivery, fleet |
| Balanced preset | 10-25m | Medium | 2-5% | Social, general |
| Low power preset | 50-100m | Low | 0.5-2% | Passive, geofencing |
| Custom minimal | 500m+ | Very Low | <0.5% | Region monitoring |

### Optimization Strategies by Use Case

#### Fitness Tracking

**Requirements**: High accuracy, frequent updates

```dart
await Locus.ready(ConfigPresets.trail.copyWith(
  desiredAccuracy: DesiredAccuracy.navigation,
  distanceFilter: 5,
  disableStopDetection: true, // No stops during workout
  stopOnStationary: false,
));
```

**Compromise**: Accept 10-20%/hour drain for best accuracy.

#### Delivery / Fleet Management

**Requirements**: Good accuracy, reasonable battery life

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 25,
  stopTimeout: 5,
  adaptiveTracking: AdaptiveTrackingConfig.balanced,
));
```

**Compromise**: 5-10%/hour drain, 5-15m accuracy.

#### Social / Check-in Apps

**Requirements**: Moderate accuracy, good battery life

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  desiredAccuracy: DesiredAccuracy.medium,
  distanceFilter: 100,
  stopTimeout: 10,
));
```

**Compromise**: 2-5%/hour drain, 10-25m accuracy.

#### Passive Tracking

**Requirements**: Minimal battery impact

```dart
await Locus.ready(ConfigPresets.lowPower.copyWith(
  desiredAccuracy: DesiredAccuracy.low,
  distanceFilter: 200,
  useSignificantChangesOnly: true, // iOS
));
```

**Compromise**: 0.5-2%/hour drain, 50-100m accuracy.

### Dynamic Adjustment

```dart
Locus.location.stream.listen((location) {
  final speed = location.coords.speed;
  
  if (speed > 25) {
    // Driving - need higher accuracy
    Locus.switchProfile(TrackingProfile.enRoute);
  } else if (speed > 5) {
    // Walking - balanced
    Locus.switchProfile(TrackingProfile.balanced);
  } else {
    // Stationary - low power
    Locus.switchProfile(TrackingProfile.standby);
  }
});
```

---

## Network and Sync Optimization

### 1. Enable Batch Sync

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 100,
  autoSyncThreshold: 50, // Sync when 50 queued
));
```

**Impact**: 100 requests → 1 request = 99% network traffic reduction.

### 2. Disable Cellular Sync

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  disableAutoSyncOnCellular: true,
));
```

**Impact**: Save mobile data, sync only on WiFi.

### 3. Optimize Retry Logic

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  maxRetry: 3,
  retryDelay: 10000, // 10 seconds
  retryDelayMultiplier: 2.0, // Exponential backoff
  maxRetryDelay: 300000, // Max 5 minutes
));
```

### 4. Reduce Payload Size

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'locations': locations.map((l) => {
      'lat': l.coords.latitude,
      'lon': l.coords.longitude,
      'time': l.timestamp.millisecondsSinceEpoch,
      // Omit unnecessary fields
    }).toList(),
  };
});
```

### 5. Monitor Network Conditions

```dart
Locus.sync.events.listen((event) {
  if (event.type == SyncEventType.failure) {
    if (event.statusCode == 503) {
      // Server overloaded, pause sync
      await Locus.sync.pause();
      
      // Resume after delay
      Future.delayed(Duration(minutes: 5), () {
        Locus.sync.resume();
      });
    }
  }
});
```

---

## Platform-Specific Optimizations

### Android

#### 1. Use Fused Location Provider

Locus automatically uses Google Play Services Fused Location Provider, which:
- Combines GPS, WiFi, cell tower data
- Optimizes battery usage
- Provides best accuracy/battery balance

#### 2. Handle Doze Mode

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  foregroundService: true, // Exempt from Doze
  preventSuspend: true,
));
```

#### 3. Optimize for Android 12+

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  fastestLocationUpdateInterval: 2000, // Throttle updates
));
```

### iOS

#### 1. Use Significant Location Changes

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  useSignificantChangesOnly: true, // Very low power
));
```

#### 2. Allow Auto-Pause

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  pausesLocationUpdatesAutomatically: true,
));
```

#### 3. Optimize Background Refresh

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  bgTaskId: 'com.example.app.refresh',
  heartbeatInterval: 600, // 10 minutes
));
```

---

## Monitoring and Metrics

### 1. Track Battery Consumption

```dart
class BatteryMonitor {
  int? _initialLevel;
  DateTime? _startTime;
  
  void start() async {
    final runway = await Locus.battery.estimateRunway();
    _initialLevel = runway.currentLevel;
    _startTime = DateTime.now();
  }
  
  Future<double> getDrainRate() async {
    if (_initialLevel == null || _startTime == null) return 0;
    
    final runway = await Locus.battery.estimateRunway();
    final currentLevel = runway.currentLevel;
    final elapsed = DateTime.now().difference(_startTime!).inHours;
    
    if (elapsed == 0) return 0;
    return (_initialLevel! - currentLevel) / elapsed;
  }
}
```

### 2. Monitor Update Frequency

```dart
int _locationCount = 0;
DateTime? _monitorStart;

Locus.location.stream.listen((location) {
  _locationCount++;
  
  _monitorStart ??= DateTime.now();
  final elapsed = DateTime.now().difference(_monitorStart!).inMinutes;
  
  if (elapsed >= 60) {
    final updatesPerHour = _locationCount / (elapsed / 60);
    print('Updates/hour: $updatesPerHour');
    
    if (updatesPerHour > 1000) {
      print('WARNING: Very high update frequency');
    }
    
    // Reset
    _locationCount = 0;
    _monitorStart = DateTime.now();
  }
});
```

### 3. Track Sync Performance

```dart
Locs.sync.events.listen((event) {
  if (event.type == SyncEventType.success) {
    print('Synced ${event.locations.length} locations');
    print('Duration: ${event.duration}ms');
    print('Payload size: ${event.payloadSize} bytes');
  }
});
```

### 4. Monitor Queue Growth

```dart
Timer.periodic(Duration(minutes: 5), (timer) async {
  final diagnostics = await Locus.getDiagnostics();
  print('Queue size: ${diagnostics.queue.length}');
  
  if (diagnostics.queue.length > 1000) {
    print('WARNING: Large queue detected');
    // Trigger manual sync
    await Locus.sync.now();
  }
});
```

---

## Best Practices

### 1. Start with a Preset

```dart
// ✅ Start with preset, customize incrementally
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
));

// ❌ Don't start from scratch
await Locus.ready(Config(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 10,
  // ... 50 more parameters
));
```

### 2. Profile in Real Conditions

- Test on real devices (not just simulators)
- Test with actual movement patterns
- Measure battery drain over hours, not minutes
- Test on different OS versions
- Test with poor GPS signal

### 3. Implement Graceful Degradation

```dart
final runway = await Locus.battery.estimateRunway();

if (runway.currentLevel < 20) {
  // Low battery: reduce to minimal tracking
  await Locus.setConfig(ConfigPresets.lowPower);
} else if (runway.currentLevel < 50) {
  // Medium battery: balanced tracking
  await Locus.setConfig(ConfigPresets.balanced);
} else {
  // Good battery: high accuracy
  await Locus.setConfig(ConfigPresets.tracking);
}
```

### 4. Educate Users

Show battery impact in UI:
```dart
final runway = await Locus.battery.estimateRunway();

showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Battery Impact'),
    content: Text(
      'Current tracking will drain ${runway.drainRatePerHour.toStringAsFixed(1)}%/hour. '
      'Estimated ${runway.hours.toStringAsFixed(1)} hours remaining.'
    ),
  ),
);
```

### 5. Test Optimizations

```dart
// Baseline
final baseline = await _measureBatteryDrain(ConfigPresets.balanced);

// Optimized
final optimized = await _measureBatteryDrain(myOptimizedConfig);

print('Improvement: ${((baseline - optimized) / baseline * 100).toStringAsFixed(1)}%');
```

---

## Summary

Performance optimization checklist:

- ✅ Use appropriate configuration preset
- ✅ Enable adaptive tracking
- ✅ Implement stop detection
- ✅ Use tracking profiles for context-aware optimization
- ✅ Enable batch sync
- ✅ Monitor battery drain
- ✅ Profile on real devices
- ✅ Implement graceful degradation
- ✅ Educate users about battery impact
- ✅ Test optimizations with metrics

**Remember**: The best configuration balances your app's requirements with user experience. Start conservative, measure, and optimize incrementally.

---

**Related Documentation:**
- [Configuration Reference](../core/configuration-reference.md)
- [Battery Optimization](battery-optimization.md)
- [FAQ](../guides/faq.md)
- [Troubleshooting Guide](../guides/troubleshooting.md)
