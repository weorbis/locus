# Architecture

Locus follows a **feature-first** architecture pattern, organizing code by domain rather than by technical layer. This makes the codebase easier to navigate and maintain.

## Directory Structure

```
lib/src/
├── features/           # Feature modules
│   ├── location/       # Core location tracking
│   │   ├── models/     # Location, LocationHistory, etc.
│   │   └── services/   # LocusLocation, SpoofDetection, etc.
│   ├── geofencing/     # Geofence management
│   │   ├── models/     # Geofence, PolygonGeofence, etc.
│   │   └── services/   # GeofencingService, PolygonService
│   ├── battery/        # Battery optimization
│   │   ├── models/     # AdaptiveConfig, BatteryRunway
│   │   └── services/   # LocusAdaptive, LocusBattery
│   ├── privacy/        # Privacy zones
│   │   ├── models/     # PrivacyZone, PrivacyZoneResult
│   │   └── services/   # PrivacyZoneService
│   ├── trips/          # Trip detection/tracking
│   │   ├── models/     # TripState, TripSummary, RoutePoint
│   │   └── services/   # TripEngine, TripStore
│   ├── sync/           # HTTP synchronization
│   │   ├── models/     # QueueItem, HttpEvent
│   │   └── services/   # LocusSync
│   ├── tracking/       # Tracking profiles
│   │   ├── models/     # TrackingProfile, TrackingProfileRule
│   │   └── services/   # TrackingProfileManager
│   └── diagnostics/    # Debug & logging
│       ├── models/     # Diagnostics, LogEntry
│       ├── services/   # ErrorRecovery, LocusDiagnostics
│       └── widgets/    # LocusDebugOverlay
├── shared/             # Cross-cutting concerns
│   └── models/         # Activity, Coords, Battery, etc.
├── core/               # Infrastructure
│   ├── locus_interface.dart    # Abstract interface
│   ├── method_channel_locus.dart  # Platform implementation
│   ├── locus_streams.dart      # Event streams
│   └── locus_channels.dart     # Method channels
├── config/             # Configuration
│   └── config.dart     # GeolocationConfig, presets
├── testing/            # Test utilities
│   └── mock_locus.dart # Mock implementation
├── models.dart         # Barrel export for all models
├── services.dart       # Barrel export for all services
└── locus.dart          # Main Locus class
```

## Feature Modules

Each feature is self-contained with its own models and services:

### Location Feature
Core location tracking, quality analysis, anomaly detection, and spoof detection.

### Geofencing Feature
Circular and polygon geofences, geofence workflows, enter/exit/dwell detection.

### Battery Feature
Adaptive tracking, battery runway estimation, power state monitoring.

### Privacy Feature
Privacy zones with exclude, obfuscate, and reduce actions.

### Trips Feature
Automatic trip detection, trip storage, route recording.

### Sync Feature
HTTP synchronization, offline queue, retry logic.

### Tracking Feature
Tracking profiles, automatic profile switching based on rules.

### Diagnostics Feature
Debug overlay, logging, error recovery.

## Imports

### For App Developers

Import everything from the main entry point:

```dart
import 'package:locus/locus.dart';
```

This exports all public models, services, and utilities.

### For SDK Contributors

Import specific features when working on the SDK:

```dart
// Import a specific feature
import 'package:locus/src/features/geofencing/geofencing.dart';

// Import shared models
import 'package:locus/src/shared/models/coords.dart';

// Import core infrastructure
import 'package:locus/src/core/locus_interface.dart';
```

## Testing

Locus provides a `MockLocus` implementation for testing:

```dart
import 'package:locus/locus.dart';

void main() {
  setUp(() {
    Locus.setInstance(MockLocus());
  });

  test('my location feature', () async {
    final mock = Locus.instance as MockLocus;
    
    // Simulate a location update
    mock.simulateLocation(Location(...));
    
    // Your test assertions
  });
}
```

---

**Next:** [Contributing](../../CONTRIBUTING.md)
