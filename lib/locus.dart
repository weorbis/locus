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
/// ## Philosophy
///
/// Locus provides building blocks, not business logic. Your app composes
/// these primitives into your specific solution (fleet, fitness, social, etc.)
library;

export 'src/locus.dart';
export 'src/battery/battery.dart';
export 'src/config/config.dart';
export 'src/events/events.dart';
export 'src/models/models.dart';
export 'src/services/services.dart';
export 'src/testing/testing.dart';
export 'src/widgets/widgets.dart';
