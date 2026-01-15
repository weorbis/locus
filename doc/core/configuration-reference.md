# Configuration Complete Reference

Comprehensive reference for all Locus configuration options, including default values, valid ranges, performance implications, and examples.

## Table of Contents

1. [Configuration Presets](#configuration-presets)
2. [Location Settings](#location-settings)
3. [Background & Foreground Settings](#background--foreground-settings)
4. [Motion Detection Settings](#motion-detection-settings)
5. [Geofencing Settings](#geofencing-settings)
6. [HTTP Sync Settings](#http-sync-settings)
7. [Persistence Settings](#persistence-settings)
8. [Scheduling Settings](#scheduling-settings)
9. [Notification Settings](#notification-settings)
10. [Advanced Features](#advanced-features)
11. [Full Configuration Example](#full-configuration-example)

---

## Configuration Presets

Presets provide optimized defaults for common use cases:

### ConfigPresets.lowPower

**Use Case**: Passive tracking, background monitoring

```dart
Config(
  desiredAccuracy: DesiredAccuracy.low,
  distanceFilter: 200,
  stopTimeout: 15,
  heartbeatInterval: 300,
  autoSync: true,
  batchSync: true,
)
```

**Characteristics**:
- Lowest battery consumption (0.5-2%/hour)
- Coarse accuracy (50-100m)
- Updates every 200 meters
- 5-minute heartbeat when idle

---

### ConfigPresets.balanced

**Use Case**: General tracking, social apps, asset tracking

```dart
Config(
  desiredAccuracy: DesiredAccuracy.medium,
  distanceFilter: 50,
  stopTimeout: 8,
  heartbeatInterval: 120,
  autoSync: true,
  batchSync: true,
)
```

**Characteristics**:
- Balanced battery/accuracy (2-5%/hour)
- Medium accuracy (10-25m)
- Updates every 50 meters
- 2-minute heartbeat when idle

---

### ConfigPresets.tracking

**Use Case**: Active tracking, delivery, fleet management

```dart
Config(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 10,
  stopTimeout: 5,
  heartbeatInterval: 60,
  autoSync: true,
  batchSync: true,
)
```

**Characteristics**:
- Higher battery consumption (5-10%/hour)
- High accuracy (5-15m)
- Updates every 10 meters
- 1-minute heartbeat when idle

---

### ConfigPresets.trail

**Use Case**: Fitness tracking, running, cycling apps

```dart
Config(
  desiredAccuracy: DesiredAccuracy.navigation,
  distanceFilter: 5,
  stopTimeout: 2,
  activityRecognitionInterval: 5000,
  heartbeatInterval: 30,
  autoSync: true,
  batchSync: false,
)
```

**Characteristics**:
- Highest battery consumption (10-20%/hour)
- Best accuracy (1-5m)
- Updates every 5 meters
- Immediate sync (no batching)
- 30-second heartbeat

---

## Location Settings

### desiredAccuracy

**Type**: `DesiredAccuracy` enum

**Description**: Target location accuracy level.

**Options**:
- `DesiredAccuracy.navigation` - Best for turn-by-turn navigation (~1-5m)
- `DesiredAccuracy.high` - High accuracy using GPS (~5-15m)
- `DesiredAccuracy.medium` - Balanced GPS/WiFi (~10-25m)
- `DesiredAccuracy.low` - Coarse location, cell/WiFi (~50-100m)
- `DesiredAccuracy.veryLow` - Very coarse (~100-500m)
- `DesiredAccuracy.lowest` - Minimal accuracy (~500m+)

**Default**: Preset-dependent

**Performance Impact**:
- Higher accuracy = more battery consumption
- `navigation` and `high` use GPS continuously
- `low` and below rely on cell towers/WiFi (battery-efficient)

**Example**:
```dart
Config(desiredAccuracy: DesiredAccuracy.high)
```

---

### distanceFilter

**Type**: `double` (meters)

**Description**: Minimum distance before triggering a location update.

**Range**: `0` to `1000000`

**Default**: Preset-dependent (5-200m)

**Performance Impact**:
- Lower values = more updates = higher battery drain
- Higher values = fewer updates = better battery life

**Recommendations**:
- **Fitness**: 5-10m
- **Delivery**: 10-25m
- **Social**: 50-100m
- **Passive**: 200-500m

**Example**:
```dart
Config(distanceFilter: 50) // Update every 50 meters
```

---

### locationUpdateInterval

**Type**: `int` (milliseconds)

**Platform**: Android only

**Description**: Minimum time between location updates.

**Range**: `1000` (1 second) to `3600000` (1 hour)

**Default**: `5000` (5 seconds)

**Performance Impact**: Lower values increase update frequency and battery usage.

**Example**:
```dart
Config(locationUpdateInterval: 10000) // Minimum 10 seconds
```

---

### fastestLocationUpdateInterval

**Type**: `int` (milliseconds)

**Platform**: Android only

**Description**: Fastest rate app can handle location updates (throttles updates from other apps).

**Range**: `1000` to `3600000`

**Default**: `1000` (1 second)

**Example**:
```dart
Config(fastestLocationUpdateInterval: 2000)
```

---

### activityRecognitionInterval

**Type**: `int` (milliseconds)

**Description**: Interval for motion activity detection.

**Range**: `1000` to `300000`

**Default**: `10000` (10 seconds)

**Performance Impact**: Lower values provide faster activity detection but increase battery usage.

**Example**:
```dart
Config(activityRecognitionInterval: 5000) // Check every 5 seconds
```

---

### stopTimeout

**Type**: `int` (minutes)

**Description**: Minutes of no motion before entering stationary mode.

**Range**: `1` to `60`

**Default**: Preset-dependent (2-15 minutes)

**Behavior**: After timeout, GPS powers down to save battery. Updates resume when motion detected.

**Example**:
```dart
Config(stopTimeout: 5) // Enter stationary mode after 5 minutes
```

---

### stopAfterElapsedMinutes

**Type**: `int` (minutes)

**Description**: Automatically stop tracking after specified duration.

**Range**: `1` to unlimited

**Default**: `null` (no auto-stop)

**Example**:
```dart
Config(stopAfterElapsedMinutes: 120) // Stop after 2 hours
```

---

### stopDetectionDelay

**Type**: `int` (milliseconds)

**Description**: Delay before triggering stop detection.

**Range**: `0` to `300000`

**Default**: `0`

**Example**:
```dart
Config(stopDetectionDelay: 60000) // Wait 1 minute before detecting stop
```

---

### motionTriggerDelay

**Type**: `int` (milliseconds)

**Description**: Delay before resuming tracking after motion detected.

**Range**: `0` to `60000`

**Default**: `0`

**Example**:
```dart
Config(motionTriggerDelay: 5000) // Wait 5 seconds after motion
```

---

### minimumActivityRecognitionConfidence

**Type**: `int` (percentage)

**Description**: Minimum confidence for activity recognition.

**Range**: `0` to `100`

**Default**: `75`

**Example**:
```dart
Config(minimumActivityRecognitionConfidence: 80) // Require 80% confidence
```

---

### useSignificantChangesOnly

**Type**: `bool`

**Platform**: iOS only

**Description**: Use significant location changes API (very low power).

**Default**: `false`

**Performance Impact**: Minimal battery usage but very infrequent updates.

**Example**:
```dart
Config(useSignificantChangesOnly: true)
```

---

### allowIdenticalLocations

**Type**: `bool`

**Description**: Whether to record locations with identical coordinates.

**Default**: `false`

**Example**:
```dart
Config(allowIdenticalLocations: true)
```

---

### disableMotionActivityUpdates

**Type**: `bool`

**Description**: Disable motion activity detection.

**Default**: `false`

**Performance Impact**: Slightly reduces battery usage.

**Example**:
```dart
Config(disableMotionActivityUpdates: true)
```

---

### disableStopDetection

**Type**: `bool`

**Description**: Disable automatic stop detection.

**Default**: `false`

**Use Case**: When consistent update intervals are critical.

**Example**:
```dart
Config(disableStopDetection: true)
```

---

### disableProviderChangeRecord

**Type**: `bool`

**Platform**: Android only

**Description**: Don't record locations when provider changes (GPS ↔ WiFi ↔ Cell).

**Default**: `false`

**Example**:
```dart
Config(disableProviderChangeRecord: true)
```

---

### disableLocationAuthorizationAlert

**Type**: `bool`

**Platform**: iOS only

**Description**: Suppress iOS authorization alert for precise location.

**Default**: `false`

**Example**:
```dart
Config(disableLocationAuthorizationAlert: true)
```

---

## Background & Foreground Settings

### enableHeadless

**Type**: `bool`

**Description**: Enable headless mode for background Dart execution.

**Default**: `false`

**Requirements**: Must call `Locus.registerHeadlessTask()`.

**See**: [Headless Execution Guide](../advanced/headless-execution.md)

**Example**:
```dart
Config(enableHeadless: true)
```

---

### startOnBoot

**Type**: `bool`

**Description**: Automatically restart tracking after device reboot.

**Default**: `false`

**Requirements**: `stopOnTerminate: false`

**Example**:
```dart
Config(
  startOnBoot: true,
  stopOnTerminate: false,
)
```

---

### stopOnTerminate

**Type**: `bool`

**Description**: Stop tracking when app is terminated.

**Default**: `true`

**Performance Impact**: `false` allows background tracking but drains battery.

**Example**:
```dart
Config(stopOnTerminate: false) // Continue in background
```

---

### foregroundService

**Type**: `bool`

**Platform**: Android only

**Description**: Run as foreground service (shows notification).

**Default**: `false`

**Requirements**: `NotificationConfig` must be provided.

**Example**:
```dart
Config(
  foregroundService: true,
  notification: NotificationConfig(
    title: 'Tracking Active',
    text: 'App is tracking your location',
  ),
)
```

---

### preventSuspend

**Type**: `bool`

**Description**: Prevent device from suspending tracking.

**Default**: `false`

**Performance Impact**: Increases battery consumption.

**Example**:
```dart
Config(preventSuspend: true)
```

---

### pausesLocationUpdatesAutomatically

**Type**: `bool`

**Platform**: iOS only

**Description**: Allow iOS to automatically pause location updates.

**Default**: `true`

**Example**:
```dart
Config(pausesLocationUpdatesAutomatically: false)
```

---

### showsBackgroundLocationIndicator

**Type**: `bool`

**Platform**: iOS only

**Description**: Show/hide blue status bar indicator during background tracking.

**Default**: `true`

**Example**:
```dart
Config(showsBackgroundLocationIndicator: false)
```

---

## Motion Detection Settings

### stationaryRadius

**Type**: `double` (meters)

**Description**: Radius around stationary position before motion is detected.

**Range**: `0` to `1000`

**Default**: `25`

**Example**:
```dart
Config(stationaryRadius: 50)
```

---

### desiredOdometerAccuracy

**Type**: `double` (meters)

**Description**: Minimum accuracy for odometer calculations.

**Range**: `0` to `1000`

**Default**: `100`

**Example**:
```dart
Config(desiredOdometerAccuracy: 50)
```

---

### elasticityMultiplier

**Type**: `double`

**Description**: Multiplier for dynamic distance filtering based on speed.

**Range**: `0` to `10`

**Default**: `1.0`

**Example**:
```dart
Config(elasticityMultiplier: 2.0)
```

---

### speedJumpFilter

**Type**: `double` (m/s)

**Description**: Reject locations requiring impossible speed changes.

**Range**: `0` to `1000`

**Default**: `0` (disabled)

**Recommendation**: Set to 50-100 for urban tracking.

**Example**:
```dart
Config(speedJumpFilter: 50) // Reject > 50 m/s speed changes
```

---

### stopOnStationary

**Type**: `bool`

**Description**: Automatically stop tracking when stationary.

**Default**: `false`

**Example**:
```dart
Config(stopOnStationary: true)
```

---

## Geofencing Settings

### geofenceModeHighAccuracy

**Type**: `bool`

**Description**: Use high-accuracy mode for geofence monitoring.

**Default**: `false`

**Performance Impact**: Increases battery usage.

**Example**:
```dart
Config(geofenceModeHighAccuracy: true)
```

---

### geofenceInitialTriggerEntry

**Type**: `bool`

**Description**: Trigger ENTER event immediately if already inside geofence when added.

**Default**: `true`

**Example**:
```dart
Config(geofenceInitialTriggerEntry: false)
```

---

### geofenceProximityRadius

**Type**: `int` (meters)

**Platform**: iOS only

**Description**: Start monitoring geofence this many meters before boundary.

**Range**: `0` to `1000`

**Default**: `50`

**Example**:
```dart
Config(geofenceProximityRadius: 100)
```

---

### maxMonitoredGeofences

**Type**: `int`

**Description**: Maximum number of active geofences.

**Limits**:
- Android: 100 (hard limit)
- iOS: 20 (hard limit)

**Default**: Platform maximum

**Example**:
```dart
Config(maxMonitoredGeofences: 50)
```

---

## HTTP Sync Settings

### url

**Type**: `String`

**Description**: HTTP endpoint for location synchronization.

**Default**: `null` (sync disabled)

**Example**:
```dart
Config(url: 'https://your-server.com/locations')
```

---

### method

**Type**: `String`

**Description**: HTTP method for sync requests.

**Options**: `POST`, `PUT`, `PATCH`

**Default**: `POST`

**Example**:
```dart
Config(method: 'PUT')
```

---

### headers

**Type**: `Map<String, dynamic>`

**Description**: HTTP headers for sync requests.

**Default**: `{}`

**Example**:
```dart
Config(
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json',
    'X-Device-ID': deviceId,
  },
)
```

---

### params

**Type**: `Map<String, dynamic>`

**Description**: Query parameters appended to URL.

**Default**: `{}`

**Example**:
```dart
Config(
  url: 'https://your-server.com/locations',
  params: {
    'api_key': 'YOUR_KEY',
    'version': '2',
  },
  // Results in: https://your-server.com/locations?api_key=YOUR_KEY&version=2
)
```

---

### extras

**Type**: `Map<String, dynamic>`

**Description**: Additional data included in sync payload.

**Default**: `{}`

**Example**:
```dart
Config(
  extras: {
    'userId': '12345',
    'deviceId': 'abc123',
    'appVersion': '1.0.0',
  },
)
```

---

### autoSync

**Type**: `bool`

**Description**: Automatically sync locations.

**Default**: `true`

**Example**:
```dart
Config(autoSync: false) // Manual sync only
```

---

### batchSync

**Type**: `bool`

**Description**: Batch multiple locations into single request.

**Default**: `true`

**Performance Impact**: Reduces HTTP requests and data usage.

**Example**:
```dart
Config(batchSync: false) // Sync each location immediately
```

---

### maxBatchSize

**Type**: `int`

**Description**: Maximum locations per batch.

**Range**: `1` to `1000`

**Default**: `100`

**Example**:
```dart
Config(maxBatchSize: 50)
```

---

### autoSyncThreshold

**Type**: `int`

**Description**: Trigger sync when queue reaches this size.

**Range**: `1` to `maxBatchSize`

**Default**: `0` (sync on every location if `batchSync: false`)

**Example**:
```dart
Config(
  batchSync: true,
  maxBatchSize: 100,
  autoSyncThreshold: 25, // Sync when 25 locations queued
)
```

---

### disableAutoSyncOnCellular

**Type**: `bool`

**Description**: Disable automatic sync when on cellular connection.

**Default**: `false`

**Use Case**: Save mobile data.

**Example**:
```dart
Config(disableAutoSyncOnCellular: true)
```

---

### locationTimeout

**Type**: `int` (milliseconds)

**Description**: Timeout for acquiring a single location.

**Range**: `1000` to `60000`

**Default**: `10000` (10 seconds)

**Example**:
```dart
Config(locationTimeout: 15000)
```

---

### httpTimeout

**Type**: `int` (milliseconds)

**Description**: Timeout for HTTP sync requests.

**Range**: `1000` to `120000`

**Default**: `30000` (30 seconds)

**Example**:
```dart
Config(httpTimeout: 60000)
```

---

### maxRetry

**Type**: `int`

**Description**: Maximum retry attempts for failed sync.

**Range**: `0` to `10`

**Default**: `3`

**Example**:
```dart
Config(maxRetry: 5)
```

---

### retryDelay

**Type**: `int` (milliseconds)

**Description**: Initial delay before retrying failed sync.

**Range**: `1000` to `300000`

**Default**: `10000` (10 seconds)

**Example**:
```dart
Config(retryDelay: 5000)
```

---

### retryDelayMultiplier

**Type**: `double`

**Description**: Exponential backoff multiplier for successive retries.

**Range**: `1.0` to `10.0`

**Default**: `2.0`

**Behavior**: Each retry delay = previous delay × multiplier

**Example**:
```dart
Config(
  retryDelay: 5000,        // First retry: 5s
  retryDelayMultiplier: 2.0, // Second: 10s, Third: 20s, Fourth: 40s
)
```

---

### maxRetryDelay

**Type**: `int` (milliseconds)

**Description**: Maximum delay between retries (caps exponential backoff).

**Range**: `1000` to `3600000`

**Default**: `300000` (5 minutes)

**Example**:
```dart
Config(maxRetryDelay: 120000) // Max 2 minutes
```

---

### queueMaxDays

**Type**: `int`

**Description**: Maximum days to keep locations in queue.

**Range**: `1` to `365`

**Default**: `7`

**Example**:
```dart
Config(queueMaxDays: 14)
```

---

### queueMaxRecords

**Type**: `int`

**Description**: Maximum number of locations to keep in queue.

**Range**: `100` to `100000`

**Default**: `10000`

**Example**:
```dart
Config(queueMaxRecords: 50000)
```

---

### idempotencyHeader

**Type**: `String`

**Description**: HTTP header name for idempotency key.

**Default**: `null`

**Example**:
```dart
Config(idempotencyHeader: 'X-Idempotency-Key')
// Sends: X-Idempotency-Key: <unique-uuid>
```

---

### bgTaskId

**Type**: `String`

**Platform**: iOS only

**Description**: Background task identifier for iOS background refresh.

**Default**: `null`

**Requirements**: Must be registered in `Info.plist`.

**Example**:
```dart
Config(bgTaskId: 'com.example.app.refresh')
```

---

## Persistence Settings

### persistMode

**Type**: `PersistMode` enum

**Description**: What to persist to local database.

**Options**:
- `PersistMode.none` - Don't persist
- `PersistMode.location` - Persist locations only
- `PersistMode.geofence` - Persist geofence events only
- `PersistMode.all` - Persist everything

**Default**: `PersistMode.all`

**Example**:
```dart
Config(persistMode: PersistMode.location)
```

---

### maxDaysToPersist

**Type**: `int`

**Description**: Maximum days to keep persisted data.

**Range**: `1` to `365`

**Default**: `7`

**Example**:
```dart
Config(maxDaysToPersist: 30)
```

---

### maxRecordsToPersist

**Type**: `int`

**Description**: Maximum records to persist.

**Range**: `100` to `100000`

**Default**: `10000`

**Example**:
```dart
Config(maxRecordsToPersist: 50000)
```

---

### locationTemplate

**Type**: `String`

**Description**: Template string for location payload format (advanced).

**Default**: `null`

**Example**:
```dart
Config(locationTemplate: '{"lat":<%= latitude %>,"lon":<%= longitude %>}')
```

---

### geofenceTemplate

**Type**: `String`

**Description**: Template string for geofence payload format (advanced).

**Default**: `null`

---

### httpRootProperty

**Type**: `String`

**Description**: Root JSON property name for locations array.

**Default**: `"locations"`

**Example**:
```dart
Config(httpRootProperty: 'data')
// Payload: {"data": [{...}, {...}]}
```

---

## Scheduling Settings

### schedule

**Type**: `List<String>`

**Description**: Cron-like schedule for enabling/disabling tracking.

**Format**: `"DAY TIME-TIME"` (e.g., `"1 09:00-17:00"` = Monday 9am-5pm)

**Day Numbers**: 1=Monday, 2=Tuesday, ..., 7=Sunday

**Example**:
```dart
Config(
  schedule: [
    '1-5 08:00-18:00', // Monday-Friday, 8am-6pm
    '6 10:00-14:00',   // Saturday, 10am-2pm
  ],
)
```

---

### scheduleUseAlarmManager

**Type**: `bool`

**Platform**: Android only

**Description**: Use AlarmManager for scheduled tracking (more reliable but battery impact).

**Default**: `false`

**Example**:
```dart
Config(scheduleUseAlarmManager: true)
```

---

### forceReloadOnBoot

**Type**: `bool`

**Description**: Force configuration reload on device reboot.

**Default**: `false`

---

### forceReloadOnLocationChange

**Type**: `bool`

**Description**: Reload configuration on each location change.

**Default**: `false`

---

### forceReloadOnMotionChange

**Type**: `bool`

**Description**: Reload configuration on motion state change.

**Default**: `false`

---

### forceReloadOnGeofence

**Type**: `bool`

**Description**: Reload configuration on geofence event.

**Default**: `false`

---

### forceReloadOnHeartbeat

**Type**: `bool`

**Description**: Reload configuration on heartbeat event.

**Default**: `false`

---

### forceReloadOnSchedule

**Type**: `bool`

**Description**: Reload configuration on schedule change.

**Default**: `false`

---

### enableTimestampMeta

**Type**: `bool`

**Description**: Include timestamp metadata in location objects.

**Default**: `true`

---

## Notification Settings

See `NotificationConfig` for Android foreground service notification.

```dart
NotificationConfig(
  title: 'Location Tracking',
  text: 'App is tracking your location',
  channelId: 'locus_tracking',
  channelName: 'Location Tracking',
  color: '#FF0000',
  smallIcon: 'ic_notification',
  largeIcon: 'ic_large_notification',
  priority: 2, // HIGH
)
```

**See**: [Platform Configuration](../setup/platform-configuration.md)

---

## Advanced Features

### logLevel

**Type**: `LogLevel` enum

**Options**: `off`, `error`, `warning`, `info`, `debug`, `verbose`

**Default**: `LogLevel.info`

**Example**:
```dart
Config(logLevel: LogLevel.verbose)
```

---

### logMaxDays

**Type**: `int`

**Description**: Days to keep logs.

**Default**: `3`

**Example**:
```dart
Config(logMaxDays: 7)
```

---

### heartbeatInterval

**Type**: `int` (seconds)

**Description**: Interval for idle heartbeat events.

**Default**: Preset-dependent (30-300 seconds)

**Example**:
```dart
Config(heartbeatInterval: 120) // Every 2 minutes
```

---

### backgroundPermissionRationale

**Type**: `PermissionRationale`

**Description**: Custom messaging for background permission request.

**Example**:
```dart
Config(
  backgroundPermissionRationale: PermissionRationale(
    title: 'Background Location Permission',
    message: 'We need background location to track your trips even when the app is closed.',
    positiveAction: 'Allow',
    negativeAction: 'Deny',
  ),
)
```

---

### triggerActivities

**Type**: `List<ActivityType>`

**Description**: Activities that trigger location updates.

**Options**: `still`, `on_foot`, `walking`, `running`, `on_bicycle`, `in_vehicle`

**Default**: All activities

**Example**:
```dart
Config(
  triggerActivities: [
    ActivityType.in_vehicle,
    ActivityType.on_bicycle,
  ],
  // Only track when driving or cycling
)
```

---

### adaptiveTracking

**Type**: `AdaptiveTrackingConfig`

**Description**: Adaptive tracking configuration.

**Example**:
```dart
Config(
  adaptiveTracking: AdaptiveTrackingConfig(
    speedTiers: SpeedTiers.driving,
    batteryThresholds: BatteryThresholds.conservative,
    stationaryGpsOff: true,
  ),
)
```

**See**: [Battery Optimization](../advanced/battery-optimization.md)

---

### lowBattery

**Type**: `LowBatteryConfig`

**Description**: Behavior when battery is low.

**Example**:
```dart
Config(
  lowBattery: LowBatteryConfig(
    threshold: 20, // Switch mode at 20% battery
    config: ConfigPresets.lowPower,
  ),
)
```

---

### spoofDetection

**Type**: `SpoofDetectionConfig`

**Description**: Spoof/mock location detection.

**Example**:
```dart
Config(
  spoofDetection: SpoofDetectionConfig(
    action: SpoofDetectionAction.flag,
    strictMode: true,
  ),
)
```

---

## Full Configuration Example

```dart
await Locus.ready(
  Config(
    // Location
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 25,
    locationUpdateInterval: 5000,
    activityRecognitionInterval: 10000,
    stopTimeout: 5,
    speedJumpFilter: 50,
    
    // Background
    enableHeadless: true,
    foregroundService: true,
    stopOnTerminate: false,
    startOnBoot: true,
    preventSuspend: true,
    
    // Geofencing
    geofenceModeHighAccuracy: true,
    maxMonitoredGeofences: 50,
    
    // HTTP Sync
    url: 'https://your-server.com/locations',
    method: 'POST',
    headers: {
      'Authorization': 'Bearer YOUR_TOKEN',
      'Content-Type': 'application/json',
    },
    extras: {
      'userId': '12345',
      'deviceId': 'abc123',
    },
    autoSync: true,
    batchSync: true,
    maxBatchSize: 50,
    autoSyncThreshold: 20,
    maxRetry: 5,
    retryDelay: 5000,
    retryDelayMultiplier: 2.0,
    
    // Persistence
    persistMode: PersistMode.all,
    maxDaysToPersist: 14,
    queueMaxDays: 7,
    queueMaxRecords: 50000,
    
    // Notification
    notification: NotificationConfig(
      title: 'Location Tracking',
      text: 'App is tracking your location',
      channelId: 'locus_tracking',
      color: '#00FF00',
      priority: 2,
    ),
    
    // Advanced
    logLevel: LogLevel.debug,
    heartbeatInterval: 120,
    adaptiveTracking: AdaptiveTrackingConfig.balanced,
    spoofDetection: SpoofDetectionConfig(
      action: SpoofDetectionAction.flag,
    ),
  ),
);
```

---

**Related Documentation:**
- [Quick Start](../guides/quickstart.md)
- [Presets Usage](configuration.md)
- [Battery Optimization](../advanced/battery-optimization.md)
- [HTTP Sync Guide](../advanced/http-sync-guide.md)
