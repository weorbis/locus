library;

/// Desired location accuracy level.
enum DesiredAccuracy {
  /// Highest precision for turn-by-turn navigation (±5 meters or better).
  navigation,

  /// High accuracy for precise location tracking (±10 meters).
  high,

  /// Balanced accuracy suitable for most use cases (±30 meters).
  medium,

  /// Lower accuracy to conserve battery (±100 meters).
  low,

  /// Very low accuracy with minimal battery impact (±300 meters).
  veryLow,

  /// Lowest accuracy for maximum battery conservation (±3 kilometers).
  lowest,
}

/// Log level for debugging.
enum LogLevel {
  /// Disables all logging output.
  off,

  /// Logs only critical errors that prevent normal operation.
  error,

  /// Logs warnings about potential issues that don't stop execution.
  warning,

  /// Logs general informational messages about application state.
  info,

  /// Logs detailed debugging information for troubleshooting.
  debug,

  /// Logs all available information including low-level details.
  verbose,
}

/// Persistence mode for location data.
enum PersistMode {
  /// Disables data persistence; no location or geofence data is saved.
  none,

  /// Persists only location data to local storage.
  location,

  /// Persists only geofence events to local storage.
  geofence,

  /// Persists both location data and geofence events to local storage.
  all,
}

/// Tracking profile for adaptive behavior.
enum LocusProfile {
  /// Optimized for stationary or minimal movement scenarios.
  stationary,

  /// Optimized for pedestrian speed and movement patterns.
  walking,

  /// Optimized for vehicle speed and road-following behavior.
  driving,

  /// Optimized for turn-by-turn navigation with highest accuracy.
  navigation,

  /// Disables adaptive tracking and uses static configuration.
  off,
}

/// Action to take when spoofing is detected.
enum SpoofDetectionAction {
  /// Marks location data as potentially spoofed but continues tracking.
  flag,

  /// Ignores spoofing detection and accepts all location data.
  ignore,

  /// Stops location tracking immediately when spoofing is detected.
  stop,
}
