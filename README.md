<p align="center">
  <img src="assets/logo/locus_logo_128.png" alt="Locus Logo" width="100" height="100">
</p>

<h1 align="center">Locus</h1>

<p align="center">
  <a href="https://pub.dev/packages/locus"><img src="https://img.shields.io/pub/v/locus?style=flat-square&logo=dart" alt="Pub Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/weorbis/locus/actions"><img src="https://img.shields.io/github/actions/workflow/status/weorbis/locus/pipeline.yml?style=flat-square&logo=github" alt="Build Status"></a>
</p>

<p align="center">
  Reliable background geolocation for Flutter apps. Part of the **WeOrbis** ecosystem.<br>
  Service-based v2.0.0 API covering tracking, geofencing, sync, privacy, and battery on Android and iOS.<br>
  Built for production: deterministic APIs, full test suite, and migration tooling from v1.
</p>

---

## Key Features

- **Continuous Tracking**: Reliable background updates with adaptive filters.
- **Motion Recognition**: Activity detection (walking, running, driving, stationary).
- **Geofencing**: Circular and polygon geofences with enter/exit/dwell detection.
- **Polygon Geofences**: Define complex boundaries with arbitrary shapes.
- **Geofence Workflows**: Multi-step geofence sequences with timeouts.
- **Privacy Zones**: Exclude, obfuscate, or reduce accuracy in sensitive areas.
- **Trip Detection**: Automatic trip start/end detection with route recording.
- **Battery Optimization**: Adaptive profiles based on speed, activity, and battery level.
- **Automated Sync**: HTTP synchronization with retry logic and batching.
- **Offline Reliability**: SQLite persistence to prevent data loss.
- **Headless Execution**: Execute background logic even when the app is terminated.

## Documentation

For full documentation, visit the [Locus GitHub repository](https://github.com/weorbis/locus):

- **[Quick Start](https://github.com/weorbis/locus/blob/main/doc/guides/quickstart.md)** - Get running in 5 minutes.
- **[Migration (v1.x to v2.0)](https://github.com/weorbis/locus/blob/main/doc/guides/migration.md)** - Move to the service-based API.
- **[Architecture](https://github.com/weorbis/locus/blob/main/doc/core/architecture.md)** - Project structure and design.
- **[Configuration](https://github.com/weorbis/locus/blob/main/doc/core/configuration.md)** - Configuration options and presets.
- **[Geofencing](https://github.com/weorbis/locus/blob/main/doc/advanced/geofencing.md)** - Circular and polygon geofences.
- **[Privacy Zones](https://github.com/weorbis/locus/blob/main/doc/advanced/privacy-zones.md)** - Location privacy features.
- **[Trip Tracking](https://github.com/weorbis/locus/blob/main/doc/advanced/trips.md)** - Trip detection and recording.
- **[Battery Optimization](https://github.com/weorbis/locus/blob/main/doc/advanced/battery-optimization.md)** - Adaptive tracking.
- **[Platform Setup](https://github.com/weorbis/locus/blob/main/doc/setup/platform-configuration.md)** - iOS & Android permissions.
- **[Troubleshooting](https://github.com/weorbis/locus/blob/main/doc/guides/troubleshooting.md)** - Common issues and fixes.
- **[FAQ](https://github.com/weorbis/locus/blob/main/doc/guides/faq.md)** - Frequently asked questions.
- **[Headless Execution](https://github.com/weorbis/locus/blob/main/doc/guides/headless-execution.md)** - Running logic when the app is terminated.
- **[Platform Behaviors](https://github.com/weorbis/locus/blob/main/doc/guides/platform-specific-behaviors.md)** - Android/iOS runtime differences.
- **[HTTP Synchronization](https://github.com/weorbis/locus/blob/main/doc/guides/http-synchronization.md)** - Request formats, retry, and batching.
- **[Performance Optimization](https://github.com/weorbis/locus/blob/main/doc/guides/performance-optimization.md)** - Tuning for battery and accuracy.
- **[Activity Recognition](https://github.com/weorbis/locus/blob/main/doc/guides/activity-recognition.md)** - Activity types and best practices.
- **[Event Streams Reference](https://github.com/weorbis/locus/blob/main/doc/reference/event-streams.md)** - When streams emit and how to subscribe safely.
- **[Error Codes](https://github.com/weorbis/locus/blob/main/doc/reference/error-codes.md)** - Exception types and recovery guidance.

## Quick Start

### 1. Installation

```yaml
dependencies:
  locus: ^2.0.0
```

### 2. Basic Setup

```dart
import 'package:locus/locus.dart';

void main() async {
  // 1. Initialize (url is optional - omit for local-only testing)
  await Locus.ready(ConfigPresets.balanced);

  // 2. Start tracking
  await Locus.start();

  // 3. Listen to updates
  Locus.location.stream.listen((location) {
    print('Location: ${location.coords.latitude}, ${location.coords.longitude}');
  });
}
```

> **Note:** The `url` parameter is optional. It's only needed for Locus' HTTP sync layer (batching + retrying location data to your backend). For local-only testing, omit it entirely.

### 3. Add HTTP Sync

To upload locations to your backend, add the `url` parameter:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://your-server.com/locations',
));
```

For quick testing without a backend, use [webhook.site](https://webhook.site) to get a test endpoint:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://webhook.site/your-unique-id',
));
```

### 3. Add Geofences

```dart
// Circular geofence
await Locus.geofencing.add(Geofence(
  identifier: 'office',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 100,
  notifyOnEntry: true,
  notifyOnExit: true,
));

// Polygon geofence
await Locus.geofencing.addPolygon(PolygonGeofence(
  identifier: 'campus',
  vertices: [
    GeoPoint(latitude: 37.7749, longitude: -122.4194),
    GeoPoint(latitude: 37.7759, longitude: -122.4184),
    GeoPoint(latitude: 37.7769, longitude: -122.4204),
  ],
));
```

## Project Tooling

Locus includes a CLI to help with configuration and diagnostics:

```bash
# Automate native permission setup
dart run locus:setup

# Run environment diagnostics
dart run locus:doctor

# Migration helper (v1.x to v2.0)
dart run locus:migrate --dry-run
```

## Versioning

- Current release: **v2.0.0** (service-based API)
- Supports Flutter 3.x / Dart 3.x
- See [CHANGELOG.md](CHANGELOG.md#200---2026-01-07) for details

## Tree Shaking

Locus v2.0 is service-based and designed to tree shake unused features in
release builds. To keep your app lean:

- Import only what you need from the public barrels.
- Avoid referencing service getters you do not use.

Example:

```dart
import 'package:locus/locus.dart' show Locus, Config, Geofence, GeoPoint;

Future<void> initTracking() async {
  await Locus.ready(const Config());
  await Locus.start();
  await Locus.geofencing.add(Geofence(
    identifier: 'office',
    latitude: 37.7749,
    longitude: -122.4194,
    radius: 100,
  ));
}
```

## Architecture

Locus uses a **feature-first** architecture:

```
lib/src/
├── features/
│   ├── location/      # Core location tracking
│   ├── geofencing/    # Circular & polygon geofences
│   ├── battery/       # Battery optimization
│   ├── privacy/       # Privacy zones
│   ├── trips/         # Trip detection
│   ├── sync/          # HTTP sync
│   ├── tracking/      # Tracking profiles
│   └── diagnostics/   # Debug tools
├── shared/            # Common models
├── core/              # Infrastructure
└── config/            # Configuration
```

## License

Locus is licensed under the **MIT License**.

- **Free and Open Source**: Use it for personal or commercial projects.
- **Community Focused**: Built to be a high-quality, free alternative for Flutter background geolocation.

See [LICENSE](LICENSE) and [LICENSING.md](LICENSING.md) for full terms.
