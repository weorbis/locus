# Headless Execution Guide

Headless execution allows your Flutter/Dart code to run in the background even when your app is terminated. This guide explains how to implement, debug, and optimize headless background tasks with Locus.

## Table of Contents

1. [What is Headless Execution?](#what-is-headless-execution)
2. [When to Use Headless Mode](#when-to-use-headless-mode)
3. [Platform Support](#platform-support)
4. [Implementation](#implementation)
5. [Headless Events](#headless-events)
6. [Headless Sync Body Builder](#headless-sync-body-builder)
7. [Limitations and Constraints](#limitations-and-constraints)
8. [Debugging Headless Code](#debugging-headless-code)
9. [Best Practices](#best-practices)
10. [Examples](#examples)

---

## What is Headless Execution?

Headless execution allows Dart code to run in the background when:
- Your app is terminated (killed by user or OS)
- A geofence event occurs while app is not running
- A location update is received in the background
- Device reboots and tracking needs to resume

Traditional Flutter apps can't execute Dart code when terminated. Headless mode creates a separate Dart isolate in the background to handle events.

### Architecture

```
App Terminated
     ↓
Native Event (Location, Geofence, Boot)
     ↓
HeadlessService (Android) / Background Processing (iOS)
     ↓
Flutter Engine Spawned
     ↓
Your Headless Callback Executed
     ↓
Event Processed
     ↓
Engine Destroyed (after idle timeout)
```

---

## When to Use Headless Mode

### Use Headless Mode For:

✅ **Processing background location updates** when app is killed
✅ **Handling geofence enter/exit events** in background
✅ **Custom sync logic** that needs to run without app
✅ **Logging or analytics** for background events
✅ **Triggering local notifications** for geofence events
✅ **Updating local database** with background data

### Don't Use Headless Mode For:

❌ **UI updates** - Headless runs without UI context
❌ **Long-running tasks** - Limited execution time (60s typical)
❌ **Heavy processing** - Drains battery, may be killed by OS
❌ **Frequent events** - Each invocation spawns engine overhead

### Alternative Approaches:

If your use case is covered by built-in features, prefer those:
- **HTTP Sync**: Built-in, no headless needed
- **Local Persistence**: Automatic, no headless needed
- **Geofence Detection**: Built-in, headless optional for custom logic

---

## Platform Support

### Android

✅ **Full support** via `HeadlessService` (JobIntentService)
- Runs after app termination
- Survives device reboot (with `startOnBoot: true`)
- Background location updates
- Geofence events
- Motion changes

### iOS

⚠️ **Limited support** due to iOS restrictions
- Background location updates work if app was running recently
- Geofence events work in background
- Limited execution time
- May not survive app termination for extended periods

---

## Implementation

### Step 1: Define Headless Callback

Create a **top-level or static function** (not an instance method) with the `@pragma('vm:entry-point')` annotation:

```dart
import 'package:locus/locus.dart';

@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  print('[Headless] Event received: ${event.type}');
  
  switch (event.type) {
    case 'location':
      _handleLocation(event);
      break;
    case 'geofence':
      _handleGeofence(event);
      break;
    case 'motionchange':
      _handleMotionChange(event);
      break;
    case 'boot':
      _handleBoot(event);
      break;
    default:
      print('[Headless] Unknown event: ${event.type}');
  }
}

void _handleLocation(HeadlessEvent event) {
  final location = event.location;
  if (location != null) {
    print('[Headless] Location: ${location.coords.latitude}, ${location.coords.longitude}');
    // Process location (log, analyze, trigger notification, etc.)
  }
}

void _handleGeofence(HeadlessEvent event) {
  final geofence = event.geofence;
  final action = event.action;
  
  if (geofence != null && action != null) {
    print('[Headless] Geofence ${geofence.identifier}: $action');
    
    if (action == 'ENTER') {
      // Trigger notification
      // Update local database
      // Send analytics event
    }
  }
}

void _handleMotionChange(HeadlessEvent event) {
  final isMoving = event.isMoving;
  print('[Headless] Motion changed: ${isMoving ? "moving" : "stationary"}');
}

void _handleBoot(HeadlessEvent event) {
  print('[Headless] Device rebooted, tracking resumed');
}
```

### Step 2: Register Headless Task

Register your callback in `main()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register headless task
  await Locus.registerHeadlessTask(headlessCallback);
  
  // Initialize Locus
  await Locus.ready(ConfigPresets.balanced.copyWith(
    enableHeadless: true,
    stopOnTerminate: false,
    startOnBoot: true,
  ));
  
  runApp(MyApp());
}
```

### Step 3: Enable Headless in Config

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  enableHeadless: true,
  stopOnTerminate: false,    // Continue after app is killed
  startOnBoot: true,         // Resume after reboot
  foregroundService: true,   // Required on Android
));
```

---

## Headless Events

The `HeadlessEvent` object contains event data:

```dart
class HeadlessEvent {
  final String type;           // Event type: 'location', 'geofence', etc.
  final Location? location;    // Location data (if available)
  final Geofence? geofence;    // Geofence data (if available)
  final String? action;        // Action: 'ENTER', 'EXIT', 'DWELL'
  final bool? isMoving;        // Motion state (if available)
  final Activity? activity;    // Activity type (if available)
  final Map<String, dynamic>? extras; // Additional data
}
```

### Event Types

| Type | Description | Available Data |
|------|-------------|----------------|
| `location` | Location update | `location`, `activity`, `isMoving` |
| `geofence` | Geofence event | `geofence`, `action`, `location` |
| `motionchange` | Motion state changed | `isMoving`, `location`, `activity` |
| `boot` | Device rebooted | None |
| `heartbeat` | Periodic heartbeat | `location` |

### Example: Comprehensive Handler

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  final timestamp = DateTime.now().toIso8601String();
  
  switch (event.type) {
    case 'location':
      if (event.location != null) {
        _logEvent('location', {
          'timestamp': timestamp,
          'lat': event.location!.coords.latitude,
          'lon': event.location!.coords.longitude,
          'accuracy': event.location!.coords.accuracy,
          'activity': event.activity?.type.name,
        });
      }
      break;
      
    case 'geofence':
      if (event.geofence != null && event.action != null) {
        _logEvent('geofence', {
          'timestamp': timestamp,
          'identifier': event.geofence!.identifier,
          'action': event.action,
        });
        
        // Trigger local notification
        if (event.action == 'ENTER') {
          _showNotification(
            'Geofence Entered',
            'You entered ${event.geofence!.identifier}',
          );
        }
      }
      break;
      
    case 'motionchange':
      _logEvent('motion', {
        'timestamp': timestamp,
        'isMoving': event.isMoving,
        'activity': event.activity?.type.name,
      });
      break;
      
    case 'boot':
      _logEvent('boot', {
        'timestamp': timestamp,
        'message': 'Tracking resumed after reboot',
      });
      break;
  }
}

void _logEvent(String type, Map<String, dynamic> data) {
  // Log to file, local database, or analytics
  print('[Headless $type] $data');
}

void _showNotification(String title, String body) {
  // Use flutter_local_notifications or similar
  // Must be initialized in headless context
}
```

---

## Headless Sync Body Builder

For custom HTTP sync payloads in headless mode, register a top-level sync body builder:

### Standard Sync Body Builder (Foreground Only)

```dart
// This works when app is running
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'device_id': extras['deviceId'],
    'locations': locations.map((l) => l.toJson()).toList(),
  };
});
```

### Headless Sync Body Builder

```dart
@pragma('vm:entry-point')
Future<Map<String, dynamic>> headlessSyncBuilder(SyncBodyContext ctx) async {
  return {
    'device_id': ctx.extras['deviceId'] ?? 'unknown',
    'timestamp': DateTime.now().toIso8601String(),
    'batch': ctx.locations.map((location) => {
      'latitude': location.coords.latitude,
      'longitude': location.coords.longitude,
      'accuracy': location.coords.accuracy,
      'timestamp': location.timestamp.toIso8601String(),
      'speed': location.coords.speed,
      'heading': location.coords.heading,
      'activity': location.activity.type.name,
    }).toList(),
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register headless sync builder
  await Locus.registerHeadlessSyncBodyBuilder(headlessSyncBuilder);
  
  // Register headless task
  await Locus.registerHeadlessTask(headlessCallback);
  
  await Locus.ready(ConfigPresets.balanced.copyWith(
    enableHeadless: true,
    url: 'https://api.example.com/locations',
    autoSync: true,
    batchSync: true,
  ));
  
  runApp(MyApp());
}
```

### SyncBodyContext

```dart
class SyncBodyContext {
  final List<Location> locations;  // Pending locations to sync
  final Map<String, dynamic> extras;  // Extras from Config
}
```

---

## Limitations and Constraints

### Execution Time Limits

- **Android**: ~60 seconds before JobIntentService may be killed
- **iOS**: ~30 seconds for background tasks

Keep headless logic fast and efficient.

### No UI Context

Headless code runs without `BuildContext`. You cannot:
- Update widgets directly
- Navigate routes
- Show dialogs

You can:
- Update local database
- Send network requests
- Show local notifications
- Log events

### Engine Startup Overhead

Each headless invocation spawns a Flutter engine:
- ~200-500ms startup time
- Memory overhead
- Battery impact

Avoid triggering headless callbacks too frequently.

### iOS Restrictions

iOS heavily restricts background processing:
- Limited execution after app termination
- May not receive events if app hasn't run recently
- Background app refresh must be enabled
- System may throttle or deny background execution

### Plugin Access

Not all Flutter plugins work in headless mode:
- Some require UI context
- Some don't support background isolates
- Test plugins individually

Known to work:
- `shared_preferences`
- `sqflite`
- `http`
- `flutter_local_notifications` (with initialization)

### Debugging Challenges

Standard Flutter debugging doesn't work for headless:
- No hot reload
- No DevTools
- Must use print statements or logging
- Check native logs (logcat, Xcode console)

---

## Debugging Headless Code

### Android Debugging

**View Logs:**
```bash
adb logcat | grep -i "flutter\|locus"
```

**Check Service Status:**
```bash
adb shell dumpsys activity services | grep HeadlessService
```

**Test Headless Callback:**
1. Start app
2. Kill app (swipe away from recent apps)
3. Trigger event (move location, enter geofence)
4. Check logcat for headless logs

### iOS Debugging

**View Logs:**
Open Xcode → Window → Devices and Simulators → Select device → View device logs

**Simulate Background:**
1. Start app in Xcode
2. Debug → Simulate Background Fetch
3. Check console for headless logs

### Common Issues

**Headless callback not firing:**
- Verify `enableHeadless: true` in Config
- Check `@pragma('vm:entry-point')` annotation
- Ensure function is top-level or static
- Verify `stopOnTerminate: false`

**HeadlessRegistrationException:**
```dart
on HeadlessRegistrationException catch (e) {
  print('Registration failed: ${e.message}');
  print('Suggestion: ${e.suggestion}');
}
```

Solution: Use top-level function with proper annotation.

**Callback executes but logic fails:**
- Add extensive logging
- Check native logs (not Flutter console)
- Verify plugins support background execution
- Test on real device (not just simulator)

---

## Best Practices

### 1. Keep Logic Simple

```dart
// ✅ Good: Fast, minimal processing
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  if (event.type == 'location' && event.location != null) {
    _logToFile(event.location!);
  }
}

// ❌ Bad: Heavy processing, long execution
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  // Multiple API calls
  // Complex calculations
  // Large file I/O
  // May timeout or drain battery
}
```

### 2. Handle Errors Gracefully

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  try {
    // Your logic
  } catch (e, stackTrace) {
    print('[Headless Error] $e');
    print(stackTrace);
    // Log error for debugging
  }
}
```

### 3. Use Appropriate Log Levels

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) {
  // Conditional logging based on build mode
  const isDebug = bool.fromEnvironment('dart.vm.product') == false;
  
  if (isDebug) {
    print('[Headless Debug] ${event.type}');
  }
  
  // Always log critical events
  if (event.type == 'geofence' && event.action == 'ENTER') {
    print('[Headless] Critical geofence entry');
  }
}
```

### 4. Offload to Server

For complex processing, send data to server:

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) async {
  if (event.type == 'location' && event.location != null) {
    // Send to server for processing
    await _sendToServer(event.location!);
  }
}

Future<void> _sendToServer(Location location) async {
  try {
    await http.post(
      Uri.parse('https://api.example.com/headless-event'),
      body: jsonEncode(location.toJson()),
    );
  } catch (e) {
    // Queue for retry (use local database)
    print('[Headless] Failed to send: $e');
  }
}
```

### 5. Test Thoroughly

Test scenarios:
- App killed by user
- Device reboot
- Low battery
- Poor network connectivity
- Multiple rapid events
- iOS vs Android differences

---

## Examples

### Example 1: Geofence Notifications

```dart
@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) async {
  if (event.type == 'geofence' && event.action == 'ENTER') {
    final geofence = event.geofence;
    if (geofence != null) {
      await _showLocalNotification(
        'Geofence Alert',
        'You entered ${geofence.identifier}',
      );
    }
  }
}

Future<void> _showLocalNotification(String title, String body) async {
  // Initialize plugin (do once, cache instance)
  final plugin = FlutterLocalNotificationsPlugin();
  
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  
  await plugin.initialize(settings);
  
  await plugin.show(
    0,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence_channel',
        'Geofence Alerts',
        importance: Importance.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}
```

### Example 2: Local Database Logging

```dart
import 'package:sqflite/sqflite.dart';

Database? _db;

@pragma('vm:entry-point')
void headlessCallback(HeadlessEvent event) async {
  await _initDatabase();
  
  if (event.type == 'location' && event.location != null) {
    await _logLocation(event.location!);
  }
}

Future<void> _initDatabase() async {
  if (_db != null) return;
  
  _db = await openDatabase(
    'headless_logs.db',
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          latitude REAL,
          longitude REAL,
          accuracy REAL,
          timestamp TEXT
        )
      ''');
    },
  );
}

Future<void> _logLocation(Location location) async {
  await _db?.insert('locations', {
    'latitude': location.coords.latitude,
    'longitude': location.coords.longitude,
    'accuracy': location.coords.accuracy,
    'timestamp': location.timestamp.toIso8601String(),
  });
}
```

### Example 3: Conditional Sync

```dart
@pragma('vm:entry-point')
Future<Map<String, dynamic>> headlessSyncBuilder(SyncBodyContext ctx) async {
  // Only sync high-accuracy locations in headless mode
  final filteredLocations = ctx.locations.where((l) => l.coords.accuracy <= 20).toList();
  
  if (filteredLocations.isEmpty) {
    // Skip sync if no good locations
    return {};
  }
  
  return {
    'timestamp': DateTime.now().toIso8601String(),
    'count': filteredLocations.length,
    'locations': filteredLocations.map((l) => l.toJson()).toList(),
  };
}
```

---

## Summary

Headless execution is powerful but comes with complexity:
- ✅ Use for critical background logic
- ✅ Keep execution fast and simple
- ✅ Test thoroughly on real devices
- ✅ Handle errors gracefully
- ⚠️ Be aware of platform limitations
- ⚠️ Monitor battery impact
- ❌ Avoid for UI updates or heavy processing

For most use cases, built-in HTTP sync and geofencing are sufficient without headless mode.

---

**Related Documentation:**
- [Configuration Reference](../core/configuration-reference.md)
- [HTTP Sync Guide](http-sync-guide.md)
- [Geofencing](geofencing.md)
- [Troubleshooting Guide](../guides/troubleshooting.md)
