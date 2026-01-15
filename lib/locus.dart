/// Locus - Background geolocation SDK for Flutter.
///
/// A pure, unopinionated foundation for background location tracking with
/// native geofencing, activity recognition, and HTTP sync capabilities.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:locus/locus.dart';
///
/// // Initialize with defaults
/// await Locus.ready();
///
/// // Start tracking
/// await Locus.start();
///
/// // Listen to location updates
/// Locus.onLocation((location) {
///   print('${location.coords.latitude}, ${location.coords.longitude}');
/// });
/// ```
///
/// ## Documentation
///
/// For full documentation, visit the [Locus GitHub repository](https://github.com/weorbis/locus):
/// - [Quick Start](https://github.com/weorbis/locus/blob/main/doc/guides/quickstart.md)
/// - [Migration from v1](https://github.com/weorbis/locus/blob/main/doc/guides/migration.md)
/// - [Architecture](https://github.com/weorbis/locus/blob/main/doc/core/architecture.md)
/// - [Configuration](https://github.com/weorbis/locus/blob/main/doc/core/configuration.md)
/// - [Geofencing](https://github.com/weorbis/locus/blob/main/doc/advanced/geofencing.md)
/// - [Privacy Zones](https://github.com/weorbis/locus/blob/main/doc/advanced/privacy-zones.md)
/// - [Trips](https://github.com/weorbis/locus/blob/main/doc/advanced/trips.md)
/// - [Battery Optimization](https://github.com/weorbis/locus/blob/main/doc/advanced/battery-optimization.md)
/// - [Platform Setup](https://github.com/weorbis/locus/blob/main/doc/setup/platform-configuration.md)
/// - [Troubleshooting](https://github.com/weorbis/locus/blob/main/doc/guides/troubleshooting.md)
/// - [FAQ](https://github.com/weorbis/locus/blob/main/doc/guides/faq.md)
/// - [Headless Execution](https://github.com/weorbis/locus/blob/main/doc/guides/headless-execution.md)
/// - [Platform Behaviors](https://github.com/weorbis/locus/blob/main/doc/guides/platform-specific-behaviors.md)
/// - [HTTP Sync](https://github.com/weorbis/locus/blob/main/doc/guides/http-synchronization.md)
/// - [Performance](https://github.com/weorbis/locus/blob/main/doc/guides/performance-optimization.md)
/// - [Activity Recognition](https://github.com/weorbis/locus/blob/main/doc/guides/activity-recognition.md)
/// - [Event Streams](https://github.com/weorbis/locus/blob/main/doc/reference/event-streams.md)
/// - [Error Codes](https://github.com/weorbis/locus/blob/main/doc/reference/error-codes.md)
///
/// ## Philosophy
///
/// Locus provides building blocks, not business logic. Your app composes
/// these primitives into your specific solution (fleet, fitness, social, etc.)
library;

export 'src/locus.dart';
export 'src/features/battery/battery.dart';
export 'src/config/config.dart';
export 'src/shared/events.dart';
export 'src/models.dart';
export 'src/services.dart';
export 'src/testing/testing.dart';
export 'src/features/diagnostics/widgets.dart';
