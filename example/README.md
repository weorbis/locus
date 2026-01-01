# Locus Example Application

This is a demonstration application for the Locus Background Geolocation SDK. It showcases key features including background tracking, motion activity detection, and geofencing.

## Features Demonstrated

- **Permission Handling**: requesting background location and motion activity permissions.
- **Service Lifecycle**: starting and stopping the background tracking service.
- **Event Monitoring**: real-time display of location updates, motion state changes, and provider authorization status.
- **Configuration**: demonstration of different tracking presets and adaptive configurations.

## Getting Started

### 1. Configure Native Settings

Before running the example, ensure your environment is configured for background location. You can use the Locus CLI from the root of this example project (or the parent project):

```bash
dart run locus:setup
```

### 2. Run the Application

Navigate to the `example` directory and run the application:

```bash
flutter run
```

## Implementation Notes

The core logic for this example is located in `lib/main.dart`. It demonstrates the use of `Locus.ready()` with a high-accuracy configuration and listeners for various event streams.
