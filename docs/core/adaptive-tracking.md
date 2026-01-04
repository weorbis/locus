# Adaptive Tracking

## Overview

Adaptive Tracking automatically adjusts location sampling rate based on device battery state and movement patterns. It provides intelligent battery optimization while maintaining location accuracy.

## How It Works

Adaptive Tracking monitors:
- Battery level and charging state
- Device activity (stationary vs. moving)
- Location quality and signal strength
- Power profile settings

Based on these inputs, it dynamically adjusts:
- Location sampling frequency
- GPS accuracy mode
- Update intervals
- Sync policies

## Using Adaptive Tracking

Enable adaptive tracking:

```dart
import 'package:locus/locus.dart';

await Locus.battery.adaptive.configure(
  AdaptiveTrackingConfig(
    enabled: true,
    conserveOnLowBattery: true,
    batteryThreshold: 0.20,  // Switch to battery-saving mode below 20%
  ),
);
```

## Battery Profiles

Adaptive tracking provides preset profiles:

```dart
// Maximum accuracy (high battery usage)
await Locus.battery.adaptive.useProfile(TrackingProfile.highAccuracy);

// Balanced (default)
await Locus.battery.adaptive.useProfile(TrackingProfile.balanced);

// Battery saving
await Locus.battery.adaptive.useProfile(TrackingProfile.powerSaving);

// Custom profile
await Locus.battery.adaptive.useProfile(
  TrackingProfile.custom(
    updateInterval: Duration(seconds: 30),
    accuracy: Accuracy.medium,
    distanceFilter: 25,
  ),
);
```

## Monitoring Adaptive State

```dart
// Get current adaptive state
final state = await Locus.battery.adaptive.state();
print('Current profile: ${state.activeProfile}');
print('Battery level: ${state.batteryLevel}');
print('Is stationary: ${state.isStationary}');
print('Current accuracy: ${state.accuracy}');

// Listen to profile changes
Locus.battery.adaptive.onProfileChange((profile) {
  print('Switched to: ${profile.name}');
});

// Get battery runway estimate
final runway = await Locus.battery.adaptive.batteryRunway();
print('Battery duration: ${runway.estimatedMinutes} minutes');
```

## Runway Calculations

Battery runway shows how long the device can maintain tracking:

```dart
final runway = await Locus.battery.adaptive.batteryRunway();

if (runway.isLow()) {
  // Switch to power-saving mode
  await Locus.battery.adaptive.useProfile(TrackingProfile.powerSaving);
}
```

## Manual Control

You can also manually control tracking parameters:

```dart
await Locus.config.set(
  GeolocationConfig(
    accuracy: Accuracy.best,
    updateInterval: Duration(seconds: 5),
    distanceFilter: 0,
  ),
);
```

**Next:** [Advanced Configuration](configuration.md)
