# Platform-Specific Setup Guide

Detailed iOS and Android setup instructions for the Locus SDK, including permissions, capabilities, build configurations, and troubleshooting.

## Table of Contents

1. [Android Setup](#android-setup)
2. [iOS Setup](#ios-setup)
3. [Automated Setup](#automated-setup)
4. [Version Requirements](#version-requirements)
5. [Troubleshooting](#troubleshooting)

---

## Android Setup

### Minimum Requirements

- **Minimum SDK**: 21 (Android 5.0 Lollipop)
- **Target SDK**: 33+ (Android 13+)
- **Compile SDK**: 33+
- **Gradle**: 7.0+
- **Kotlin**: 1.7+

### 1. AndroidManifest.xml Permissions

Add required permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">

    <!-- Location Permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    
    <!-- Background Location (Android 10+) -->
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    
    <!-- Foreground Service -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    
    <!-- Internet for HTTP sync -->
    <uses-permission android:name="android.permission.INTERNET" />
    
    <!-- Boot receiver -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    
    <!-- Activity Recognition (optional) -->
    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
    
    <!-- Wake Lock for background processing -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:name="${applicationName}"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Your activities -->
        <activity android:name=".MainActivity" ...>
            ...
        </activity>
        
    </application>

</manifest>
```

### 2. Gradle Configuration

**android/build.gradle.kts** (project-level):

```kotlin
buildscript {
    ext.kotlin_version = '1.9.0'
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
```

**android/app/build.gradle.kts** (app-level):

```kotlin
android {
    namespace = "com.example.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlin_version"
    
    // Google Play Services Location
    implementation "com.google.android.gms:play-services-location:21.0.1"
    
    // AndroidX
    implementation "androidx.core:core-ktx:1.12.0"
    implementation "androidx.work:work-runtime-ktx:2.9.0"
}
```

### 3. ProGuard Rules

If using ProGuard/R8, add to `android/app/proguard-rules.pro`:

```proguard
# Locus SDK
-keep class dev.locus.** { *; }
-keep interface dev.locus.** { *; }

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
```

### 4. Notification Icon

For foreground service notification, add notification icons to:

```
android/app/src/main/res/
  drawable/
    ic_notification.png (or .xml for vector)
  mipmap-hdpi/
    ic_large_notification.png
  mipmap-xhdpi/
    ic_large_notification.png
  mipmap-xxhdpi/
    ic_large_notification.png
  mipmap-xxxhdpi/
    ic_large_notification.png
```

Or use default:
```dart
NotificationConfig(
  smallIcon: 'ic_notification', // Defaults to app icon if not found
)
```

### 5. Android 12+ Foreground Service

For Android 12+, declare foreground service type in AndroidManifest.xml:

```xml
<application>
    <service
        android:name="dev.locus.service.ForegroundService"
        android:foregroundServiceType="location"
        android:exported="false" />
</application>
```

### 6. Battery Optimization

Guide users to disable battery optimization:

```dart
final state = await Locus.getState();
if (state.batteryOptimizationEnabled == true) {
  // Show dialog explaining why
  // Then open settings:
  // Settings → Apps → Your App → Battery → Unrestricted
}
```

### 7. Google Play Services

Locus requires Google Play Services. Check availability:

```dart
// Locus automatically checks on Android
// If unavailable, appropriate error is thrown
```

---

## iOS Setup

### Minimum Requirements

- **Minimum iOS**: 11.0
- **Xcode**: 14.0+
- **Swift**: 5.0+
- **CocoaPods**: 1.11+

### 1. Info.plist Permissions

Add to `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Location Permissions -->
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>We need your location to track trips even when the app is in the background.</string>
    
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>We need your location to track your trips.</string>
    
    <key>NSLocationAlwaysUsageDescription</key>
    <string>We need your location to track trips in the background.</string>
    
    <!-- Motion & Fitness (optional) -->
    <key>NSMotionUsageDescription</key>
    <string>We use motion data to detect your activity and optimize battery usage.</string>
    
    <!-- Background Modes -->
    <key>UIBackgroundModes</key>
    <array>
        <string>location</string>
        <string>fetch</string>
        <string>processing</string>
    </array>
    
    <!-- Background Task Identifiers -->
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER).refresh</string>
    </array>
    
    <!-- Other app settings -->
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    ...
</dict>
</plist>
```

### 2. Xcode Capabilities

Open `ios/Runner.xcworkspace` in Xcode:

1. Select **Runner** project
2. Select **Runner** target
3. Navigate to **Signing & Capabilities** tab
4. Click **+ Capability**

Add:
- ✅ **Background Modes**
  - ✅ Location updates
  - ✅ Background fetch
  - ✅ Background processing
- ✅ **Push Notifications** (if using remote notifications)

### 3. Podfile Configuration

**ios/Podfile**:

```ruby
platform :ios, '11.0'

# Uncomment if using Swift
use_frameworks!

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # CocoaPods post-install hook
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      flutter_additional_ios_build_settings(target)
      
      target.build_configurations.each do |config|
        # Set minimum deployment target
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
        
        # Enable bitcode (optional)
        config.build_settings['ENABLE_BITCODE'] = 'NO'
      end
    end
  end
end
```

Run after editing:
```bash
cd ios
pod install
```

### 4. App Delegate Configuration

**ios/Runner/AppDelegate.swift**:

```swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Request background app refresh (if using bgTaskId)
    if #available(iOS 13.0, *) {
      UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Background fetch handler
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Locus handles this automatically
    completionHandler(.newData)
  }
}
```

### 5. Background Task Registration

If using `bgTaskId` for background refresh:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  bgTaskId: 'com.example.app.refresh',
));
```

Ensure it matches `Info.plist`:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.example.app.refresh</string>
</array>
```

### 6. Precise Location (iOS 14+)

iOS 14+ allows users to select reduced accuracy. Handle this:

```dart
Locus.location.stream.listen((location) {
  if (location.coords.accuracy > 1000) {
    // Likely reduced accuracy mode
    // Prompt user: Settings → App → Precise Location → ON
  }
});
```

### 7. Location Button (iOS 15+)

iOS 15+ provides a temporary location permission button:

```dart
// Use CoreLocationUI framework (requires separate integration)
// Or guide user to grant "Always" permission
```

### 8. Build Settings

In Xcode, configure build settings:

**Runner → Build Settings**:
- **iOS Deployment Target**: 11.0 or higher
- **Swift Language Version**: 5.x
- **Enable Bitcode**: No
- **Architectures**: arm64 (remove armv7 for iOS 11+)

---

## Automated Setup

Locus provides CLI tools to automate platform configuration:

### Setup Command

```bash
dart run locus:setup
```

This command:
- ✅ Adds required permissions to AndroidManifest.xml
- ✅ Adds usage descriptions to Info.plist
- ✅ Configures background modes (iOS)
- ✅ Verifies Gradle configuration
- ✅ Checks for common issues

### Doctor Command

Check configuration health:

```bash
dart run locus:doctor
```

Outputs:
```
✅ Android manifest permissions
✅ iOS Info.plist permissions
✅ iOS background modes
⚠️  Background location permission description missing
❌ Foreground service type not declared (Android 12+)
```

Fix issues based on output.

---

## Version Requirements

### Android

| Component | Minimum Version | Recommended |
|-----------|----------------|-------------|
| Gradle | 7.0 | 8.1+ |
| Android Gradle Plugin | 7.0.0 | 8.1+ |
| Kotlin | 1.7.0 | 1.9+ |
| compileSdk | 31 | 34 |
| minSdk | 21 | 21 |
| targetSdk | 31 | 34 |
| Google Play Services Location | 20.0.0 | 21.0.1 |
| AndroidX Core | 1.6.0 | 1.12+ |

### iOS

| Component | Minimum Version | Recommended |
|-----------|----------------|-------------|
| iOS | 11.0 | 15.0+ |
| Xcode | 12.0 | 15.0+ |
| Swift | 5.0 | 5.9+ |
| CocoaPods | 1.10 | 1.14+ |

### Flutter

| Component | Minimum Version | Recommended |
|-----------|----------------|-------------|
| Flutter | 3.0.0 | 3.16+ |
| Dart | 2.17.0 | 3.2+ |

---

## Troubleshooting

### Android Issues

#### "Google Play Services not available"

**Cause**: Device doesn't have Google Play Services.

**Solution**: 
- Test on device with Play Services
- Check emulator has Play Services installed
- Use device with Google Mobile Services

#### "Permission denial: starting foreground service"

**Cause**: Android 12+ requires foreground service type.

**Solution**: Add to AndroidManifest.xml:
```xml
<service
    android:name="dev.locus.service.ForegroundService"
    android:foregroundServiceType="location" />
```

#### "Background location permission denied"

**Cause**: Android 10+ requires separate background permission.

**Solution**: Request in two steps:
```dart
// 1. Request "While using app"
await Locus.requestPermission();

// 2. Then request "Allow all the time" (separate dialog)
// Use PermissionAssistant for guided flow
```

#### Gradle build fails

**Cause**: Version incompatibility.

**Solution**: Update Gradle and dependencies:
```bash
cd android
./gradlew wrapper --gradle-version 8.1
```

### iOS Issues

#### "Background execution not working"

**Cause**: Background modes not enabled.

**Solution**: 
1. Open Xcode
2. Runner → Signing & Capabilities
3. Add **Background Modes**
4. Enable **Location updates**

#### "Permission dialog not showing"

**Cause**: Missing usage description in Info.plist.

**Solution**: Add all three location descriptions:
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationAlwaysUsageDescription`

#### "Location services must be enabled"

**Cause**: User disabled location system-wide.

**Solution**: Check and prompt:
```dart
final state = await Locus.getState();
if (!state.locationServicesEnabled) {
  // Show dialog: "Enable Location Services in Settings"
}
```

#### Pod install fails

**Cause**: CocoaPods cache issue.

**Solution**:
```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install
```

#### Simulator location not updating

**Cause**: Simulator needs manual location.

**Solution**: 
- Debug → Location → Custom Location
- Or use GPX file: Debug → Simulate Location

### Both Platforms

#### "Insufficient permissions" exception

**Cause**: Location permission not granted.

**Solution**:
```dart
final granted = await Locus.requestPermission();
if (!granted) {
  // Show rationale and guide to settings
}
```

#### Background tracking stops after app kill

**Cause**: `stopOnTerminate: true` (default).

**Solution**:
```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  stopOnTerminate: false,
  startOnBoot: true,
  foregroundService: true, // Android
));
```

#### High battery drain

**Cause**: Configuration too aggressive.

**Solution**: Use lower-power preset:
```dart
await Locus.ready(ConfigPresets.lowPower);
```

---

## Testing Setup

### Android

Test permissions on real device:
```bash
adb shell pm list permissions -d -g
adb shell dumpsys package com.example.app | grep permission
```

Check battery optimization:
```bash
adb shell dumpsys deviceidle whitelist
```

### iOS

Test background execution:
1. Run app in Xcode
2. Debug → Simulate Background Fetch
3. Check console for background logs

Test location:
1. Features → Location → Custom Location
2. Or load GPX file

---

**Related Documentation:**
- [Quick Start Guide](../guides/quickstart.md)
- [Configuration Reference](../core/configuration-reference.md)
- [Troubleshooting Guide](../guides/troubleshooting.md)
- [Platform Configuration](platform-configuration.md)
