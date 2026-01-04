# Battery Optimization

Locus includes sophisticated battery optimization features that automatically adjust tracking behavior based on device conditions and user activity.

## Adaptive Tracking

Adaptive tracking automatically adjusts location accuracy and update frequency based on:

- Current battery level
- Device charging state
- User activity (stationary, walking, driving)
- Movement speed

### Enabling Adaptive Tracking

```dart
await Locus.ready(Config.balanced(
  url: 'https://api.example.com/locations',
  enableAdaptiveTracking: true,
));
```

### Adaptive Configuration

```dart
final adaptiveConfig = AdaptiveTrackingConfig(
  // Battery thresholds
  lowBatteryThreshold: 20,
  criticalBatteryThreshold: 10,
  
  // Behavior when stationary
  stationaryDistanceFilter: 50,
  stationaryAccuracy: Accuracy.low,
  stationaryHeartbeat: Duration(minutes: 5),
  
  // Behavior when moving
  movingDistanceFilter: 10,
  movingAccuracy: Accuracy.high,
  
  // Speed-based adjustments
  walkingSpeedThreshold: 2.0,  // m/s
  drivingSpeedThreshold: 10.0, // m/s
);

await Locus.configureAdaptiveTracking(adaptiveConfig);
```

## Battery Runway

Battery runway estimates how long tracking can continue at current power consumption:

```dart
final runway = await Locus.getBatteryRunway();
print('Estimated tracking time remaining: ${runway.duration}');
print('Current drain rate: ${runway.drainRatePerHour}%/hr');
```

### Runway Calculator

For more detailed estimates:

```dart
final calculator = BatteryRunwayCalculator();

final estimate = calculator.estimate(
  currentLevel: 75,
  isCharging: false,
  currentConfig: myConfig,
);

print('At current settings: ${estimate.duration}');
print('Recommended config: ${estimate.recommendedConfig}');
```

## Power State Monitoring

Monitor device power state changes:

```dart
Locus.onPowerStateChange.listen((state) {
  print('Battery: ${state.level}%');
  print('Charging: ${state.isCharging}');
  print('Power save mode: ${state.isPowerSaveMode}');
});
```

## Tracking Profiles

Pre-defined profiles optimize for different use cases:

```dart
// High accuracy for fitness apps
await Locus.setTrackingProfile(TrackingProfile.fitness);

// Battery-saving for long trips
await Locus.setTrackingProfile(TrackingProfile.passive);

// Balanced for general use
await Locus.setTrackingProfile(TrackingProfile.balanced);
```

### Custom Profiles

Create custom profiles with automatic switching rules:

```dart
final customProfile = TrackingProfile(
  identifier: 'delivery_mode',
  distanceFilter: 25,
  desiredAccuracy: Accuracy.balanced,
  rules: [
    TrackingProfileRule(
      type: TrackingProfileRuleType.batteryBelow,
      threshold: 20,
      targetProfile: TrackingProfile.passive,
    ),
    TrackingProfileRule(
      type: TrackingProfileRuleType.speedAbove,
      threshold: 15, // m/s
      targetProfile: TrackingProfile.fitness,
    ),
  ],
);

final manager = TrackingProfileManager();
manager.registerProfile(customProfile);
await manager.setActiveProfile('delivery_mode');
```

## Sync Policy

Control when data is synced to save battery:

```dart
final syncPolicy = SyncPolicy(
  // Only sync on WiFi when battery is low
  wifiOnlyBelowBattery: 30,
  
  // Batch locations to reduce network calls
  batchSize: 50,
  
  // Maximum time between syncs
  maxSyncInterval: Duration(hours: 1),
  
  // Sync immediately when charging
  immediateWhenCharging: true,
);

await Locus.configureSyncPolicy(syncPolicy);
```

---

**Next:** [Diagnostics & Debugging](diagnostics.md)
