# Platform Configuration

Background location tracking requires specific permissions and configurations for each platform.

## Android Requirements

### 1. Permissions

Locus requires the following in your `AndroidManifest.xml` (automated by `dart run locus:setup`):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

### 2. Foreground Service

To track while the app is in the background, Locus runs a Foreground Service. You must provide a `NotificationConfig` in your `Config`.

## iOS Requirements

### 1. Capabilities

Enable the following **Background Modes** in Xcode:

- Location updates
- Background fetch
- Background processing (optional, for sync)

### 2. Info.plist

Add descriptions for the following keys (automated by `dart run locus:setup`):

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to track your trips even in the background.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your trips.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>
```

## Permission Assistant

Locus includes a `PermissionAssistant` to guide users through the complex multi-step permission flow:

```dart
final status = await PermissionAssistant.requestBackgroundWorkflow(
  config: myConfig,
  delegate: MyPermissionDelegate(),
);
```

## Precise Location Checks

`Locus.requestPermission()` tells you whether the required permission flow completed, but Android and iOS can still grant reduced accuracy. If your product requires high-accuracy tracking, check precise access before starting:

```dart
final precise = await Locus.hasPreciseLocationPermission();
if (!precise) {
  // Show app-specific guidance: enable Precise Location / exact location.
}
```

On Android this checks `ACCESS_FINE_LOCATION`. On iOS it checks `accuracyAuthorization == fullAccuracy`.

---

**Next:** [Testing Guide](../testing/unit-testing.md)
