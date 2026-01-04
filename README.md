<p align="center">
  <img src="assets/logo/locus_logo_128.png" alt="Locus Logo" width="100" height="100">
</p>

<h1 align="center">Locus</h1>

<p align="center">
  <a href="https://pub.dev/packages/locus"><img src="https://img.shields.io/pub/v/locus?style=flat-square&logo=dart" alt="Pub Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-PolyForm%20Small%20Business-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/koksalmehmet/locus/actions"><img src="https://img.shields.io/github/actions/workflow/status/koksalmehmet/locus/pipeline.yml?style=flat-square&logo=github" alt="Build Status"></a>
</p>

<p align="center">
  A battle-tested background geolocation SDK for Flutter.<br>
  High-performance tracking, motion recognition, geofencing, and automated sync for Android and iOS.
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

For full documentation, visit [locus.dev](https://pub.dev/documentation/locus/latest/) or check the local [docs](docs/intro.md) folder:

- **[Quick Start](docs/guides/quickstart.md)** - Get running in 5 minutes.
- **[Architecture](docs/core/architecture.md)** - Project structure and design.
- **[Configuration](docs/core/configuration.md)** - Configuration options and presets.
- **[Geofencing](docs/advanced/geofencing.md)** - Circular and polygon geofences.
- **[Privacy Zones](docs/advanced/privacy-zones.md)** - Location privacy features.
- **[Trip Tracking](docs/advanced/trips.md)** - Trip detection and recording.
- **[Battery Optimization](docs/advanced/battery-optimization.md)** - Adaptive tracking.
- **[Platform Setup](docs/setup/platform-configuration.md)** - iOS & Android permissions.

## Quick Start

### 1. Installation

```yaml
dependencies:
  locus: ^1.1.0
```

### 2. Basic Setup

```dart
import 'package:locus/locus.dart';

void main() async {
  // 1. Initialize
  await Locus.ready(Config.balanced(
    url: 'https://api.yourservice.com/locations',
  ));

  // 2. Start tracking
  await Locus.start();

  // 3. Listen to updates
  Locus.onLocation((location) {
    print('Location: ${location.coords.latitude}, ${location.coords.longitude}');
  });
}
```

### 3. Add Geofences

```dart
// Circular geofence
await Locus.addGeofence(Geofence(
  identifier: 'office',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 100,
  notifyOnEntry: true,
  notifyOnExit: true,
));

// Polygon geofence
await Locus.addPolygonGeofence(PolygonGeofence(
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

Locus is licensed under the **PolyForm Small Business License 1.0.0**.

- **Free** for individuals and small businesses (< $250k annual revenue).
- **Professional/Enterprise** licenses available for larger organizations.

See [LICENSE](LICENSE) and [LICENSING.md](LICENSING.md) for full terms.
