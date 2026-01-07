# HTTP Sync Configuration Guide

Complete guide to configuring, customizing, and debugging HTTP synchronization in the Locus SDK.

## Table of Contents

1. [Overview](#overview)
2. [Basic Setup](#basic-setup)
3. [Sync Modes](#sync-modes)
4. [Retry Logic](#retry-logic)
5. [Batching Options](#batching-options)
6. [Custom Sync Body Builders](#custom-sync-body-builders)
7. [Authentication](#authentication)
8. [Error Handling](#error-handling)
9. [Debugging Sync](#debugging-sync)
10. [Advanced Patterns](#advanced-patterns)
11. [Best Practices](#best-practices)

---

## Overview

Locus includes built-in HTTP synchronization for sending location data to your backend server. Features:

- **Automatic sync** with configurable triggers
- **Offline queueing** with SQLite persistence
- **Retry logic** with exponential backoff
- **Batch sync** for efficiency
- **Custom payload** formatting
- **Header/auth** configuration
- **Idempotency** support

---

## Basic Setup

### Minimal Configuration

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
));
```

This enables automatic sync with default settings:
- POST requests
- Batch sync enabled
- Max 100 locations per batch
- Automatic retry on failure

### Complete Configuration

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json',
  },
  params: {
    'api_key': 'YOUR_API_KEY',
  },
  extras: {
    'userId': '12345',
    'deviceId': 'abc123',
  },
  autoSync: true,
  batchSync: true,
  maxBatchSize: 50,
  autoSyncThreshold: 25,
  httpTimeout: 30000,
  maxRetry: 3,
  retryDelay: 5000,
));
```

### Default Payload Format

Without customization, payloads look like:

```json
{
  "locations": [
    {
      "timestamp": "2024-01-07T10:30:00.000Z",
      "coords": {
        "latitude": 37.7749,
        "longitude": -122.4194,
        "accuracy": 10.5,
        "altitude": 15.2,
        "altitudeAccuracy": 5.0,
        "heading": 180.5,
        "speed": 5.2,
        "speedAccuracy": 1.0
      },
      "activity": {
        "type": "in_vehicle",
        "confidence": 85
      },
      "battery": {
        "level": 0.75,
        "isCharging": false
      },
      "isMoving": true,
      "odometer": 1234.5,
      "uuid": "550e8400-e29b-41d4-a716-446655440000"
    }
  ]
}
```

---

## Sync Modes

### 1. Automatic Sync (Recommended)

Locations are synced automatically based on thresholds:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  autoSync: true,
  batchSync: true,
  maxBatchSize: 100,
  autoSyncThreshold: 50, // Sync when 50 locations queued
));
```

**Behavior**:
- Syncs when `autoSyncThreshold` reached
- Syncs when app backgrounded/foregrounded
- Syncs on network connectivity change
- Syncs periodically (heartbeat)

### 2. Manual Sync

Full control over when to sync:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  autoSync: false,
));

// Trigger sync manually
await Locus.sync.now();
```

**Use Cases**:
- Sync on user action (button press)
- Sync with other API calls
- Custom scheduling logic
- Batch with app-specific data

### 3. Immediate Sync (No Batching)

Sync each location immediately:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  autoSync: true,
  batchSync: false, // Sync each location
));
```

**Trade-offs**:
- ✅ Lowest latency
- ❌ More HTTP requests
- ❌ Higher battery/data usage
- ❌ More prone to rate limiting

---

## Retry Logic

### Exponential Backoff

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  maxRetry: 5,
  retryDelay: 5000,        // First retry: 5s
  retryDelayMultiplier: 2.0, // Second: 10s, Third: 20s, Fourth: 40s
  maxRetryDelay: 300000,   // Cap at 5 minutes
));
```

**Retry Schedule Example**:
1. Initial attempt fails
2. Wait 5 seconds → Retry 1
3. Wait 10 seconds → Retry 2
4. Wait 20 seconds → Retry 3
5. Wait 40 seconds → Retry 4
6. Wait 80 seconds (capped to 300s = 5 min) → Retry 5
7. Give up, keep in queue

### Retry on Specific Status Codes

By default, retries on:
- **5xx** errors (server errors)
- **429** (rate limit)
- **408** (timeout)
- Network errors

Does NOT retry on:
- **401** (unauthorized) - pauses sync
- **400** (bad request) - discards batch
- **404** (not found) - discards batch

### Pause and Resume

```dart
// Pause sync (e.g., on 401 unauthorized)
await Locus.sync.pause();

// Refresh auth token
await refreshAuthToken();

// Update headers and resume
await Locus.setConfig(ConfigPresets.balanced.copyWith(
  headers: {
    'Authorization': 'Bearer NEW_TOKEN',
  },
));

await Locus.sync.resume();
```

### Clear Queue

```dart
// Clear all pending locations
await Locus.sync.clearQueue();
```

---

## Batching Options

### Basic Batching

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 100,       // Max locations per request
  autoSyncThreshold: 50,   // Sync when 50 queued
));
```

### Time-Based Batching

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 100,
  heartbeatInterval: 300,  // Sync every 5 minutes via heartbeat
));

// Listen for heartbeat events
Locus.location.stream.listen((location) {
  if (location.event == 'heartbeat') {
    Locus.sync.now(); // Trigger sync
  }
});
```

### Conditional Batching

```dart
int _locationCount = 0;
DateTime? _lastSync;

Locus.location.stream.listen((location) async {
  _locationCount++;
  final now = DateTime.now();
  
  // Sync if 100 locations OR 10 minutes elapsed
  if (_locationCount >= 100 ||
      (_lastSync != null && now.difference(_lastSync!).inMinutes >= 10)) {
    await Locus.sync.now();
    _locationCount = 0;
    _lastSync = now;
  }
});
```

### Queue Management

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  queueMaxRecords: 10000, // Max queue size
  queueMaxDays: 7,        // Purge after 7 days
));

// Monitor queue size
final diagnostics = await Locus.getDiagnostics();
print('Queued: ${diagnostics.queue.length}');

if (diagnostics.queue.length > 5000) {
  // Force sync
  await Locus.sync.now();
}
```

---

## Custom Sync Body Builders

### Standard Sync Body Builder

For foreground sync customization:

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'timestamp': DateTime.now().toIso8601String(),
    'device_id': extras['deviceId'],
    'user_id': extras['userId'],
    'count': locations.length,
    'batch': locations.map((location) => {
      'lat': location.coords.latitude,
      'lng': location.coords.longitude,
      'accuracy': location.coords.accuracy,
      'timestamp': location.timestamp.toIso8601String(),
      'speed': location.coords.speed,
      'heading': location.coords.heading,
      'altitude': location.coords.altitude,
      'activity': location.activity.type.name,
      'confidence': location.activity.confidence,
      'battery': location.battery.level,
    }).toList(),
  };
});
```

### Headless Sync Body Builder

For background sync when app is terminated:

```dart
@pragma('vm:entry-point')
Future<Map<String, dynamic>> headlessSyncBuilder(SyncBodyContext ctx) async {
  return {
    'device_id': ctx.extras['deviceId'] ?? 'unknown',
    'timestamp': DateTime.now().toIso8601String(),
    'locations': ctx.locations.map((l) => {
      'lat': l.coords.latitude,
      'lon': l.coords.longitude,
      'time': l.timestamp.millisecondsSinceEpoch,
      'acc': l.coords.accuracy,
    }).toList(),
  };
}

void main() async {
  await Locus.registerHeadlessSyncBodyBuilder(headlessSyncBuilder);
  await Locus.ready(ConfigPresets.balanced.copyWith(
    enableHeadless: true,
    url: 'https://api.example.com/locations',
  ));
}
```

### Filtered Sync

Only sync high-quality locations:

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  // Filter out low-accuracy locations
  final filtered = locations.where((l) => l.coords.accuracy <= 50).toList();
  
  if (filtered.isEmpty) {
    // Return empty payload to skip sync
    return {};
  }
  
  return {
    'locations': filtered.map((l) => l.toJson()).toList(),
  };
});
```

### Compressed Payload

Minimize payload size:

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'device': extras['deviceId'],
    'data': locations.map((l) => [
      l.coords.latitude,
      l.coords.longitude,
      l.timestamp.millisecondsSinceEpoch,
      l.coords.accuracy.round(),
    ]).toList(),
  };
});
```

### Add Computed Fields

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  return {
    'locations': locations.map((location) {
      final json = location.toJson();
      
      // Add computed fields
      json['distance_from_home'] = _calculateDistance(
        location.coords,
        homeCoords,
      );
      json['is_spoofed'] = location.isSpoofed;
      json['privacy_filtered'] = location.isInPrivacyZone;
      
      return json;
    }).toList(),
  };
});
```

---

## Authentication

### Bearer Token

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  headers: {
    'Authorization': 'Bearer YOUR_ACCESS_TOKEN',
  },
));
```

### API Key

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  params: {
    'api_key': 'YOUR_API_KEY',
  },
  // Results in: POST https://api.example.com/locations?api_key=YOUR_API_KEY
));
```

### Custom Headers

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  headers: {
    'X-API-Key': 'YOUR_API_KEY',
    'X-Device-ID': deviceId,
    'X-App-Version': appVersion,
    'User-Agent': 'MyApp/1.0.0',
  },
));
```

### Dynamic Token Refresh

```dart
String? _accessToken;

Future<void> _refreshToken() async {
  final response = await http.post(
    Uri.parse('https://api.example.com/auth/refresh'),
    body: {'refresh_token': refreshToken},
  );
  
  _accessToken = jsonDecode(response.body)['access_token'];
  
  // Update Locus headers
  await Locus.setConfig(ConfigPresets.balanced.copyWith(
    headers: {
      'Authorization': 'Bearer $_accessToken',
    },
  ));
}

// Listen for 401 responses
Locus.sync.events.listen((event) async {
  if (event.type == SyncEventType.failure && event.statusCode == 401) {
    // Pause sync
    await Locus.sync.pause();
    
    // Refresh token
    await _refreshToken();
    
    // Resume sync
    await Locus.sync.resume();
  }
});
```

### Idempotency Header

Prevent duplicate processing:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  idempotencyHeader: 'X-Idempotency-Key',
));

// Locus automatically generates UUID for each request:
// X-Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

---

## Error Handling

### Sync Event Stream

```dart
Locus.sync.events.listen((event) {
  switch (event.type) {
    case SyncEventType.success:
      print('Synced ${event.locations.length} locations');
      print('Status: ${event.statusCode}');
      print('Duration: ${event.duration}ms');
      break;
      
    case SyncEventType.failure:
      print('Sync failed: ${event.error}');
      print('Status: ${event.statusCode}');
      print('Will retry: ${event.willRetry}');
      break;
      
    case SyncEventType.queued:
      print('${event.locations.length} locations queued for sync');
      break;
      
    case SyncEventType.paused:
      print('Sync paused');
      break;
      
    case SyncEventType.resumed:
      print('Sync resumed');
      break;
  }
});
```

### Handle Specific Errors

```dart
Locus.sync.events.listen((event) async {
  if (event.type != SyncEventType.failure) return;
  
  switch (event.statusCode) {
    case 401:
      // Unauthorized - refresh token
      await _refreshAuthToken();
      await Locus.sync.resume();
      break;
      
    case 429:
      // Rate limited - pause for longer
      await Locus.sync.pause();
      await Future.delayed(Duration(minutes: 5));
      await Locus.sync.resume();
      break;
      
    case 503:
      // Server unavailable - exponential backoff handles this
      print('Server unavailable, will retry');
      break;
      
    case 400:
      // Bad request - log and discard
      print('Invalid payload: ${event.error}');
      break;
      
    default:
      if (event.statusCode >= 500) {
        // Server error - will retry automatically
        print('Server error: ${event.statusCode}');
      }
  }
});
```

### Validate Server Response

```dart
Locus.sync.events.listen((event) {
  if (event.type == SyncEventType.success) {
    // Verify server processed correctly
    if (event.responseBody != null) {
      final response = jsonDecode(event.responseBody!);
      
      if (response['status'] != 'ok') {
        print('Server reported error: ${response['message']}');
      }
    }
  }
});
```

---

## Debugging Sync

### Enable Verbose Logging

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  logLevel: LogLevel.verbose,
));

// View logs
final logs = await Locus.getLog();
for (final entry in logs.where((e) => e.message.contains('sync'))) {
  print('[${entry.level}] ${entry.message}');
}
```

### Inspect Queue

```dart
final diagnostics = await Locus.getDiagnostics();
print('Queue size: ${diagnostics.queue.length}');
print('Last sync: ${diagnostics.lastSyncAt}');

// Get queued locations
final queued = await Locus.location.getLocations(limit: 100);
print('Oldest: ${queued.first.timestamp}');
print('Newest: ${queued.last.timestamp}');
```

### Monitor Sync Performance

```dart
class SyncMonitor {
  int _successCount = 0;
  int _failureCount = 0;
  int _totalLocations = 0;
  Duration _totalDuration = Duration.zero;
  
  void start() {
    Locus.sync.events.listen((event) {
      if (event.type == SyncEventType.success) {
        _successCount++;
        _totalLocations += event.locations.length;
        _totalDuration += Duration(milliseconds: event.duration);
      } else if (event.type == SyncEventType.failure) {
        _failureCount++;
      }
    });
  }
  
  void printStats() {
    print('Success: $_successCount');
    print('Failure: $_failureCount');
    print('Total locations: $_totalLocations');
    print('Avg duration: ${_totalDuration.inMilliseconds / _successCount}ms');
    print('Success rate: ${(_successCount / (_successCount + _failureCount) * 100).toStringAsFixed(1)}%');
  }
}
```

### Test Sync Manually

```dart
// Add test location
await Locus.location.getCurrentPosition();

// Trigger sync
await Locus.sync.now();

// Check result
await Future.delayed(Duration(seconds: 2));
final diagnostics = await Locus.getDiagnostics();
print('Queue after sync: ${diagnostics.queue.length}');
```

### Capture HTTP Traffic

Use a proxy tool (Charles, Proxyman) to inspect requests:

```dart
// Configure proxy for debugging
// Note: This requires additional setup outside Locus
```

---

## Advanced Patterns

### Sync with Progress

```dart
Future<void> syncWithProgress(BuildContext context) async {
  final diagnostics = await Locus.getDiagnostics();
  final total = diagnostics.queue.length;
  
  if (total == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nothing to sync')),
    );
    return;
  }
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => SyncProgressDialog(total: total),
  );
  
  await Locus.sync.now();
}

class SyncProgressDialog extends StatefulWidget {
  final int total;
  const SyncProgressDialog({required this.total});
  
  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  int _synced = 0;
  
  @override
  void initState() {
    super.initState();
    
    Locus.sync.events.listen((event) {
      if (event.type == SyncEventType.success) {
        setState(() {
          _synced += event.locations.length;
        });
        
        if (_synced >= widget.total) {
          Navigator.of(context).pop();
        }
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Syncing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _synced / widget.total,
          ),
          SizedBox(height: 16),
          Text('$_synced / ${widget.total} locations synced'),
        ],
      ),
    );
  }
}
```

### Conditional Sync Based on Network

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

Connectivity().onConnectivityChanged.listen((result) async {
  if (result == ConnectivityResult.wifi) {
    // On WiFi - sync everything
    await Locus.setConfig(ConfigPresets.balanced.copyWith(
      disableAutoSyncOnCellular: false,
    ));
    await Locus.sync.now();
  } else if (result == ConnectivityResult.mobile) {
    // On cellular - minimal sync
    await Locus.setConfig(ConfigPresets.balanced.copyWith(
      disableAutoSyncOnCellular: true,
    ));
  }
});
```

### Batch Sync with App Data

```dart
Future<void> syncLocationAndAppData() async {
  // Get pending locations
  final locations = await Locus.location.getLocations();
  
  // Combine with app data
  final payload = {
    'locations': locations.map((l) => l.toJson()).toList(),
    'app_state': await _getAppState(),
    'user_actions': await _getPendingActions(),
  };
  
  // Send custom payload
  await http.post(
    Uri.parse('https://api.example.com/batch-sync'),
    body: jsonEncode(payload),
  );
  
  // Clear queue on success
  await Locus.sync.clearQueue();
}
```

### Multi-Endpoint Sync

```dart
Future<void> syncToMultipleEndpoints() async {
  final locations = await Locus.location.getLocations();
  
  // Primary endpoint
  try {
    await _syncTo('https://api.primary.com/locations', locations);
  } catch (e) {
    print('Primary endpoint failed: $e');
  }
  
  // Backup endpoint
  try {
    await _syncTo('https://api.backup.com/locations', locations);
  } catch (e) {
    print('Backup endpoint failed: $e');
  }
  
  // Analytics endpoint (fire-and-forget)
  _syncTo('https://analytics.example.com/track', locations)
      .catchError((_) {});
  
  await Locus.sync.clearQueue();
}
```

---

## Best Practices

### 1. Use Batch Sync

```dart
// ✅ Efficient
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: true,
  maxBatchSize: 100,
));

// ❌ Inefficient
await Locus.ready(ConfigPresets.balanced.copyWith(
  batchSync: false, // Each location = separate request
));
```

### 2. Implement Idempotency

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  idempotencyHeader: 'X-Idempotency-Key',
));

// Server should deduplicate based on this header
```

### 3. Handle 401 Gracefully

```dart
Locus.sync.events.listen((event) async {
  if (event.type == SyncEventType.failure && event.statusCode == 401) {
    await Locus.sync.pause();
    await _refreshAuthToken();
    await Locus.sync.resume();
  }
});
```

### 4. Monitor Queue Growth

```dart
Timer.periodic(Duration(minutes: 5), (timer) async {
  final diagnostics = await Locus.getDiagnostics();
  if (diagnostics.queue.length > 1000) {
    print('WARNING: Large queue - check sync');
    await Locus.sync.now();
  }
});
```

### 5. Validate Payloads

```dart
Locus.sync.setSyncBodyBuilder((locations, extras) async {
  // Validate before sending
  if (locations.isEmpty) return {};
  
  if (extras['userId'] == null) {
    print('ERROR: userId missing from extras');
    return {};
  }
  
  return {
    'user_id': extras['userId'],
    'locations': locations.map((l) => l.toJson()).toList(),
  };
});
```

### 6. Test Offline Scenarios

- Disable network during tracking
- Verify locations queue properly
- Enable network and verify sync
- Test queue persistence across app restarts

### 7. Log Sync Metrics

```dart
Locus.sync.events.listen((event) {
  if (event.type == SyncEventType.success) {
    analytics.logEvent('location_sync_success', {
      'count': event.locations.length,
      'duration_ms': event.duration,
      'payload_bytes': event.payloadSize,
    });
  } else if (event.type == SyncEventType.failure) {
    analytics.logEvent('location_sync_failure', {
      'status_code': event.statusCode,
      'error': event.error,
    });
  }
});
```

---

## Summary

Key takeaways:
- ✅ Use batch sync for efficiency
- ✅ Implement proper error handling (especially 401)
- ✅ Use custom sync body builders for payload control
- ✅ Monitor queue size and sync performance
- ✅ Test offline and retry scenarios
- ✅ Enable idempotency for reliability
- ✅ Log metrics for debugging

---

**Related Documentation:**
- [Configuration Reference](../core/configuration-reference.md)
- [Headless Execution Guide](headless-execution.md)
- [Error Codes Reference](../api/error-codes.md)
- [Troubleshooting Guide](../guides/troubleshooting.md)
