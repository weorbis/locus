/// Locus SDK Constants
///
/// This file contains all magic numbers and constants used throughout the SDK.
/// Using named constants improves code readability and maintainability.
library;

// ============================================================================
// TIME CONSTANTS
// ============================================================================

/// Milliseconds per second.
const int kMillisecondsPerSecond = 1000;

/// Seconds per minute.
const int kSecondsPerMinute = 60;

/// Seconds per hour.
const int kSecondsPerHour = 3600;

/// Seconds per day.
const int kSecondsPerDay = 86400;

/// Default heartbeat interval in seconds.
const int kDefaultHeartbeatIntervalSeconds = 60;

/// Default update interval in seconds.
const int kDefaultUpdateIntervalSeconds = 60;

/// Minimum activity recognition interval in milliseconds.
const int kMinActivityRecognitionIntervalMs = 1000;

// ============================================================================
// DISTANCE CONSTANTS
// ============================================================================

/// Meters per kilometer.
const double kMetersPerKilometer = 1000.0;

/// Default distance filter in meters.
const double kDefaultDistanceFilterMeters = 50.0;

/// Default minimum accuracy in meters.
const double kDefaultMinAccuracyMeters = 100.0;

/// Default route deviation threshold in meters.
const double kDefaultRouteDeviationThresholdMeters = 100.0;

/// Default significant change displacement in meters.
const double kDefaultSignificantChangeDisplacementMeters = 1000.0;

/// Default geofence radius in meters.
const double kDefaultGeofenceRadiusMeters = 100.0;

// ============================================================================
// SPEED CONSTANTS
// ============================================================================

/// Maximum possible speed in km/h (commercial jet speed).
/// Used for spoof detection.
const double kMaxPossibleSpeedKph = 1200.0;

/// Maximum altitude change per second in meters (~360 km/h vertical).
/// Used for spoof detection.
const double kMaxAltitudeChangePerSecondMeters = 100.0;

// ============================================================================
// BATTERY CONSTANTS
// ============================================================================

/// Maximum battery percentage (100%).
const int kMaxBatteryPercent = 100;

/// Minimum battery percentage (0%).
const int kMinBatteryPercent = 0;

/// Default low battery threshold percentage.
const int kDefaultLowBatteryThreshold = 20;

/// Default critical battery threshold percentage.
const int kDefaultCriticalBatteryThreshold = 10;

// ============================================================================
// SYNC CONSTANTS
// ============================================================================

/// Default sync batch size.
const int kDefaultBatchSize = 100;

/// Maximum dead letter queue size.
const int kMaxDeadLetterQueueSize = 100;

/// Default max records to persist.
const int kDefaultMaxRecordsToPersist = 1000;

// ============================================================================
// STORAGE CONSTANTS
// ============================================================================

/// Maximum log storage size in bytes.
const int kMaxLogStorageBytes = 50000;

/// Maximum locations in memory cache.
const int kMaxLocationsInCache = 50;

// ============================================================================
// CONFIDENCE CONSTANTS
// ============================================================================

/// Maximum confidence percentage (100%).
const int kMaxConfidencePercent = 100;

/// Default activity confidence.
const int kDefaultActivityConfidence = 100;

// ============================================================================
// SPOOF DETECTION CONSTANTS
// ============================================================================

/// Default number of factors needed to detect spoofing.
const int kDefaultMinSpoofFactors = 2;

/// Threshold for repeated coordinates detection.
const int kRepeatedCoordinatesThreshold = 3;
