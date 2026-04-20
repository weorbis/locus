# Migration Guide: v1.x to v2.0

This guide helps you migrate your Locus SDK integration from v1.x to v2.0.

## Overview

Locus v2.0 introduces a feature-first, service-based API. Core lifecycle methods
remain on `Locus`, while location, geofencing, privacy, trips, sync, and battery
methods moved to dedicated services. Deprecated facade methods are removed.

| v1.x                          | v2.0                                  |
| ----------------------------- | ------------------------------------- |
| `Locus.getCurrentPosition()`  | `Locus.location.getCurrentPosition()` |
| `Locus.getLocations()`        | `Locus.location.getLocations()`       |
| `Locus.queryLocations(q)`     | `Locus.location.query(q)`             |
| `Locus.getLocationSummary()`  | `Locus.location.getSummary()`         |
| `Locus.addGeofence(g)`        | `Locus.geofencing.add(g)`             |
| `Locus.addPolygonGeofence(p)` | `Locus.geofencing.addPolygon(p)`      |
| `Locus.addPrivacyZone(z)`     | `Locus.privacy.add(z)`                |
| `Locus.startTrip(cfg)`        | `Locus.trips.start(cfg)`              |
| `Locus.sync()`                | `Locus.dataSync.now()`                |
| `Locus.getBatteryStats()`     | `Locus.battery.getStats()`            |

---

## Automated Migration

Locus provides a CLI tool to automate most migration tasks:

```bash
# Preview changes (recommended first step)
dart run locus:migrate --dry-run

# Apply migrations with backup
dart run locus:migrate --backup

# Migrate a specific project
dart run locus:migrate --path=/path/to/project

# JSON output for CI/CD
dart run locus:migrate --format=json

# Skip test files
dart run locus:migrate --skip-tests
```

### Migration CLI Options

| Option         | Abbr | Description                               |
| -------------- | ---- | ----------------------------------------- |
| `--dry-run`    | `-n` | Preview changes without modifying files   |
| `--backup`     | `-b` | Create backup before migrating            |
| `--path`       | `-p` | Project path (default: current directory) |
| `--format`     | `-f` | Output format: `text` or `json`           |
| `--verbose`    | `-v` | Show detailed output                      |
| `--skip-tests` | N/A  | Skip test files                           |
| `--no-color`   | N/A  | Disable colored output                    |

---

## Manual Migration

If you prefer to migrate manually, follow these steps.

### 1. Location Service

**Before (v1.x):**

```dart
await Locus.start();
final state = await Locus.getState();
final location = await Locus.getCurrentPosition();
final locations = await Locus.getLocations();
Locus.onLocation((loc) => print(loc));
```

**After (v2.0):**

```dart
await Locus.start();
final state = await Locus.getState();
final location = await Locus.location.getCurrentPosition();
final locations = await Locus.location.getLocations();

final subscription = Locus.location.stream.listen((loc) {
  print(loc);
});

// Cancel when done
await subscription.cancel();
```

### 2. Geofencing Service

**Before (v1.x):**

```dart
await Locus.addGeofence(geofence);
await Locus.addGeofences([g1, g2]);
await Locus.removeGeofence('id');
await Locus.getGeofences();
Locus.onGeofence((event) => print(event));
```

**After (v2.0):**

```dart
await Locus.geofencing.add(geofence);
await Locus.geofencing.addAll([g1, g2]);
await Locus.geofencing.remove('id');
await Locus.geofencing.getAll();
Locus.geofencing.events.listen((event) => print(event));
```

### 3. Privacy Service

**Before (v1.x):**

```dart
await Locus.addPrivacyZone(zone);
await Locus.getPrivacyZones();
await Locus.removePrivacyZone('id');
```

**After (v2.0):**

```dart
await Locus.privacy.add(zone);
await Locus.privacy.getAll();
await Locus.privacy.remove('id');
```

### 4. Trips Service

**Before (v1.x):**

```dart
await Locus.trips.start(config);
final summary = await Locus.stopTrip();
final state = await Locus.getTripState();
Locus.tripEvents.listen((event) => print(event));
```

**After (v2.0):**

```dart
await Locus.trips.start(config);
final summary = await Locus.trips.stop();
final state = await Locus.trips.getState();
Locus.trips.events.listen((event) => print(event));
```

### 5. Data Sync Service

**Before (v1.x):**

```dart
await Locus.sync();
await Locus.resumeSync();
await Locus.destroyLocations();
await Locus.getQueue();
await Locus.clearQueue();
Locus.httpStream.listen((event) => print(event));
```

**After (v2.0):**

```dart
await Locus.dataSync.now();
await Locus.dataSync.resume();
await Locus.location.destroyLocations();
await Locus.dataSync.getQueue();
await Locus.dataSync.clearQueue();
Locus.dataSync.events.listen((event) => print(event));
```

### 6. Battery Service

**Before (v1.x):**

```dart
final stats = await Locus.getBatteryStats();
final power = await Locus.getPowerState();
final runway = await Locus.estimateBatteryRunway();
Locus.powerSaveStream.listen((enabled) => print(enabled));
```

**After (v2.0):**

```dart
final stats = await Locus.battery.getStats();
final power = await Locus.battery.getPowerState();
final runway = await Locus.battery.estimateRunway();
Locus.battery.powerSaveChanges.listen((enabled) => print(enabled));
```

### 7. Diagnostics Service

**Before (v1.x):**

```dart
final diagnostics = await Locus.getDiagnostics();
final logs = await Locus.getLog();
Locus.locationAnomalies().listen((anomaly) => print(anomaly));
```

**After (v2.0):**

```dart
final diagnostics = await Locus.getDiagnostics();
final logs = await Locus.getLog();
Locus.locationAnomalies().listen((anomaly) => print(anomaly));
```

---

## Removed Features

The following features are **removed** in v2.0:

### `Locus.emailLog()`

**Removed.** Background services shouldn't spawn email intents.

**Migration:**

```dart
// Before
await Locus.emailLog('support@example.com');

// After - Implement your own email feature
final Uri emailUri = Uri(
  scheme: 'mailto',
  path: 'support@example.com',
  queryParameters: {'subject': 'Locus Debug Log', 'body': logContent},
);
if (await canLaunchUrl(emailUri)) {
  await launchUrl(emailUri);
}
```

### `Locus.playSound()`

**Removed.** Use a dedicated sound package.

**Migration:**

```dart
// Before
await Locus.playSound('notification');

// After - Use flutter_sound or audioplayers
import 'package:audioplayers/audioplayers.dart';

final audioPlayer = AudioPlayer();
await audioPlayer.play(AssetSource('sounds/notification.wav'));
```

---

## Manual Review Required

### Headless Callbacks

Headless callbacks remain on `Locus`. Add `@pragma('vm:entry-point')`:

**Before:**

```dart
Future<void> myHeadlessCallback(HeadlessEvent event) async {
  // Handle background event
}

void main() {
  Locus.registerHeadlessTask(myHeadlessCallback);
}
```

For sync payload customization, use the sync service:

```dart
@pragma('vm:entry-point')
Future<JsonMap> buildSyncBody(SyncBodyContext context) async {
  return {'locations': context.locations.map((l) => l.toMap()).toList()};
}

void main() {
  Locus.dataSync.registerHeadlessSyncBodyBuilder(buildSyncBody);
}
```

### Sync no longer paused by default

Prior versions of Locus started sync in a paused state; host apps had to call `Locus.dataSync.resume()` after `Locus.ready()` or no HTTP traffic would ever reach the backend. From the next release, sync is **active by default** when `Config.url` is set.

**If your app previously relied on the paused default** (e.g. as a way to block sync until a separate `task_id` was established), replace the implicit behavior with one of:

```dart
// Option A — explicit pause at startup (matches the old behavior exactly):
await Locus.ready(config);
await Locus.dataSync.pause();

// Option B (preferred) — reject individual batches via the pre-sync validator,
// which keeps items queued without blocking the transport layer:
Locus.dataSync.setPreSyncValidator((locations, extras) async {
  return extras['task_id'] != null;
});
```

`Locus.dataSync.resume()` is still the right call after refreshing auth credentials in response to a 401/403 — auth-failure pauses are automatic and persist across process restarts until you explicitly resume.

### Stream Subscriptions

Callback-style listeners must be converted to stream subscriptions:

**Before:**

```dart
Locus.onLocation((location) {
  print(location);
});
// No way to cancel the subscription
```

**After:**

```dart
final subscription = Locus.location.stream.listen((location) {
  print(location);
});

// Cancel when done
subscription.cancel();
```

---

## Tree Shaking

Locus v2.0 supports tree shaking to reduce bundle size:

```dart
// Import everything (includes all features)
import 'package:locus/locus.dart';

// Import only what you need from public barrels
import 'package:locus/locus.dart' show Locus, Config, Geofence, GeoPoint;
```

---

## Rollback

If something goes wrong:

```bash
# List available backups
ls .locus/backup/

# Restore from backup
tar -xzf .locus/backup/2026-01-15T10-30-00/backup.tar.gz -C /path/to/restore
```

---

## CI/CD Integration

Add migration check to your CI pipeline:

```yaml
name: Locus Migration Check

on:
  pull_request:
    paths:
      - "lib/**/*.dart"

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Dart
        uses: dart-lang/setup-dart@v1

      - name: Check Migration Status
        run: |
          echo "Running Locus migration check..."
          dart run locus:migrate --dry-run --format=json > migration_report.json

      - name: Fail if manual review needed
        run: |
          if grep -q "manualReview" migration_report.json; then
            echo "Manual migration steps required"
            cat migration_report.json
            exit 1
          fi
          echo "Migration check passed"
```

---

## Troubleshooting

### Pattern not detected

If a pattern isn't being detected, check for:

- Typos in method names
- Different spacing or formatting
- Dynamic method calls (not supported)
- Code in conditional compilation (`if (kDebugMode)`)

### Replacement incorrect

If replacement produces incorrect code:

1. Run with `--dry-run` first
2. Manually update the problematic file
3. Report the issue at https://github.com/weorbis/locus/issues

### Backup not created

If backup creation fails:

1. Ensure you have write permissions in the project directory
2. Check available disk space
3. Try without backup: `dart run locus:migrate --no-backup`

---

## Summary Checklist

- [ ] Run `dart run locus:migrate --dry-run`
- [ ] Review changes
- [ ] Run `dart run locus:migrate --backup`
- [ ] Update imports if needed
- [ ] Add `@pragma('vm:entry-point')` to headless callbacks
- [ ] Convert callbacks to `.listen()` pattern
- [ ] Remove `Locus.emailLog()` calls
- [ ] Replace `Locus.playSound()` with audio package
- [ ] Run tests
- [ ] Build and verify

---

## Need Help?

- **Issues:** https://github.com/weorbis/locus/issues
- **Documentation:** https://locus.dev/docs
- **Discord:** https://discord.gg/locus
