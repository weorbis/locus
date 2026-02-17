/// Adaptive tracking configuration for intelligent battery optimization.
///
/// Automatically adjusts GPS polling frequency, accuracy, and behavior
/// based on motion state, speed, battery level, and activity recognition.
library;

import 'package:locus/src/config/config_enums.dart';
import 'package:locus/src/models.dart';

/// Configuration for adaptive tracking behavior.
///
/// Adaptive tracking dynamically adjusts location settings based on
/// current conditions to optimize battery life while maintaining
/// the required accuracy for your use case.
///
/// Example:
/// ```dart
/// final config = Config(
///   adaptiveTracking: AdaptiveTrackingConfig(
///     enabled: true,
///     speedTiers: SpeedTiers.driving,
///     batteryThresholds: BatteryThresholds.conservative,
///     activityOptimization: true,
///   ),
/// );
/// ```
class AdaptiveTrackingConfig {
  /// Creates an adaptive tracking configuration.
  const AdaptiveTrackingConfig({
    this.enabled = true,
    this.speedTiers = const SpeedTiers(),
    this.batteryThresholds = const BatteryThresholds(),
    this.activityOptimization = true,
    this.stationaryGpsOff = true,
    this.stationaryDelay = const Duration(minutes: 1),
    this.minAccuracyMeters = 100,
    this.filterDuplicates = true,
    this.duplicateDistanceMeters = 5,
    this.geofenceOptimization = true,
    this.smartHeartbeat = true,
    this.maxHeartbeatInterval = const Duration(minutes: 15),
    this.minHeartbeatInterval = const Duration(minutes: 1),
  });

  /// Creates from a map.
  factory AdaptiveTrackingConfig.fromMap(JsonMap map) {
    return AdaptiveTrackingConfig(
      enabled: map['enabled'] as bool? ?? true,
      speedTiers: map['speedTiers'] is Map
          ? SpeedTiers.fromMap(
              Map<String, dynamic>.from(map['speedTiers'] as Map))
          : const SpeedTiers(),
      batteryThresholds: map['batteryThresholds'] is Map
          ? BatteryThresholds.fromMap(
              Map<String, dynamic>.from(map['batteryThresholds'] as Map))
          : const BatteryThresholds(),
      activityOptimization: map['activityOptimization'] as bool? ?? true,
      stationaryGpsOff: map['stationaryGpsOff'] as bool? ?? true,
      stationaryDelay: Duration(
        milliseconds: (map['stationaryDelayMs'] as num?)?.toInt() ?? 60000,
      ),
      minAccuracyMeters: (map['minAccuracyMeters'] as num?)?.toDouble() ?? 100,
      filterDuplicates: map['filterDuplicates'] as bool? ?? true,
      duplicateDistanceMeters:
          (map['duplicateDistanceMeters'] as num?)?.toDouble() ?? 5,
      geofenceOptimization: map['geofenceOptimization'] as bool? ?? true,
      smartHeartbeat: map['smartHeartbeat'] as bool? ?? true,
      maxHeartbeatInterval: Duration(
        milliseconds:
            (map['maxHeartbeatIntervalMs'] as num?)?.toInt() ?? 900000,
      ),
      minHeartbeatInterval: Duration(
        milliseconds: (map['minHeartbeatIntervalMs'] as num?)?.toInt() ?? 60000,
      ),
    );
  }

  /// Whether adaptive tracking is enabled.
  final bool enabled;

  /// Speed-based update interval tiers.
  final SpeedTiers speedTiers;

  /// Battery level thresholds for optimization.
  final BatteryThresholds batteryThresholds;

  /// Whether to optimize based on activity recognition.
  ///
  /// When enabled, will use lower accuracy when stationary, walking,
  /// and higher accuracy when in a vehicle.
  final bool activityOptimization;

  /// Whether to disable GPS when stationary for extended periods.
  final bool stationaryGpsOff;

  /// Time to wait before disabling GPS after becoming stationary.
  final Duration stationaryDelay;

  /// Minimum accuracy to accept when in power-saving mode.
  ///
  /// Locations with worse accuracy may be filtered.
  final double minAccuracyMeters;

  /// Whether to skip duplicate locations.
  ///
  /// Filters locations that are within [duplicateDistanceMeters]
  /// of the previous location.
  final bool filterDuplicates;

  /// Distance threshold for duplicate detection.
  final double duplicateDistanceMeters;

  /// Whether to downgrade accuracy when in a geofence.
  final bool geofenceOptimization;

  /// Whether to enable smart heartbeat (extend interval when stationary).
  final bool smartHeartbeat;

  /// Maximum heartbeat interval when stationary.
  final Duration maxHeartbeatInterval;

  /// Minimum heartbeat interval when moving.
  final Duration minHeartbeatInterval;

  /// Disabled - no adaptive optimization.
  static const AdaptiveTrackingConfig disabled = AdaptiveTrackingConfig(
    enabled: false,
  );

  /// Balanced preset - moderate optimization.
  static const AdaptiveTrackingConfig balanced = AdaptiveTrackingConfig(
    enabled: true,
    speedTiers: SpeedTiers.balanced,
    batteryThresholds: BatteryThresholds.balanced,
    activityOptimization: true,
    stationaryGpsOff: true,
    stationaryDelay: Duration(seconds: 30),
  );

  /// Aggressive preset - maximum battery savings.
  static const AdaptiveTrackingConfig aggressive = AdaptiveTrackingConfig(
    enabled: true,
    speedTiers: SpeedTiers.conservative,
    batteryThresholds: BatteryThresholds.conservative,
    activityOptimization: true,
    stationaryGpsOff: true,
    stationaryDelay: Duration(seconds: 15),
    minAccuracyMeters: 150,
    filterDuplicates: true,
    duplicateDistanceMeters: 10,
    geofenceOptimization: true,
    smartHeartbeat: true,
    maxHeartbeatInterval: Duration(minutes: 30),
  );

  /// Calculates optimal settings based on current conditions.
  AdaptiveSettings calculateSettings({
    required double speedMps,
    required int batteryPercent,
    required bool isCharging,
    required bool isMoving,
    required ActivityType? activity,
    required bool isInGeofence,
    Duration? timeSinceStationary,
  }) {
    // When charging, use high performance settings
    if (isCharging) {
      return const AdaptiveSettings(
        distanceFilter: 10,
        desiredAccuracy: DesiredAccuracy.high,
        heartbeatInterval: 60,
        gpsEnabled: true,
        reason: 'Charging - high performance mode',
      );
    }

    // Low battery mode
    final batteryLevel = batteryThresholds.getLevel(batteryPercent);
    if (batteryLevel == BatteryLevel.critical) {
      return const AdaptiveSettings(
        distanceFilter: 200,
        desiredAccuracy: DesiredAccuracy.low,
        heartbeatInterval: 900, // 15 minutes
        gpsEnabled: false,
        reason: 'Critical battery - minimal tracking',
      );
    }

    if (batteryLevel == BatteryLevel.low) {
      return AdaptiveSettings(
        distanceFilter: 100,
        desiredAccuracy: DesiredAccuracy.medium,
        heartbeatInterval: smartHeartbeat ? 300 : 120,
        gpsEnabled: isMoving,
        reason: 'Low battery - reduced tracking',
      );
    }

    // Stationary optimization - with stationaryDelay check
    if (!isMoving && stationaryGpsOff) {
      // Only disable GPS after stationaryDelay has passed
      final hasExceededDelay =
          timeSinceStationary == null || timeSinceStationary >= stationaryDelay;

      if (hasExceededDelay) {
        final heartbeat = smartHeartbeat
            ? (batteryLevel == BatteryLevel.low
                ? maxHeartbeatInterval.inSeconds
                : ((maxHeartbeatInterval.inSeconds +
                        minHeartbeatInterval.inSeconds) ~/
                    2))
            : minHeartbeatInterval.inSeconds;
        return AdaptiveSettings(
          distanceFilter: 50,
          desiredAccuracy: DesiredAccuracy.low,
          heartbeatInterval: heartbeat,
          gpsEnabled: false,
          reason: 'Stationary (${stationaryDelay.inSeconds}s) - GPS disabled',
        );
      }
    }

    // Activity-based optimization (when enabled)
    if (activityOptimization && activity != null) {
      final activitySettings = _getActivityBasedSettings(activity, speedMps);
      if (activitySettings != null) {
        return activitySettings;
      }
    }

    // Geofence optimization
    if (isInGeofence && geofenceOptimization && !isMoving) {
      return const AdaptiveSettings(
        distanceFilter: 25,
        desiredAccuracy: DesiredAccuracy.medium,
        heartbeatInterval: 180,
        gpsEnabled: true,
        reason: 'In geofence - reduced accuracy',
      );
    }

    // Speed-based optimization (fallback)
    final speedKph = speedMps * 3.6;
    final tier = speedTiers.getTier(speedKph);

    return AdaptiveSettings(
      distanceFilter: tier.distanceFilter.toDouble(),
      desiredAccuracy: tier.accuracy,
      heartbeatInterval: tier.updateInterval,
      gpsEnabled: true,
      reason: 'Speed-based: ${tier.name}',
    );
  }

  /// Returns activity-specific settings, or null to fall through to speed-based.
  AdaptiveSettings? _getActivityBasedSettings(
    ActivityType activity,
    double speedMps,
  ) {
    switch (activity) {
      case ActivityType.still:
        // User is stationary - use minimal tracking
        return AdaptiveSettings(
          distanceFilter: 50,
          desiredAccuracy: DesiredAccuracy.low,
          heartbeatInterval: smartHeartbeat ? 300 : 120,
          gpsEnabled: false,
          reason: 'Activity: still',
        );

      case ActivityType.walking:
        // Walking - moderate accuracy, frequent updates
        return const AdaptiveSettings(
          distanceFilter: 10,
          desiredAccuracy: DesiredAccuracy.medium,
          heartbeatInterval: 30,
          gpsEnabled: true,
          reason: 'Activity: walking',
        );

      case ActivityType.running:
        // Running - higher accuracy for fitness tracking
        return const AdaptiveSettings(
          distanceFilter: 8,
          desiredAccuracy: DesiredAccuracy.high,
          heartbeatInterval: 15,
          gpsEnabled: true,
          reason: 'Activity: running',
        );

      case ActivityType.onBicycle:
        // Cycling - high accuracy, frequent updates
        return const AdaptiveSettings(
          distanceFilter: 15,
          desiredAccuracy: DesiredAccuracy.high,
          heartbeatInterval: 10,
          gpsEnabled: true,
          reason: 'Activity: cycling',
        );

      case ActivityType.inVehicle:
        // In vehicle - highest accuracy for navigation/fleet
        return const AdaptiveSettings(
          distanceFilter: 20,
          desiredAccuracy: DesiredAccuracy.high,
          heartbeatInterval: 5,
          gpsEnabled: true,
          reason: 'Activity: in vehicle',
        );

      case ActivityType.onFoot:
        // Generic on foot - fallback to speed-based
        return null;

      case ActivityType.tilting:
      case ActivityType.unknown:
        // Unknown or tilting - fall through to speed-based
        return null;
    }
  }

  /// Creates a copy with the given fields replaced.
  AdaptiveTrackingConfig copyWith({
    bool? enabled,
    SpeedTiers? speedTiers,
    BatteryThresholds? batteryThresholds,
    bool? activityOptimization,
    bool? stationaryGpsOff,
    Duration? stationaryDelay,
    double? minAccuracyMeters,
    bool? filterDuplicates,
    double? duplicateDistanceMeters,
    bool? geofenceOptimization,
    bool? smartHeartbeat,
    Duration? maxHeartbeatInterval,
    Duration? minHeartbeatInterval,
  }) {
    return AdaptiveTrackingConfig(
      enabled: enabled ?? this.enabled,
      speedTiers: speedTiers ?? this.speedTiers,
      batteryThresholds: batteryThresholds ?? this.batteryThresholds,
      activityOptimization: activityOptimization ?? this.activityOptimization,
      stationaryGpsOff: stationaryGpsOff ?? this.stationaryGpsOff,
      stationaryDelay: stationaryDelay ?? this.stationaryDelay,
      minAccuracyMeters: minAccuracyMeters ?? this.minAccuracyMeters,
      filterDuplicates: filterDuplicates ?? this.filterDuplicates,
      duplicateDistanceMeters:
          duplicateDistanceMeters ?? this.duplicateDistanceMeters,
      geofenceOptimization: geofenceOptimization ?? this.geofenceOptimization,
      smartHeartbeat: smartHeartbeat ?? this.smartHeartbeat,
      maxHeartbeatInterval: maxHeartbeatInterval ?? this.maxHeartbeatInterval,
      minHeartbeatInterval: minHeartbeatInterval ?? this.minHeartbeatInterval,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'enabled': enabled,
        'speedTiers': speedTiers.toMap(),
        'batteryThresholds': batteryThresholds.toMap(),
        'activityOptimization': activityOptimization,
        'stationaryGpsOff': stationaryGpsOff,
        'stationaryDelayMs': stationaryDelay.inMilliseconds,
        'minAccuracyMeters': minAccuracyMeters,
        'filterDuplicates': filterDuplicates,
        'duplicateDistanceMeters': duplicateDistanceMeters,
        'geofenceOptimization': geofenceOptimization,
        'smartHeartbeat': smartHeartbeat,
        'maxHeartbeatIntervalMs': maxHeartbeatInterval.inMilliseconds,
        'minHeartbeatIntervalMs': minHeartbeatInterval.inMilliseconds,
      };
}

/// Speed-based update interval tiers.
///
/// Configures how update intervals change based on current speed.
class SpeedTiers {
  /// Creates speed tiers.
  const SpeedTiers({
    this.stationary = const SpeedTier(
      name: 'stationary',
      minSpeedKph: 0,
      maxSpeedKph: 0,
      updateInterval: 60,
      distanceFilter: 50,
      accuracy: DesiredAccuracy.low,
    ),
    this.walking = const SpeedTier(
      name: 'walking',
      minSpeedKph: 0,
      maxSpeedKph: 5,
      updateInterval: 20,
      distanceFilter: 15,
      accuracy: DesiredAccuracy.medium,
    ),
    this.city = const SpeedTier(
      name: 'city',
      minSpeedKph: 5,
      maxSpeedKph: 30,
      updateInterval: 10,
      distanceFilter: 10,
      accuracy: DesiredAccuracy.high,
    ),
    this.suburban = const SpeedTier(
      name: 'suburban',
      minSpeedKph: 30,
      maxSpeedKph: 80,
      updateInterval: 7,
      distanceFilter: 15,
      accuracy: DesiredAccuracy.high,
    ),
    this.highway = const SpeedTier(
      name: 'highway',
      minSpeedKph: 80,
      maxSpeedKph: 999,
      updateInterval: 5,
      distanceFilter: 25,
      accuracy: DesiredAccuracy.high,
    ),
  });

  /// Creates from a map.
  factory SpeedTiers.fromMap(JsonMap map) {
    return SpeedTiers(
      stationary: map['stationary'] is Map
          ? SpeedTier.fromMap(
              Map<String, dynamic>.from(map['stationary'] as Map))
          : const SpeedTier(
              name: 'stationary',
              minSpeedKph: 0,
              maxSpeedKph: 0,
              updateInterval: 60,
              distanceFilter: 50,
              accuracy: DesiredAccuracy.low,
            ),
      walking: map['walking'] is Map
          ? SpeedTier.fromMap(Map<String, dynamic>.from(map['walking'] as Map))
          : const SpeedTier(
              name: 'walking',
              minSpeedKph: 0,
              maxSpeedKph: 5,
              updateInterval: 20,
              distanceFilter: 15,
              accuracy: DesiredAccuracy.medium,
            ),
      city: map['city'] is Map
          ? SpeedTier.fromMap(Map<String, dynamic>.from(map['city'] as Map))
          : const SpeedTier(
              name: 'city',
              minSpeedKph: 5,
              maxSpeedKph: 30,
              updateInterval: 10,
              distanceFilter: 10,
              accuracy: DesiredAccuracy.high,
            ),
      suburban: map['suburban'] is Map
          ? SpeedTier.fromMap(Map<String, dynamic>.from(map['suburban'] as Map))
          : const SpeedTier(
              name: 'suburban',
              minSpeedKph: 30,
              maxSpeedKph: 80,
              updateInterval: 7,
              distanceFilter: 15,
              accuracy: DesiredAccuracy.high,
            ),
      highway: map['highway'] is Map
          ? SpeedTier.fromMap(Map<String, dynamic>.from(map['highway'] as Map))
          : const SpeedTier(
              name: 'highway',
              minSpeedKph: 80,
              maxSpeedKph: 999,
              updateInterval: 5,
              distanceFilter: 25,
              accuracy: DesiredAccuracy.high,
            ),
    );
  }

  /// Tier for stationary (0 km/h).
  final SpeedTier stationary;

  /// Tier for walking speed (<5 km/h).
  final SpeedTier walking;

  /// Tier for city driving (5-30 km/h).
  final SpeedTier city;

  /// Tier for suburban driving (30-80 km/h).
  final SpeedTier suburban;

  /// Tier for highway driving (>80 km/h).
  final SpeedTier highway;

  /// Balanced preset - good for most use cases.
  static const SpeedTiers balanced = SpeedTiers();

  /// Driving-optimized - higher frequency at high speeds.
  static const SpeedTiers driving = SpeedTiers(
    stationary: SpeedTier(
      name: 'stationary',
      minSpeedKph: 0,
      maxSpeedKph: 0,
      updateInterval: 30,
      distanceFilter: 25,
      accuracy: DesiredAccuracy.medium,
    ),
    highway: SpeedTier(
      name: 'highway',
      minSpeedKph: 80,
      maxSpeedKph: 999,
      updateInterval: 3,
      distanceFilter: 20,
      accuracy: DesiredAccuracy.high,
    ),
  );

  /// Conservative preset - maximize battery savings.
  static const SpeedTiers conservative = SpeedTiers(
    stationary: SpeedTier(
      name: 'stationary',
      minSpeedKph: 0,
      maxSpeedKph: 0,
      updateInterval: 120,
      distanceFilter: 100,
      accuracy: DesiredAccuracy.low,
    ),
    walking: SpeedTier(
      name: 'walking',
      minSpeedKph: 0,
      maxSpeedKph: 5,
      updateInterval: 30,
      distanceFilter: 25,
      accuracy: DesiredAccuracy.medium,
    ),
    city: SpeedTier(
      name: 'city',
      minSpeedKph: 5,
      maxSpeedKph: 30,
      updateInterval: 15,
      distanceFilter: 15,
      accuracy: DesiredAccuracy.medium,
    ),
    suburban: SpeedTier(
      name: 'suburban',
      minSpeedKph: 30,
      maxSpeedKph: 80,
      updateInterval: 10,
      distanceFilter: 25,
      accuracy: DesiredAccuracy.high,
    ),
    highway: SpeedTier(
      name: 'highway',
      minSpeedKph: 80,
      maxSpeedKph: 999,
      updateInterval: 7,
      distanceFilter: 35,
      accuracy: DesiredAccuracy.high,
    ),
  );

  /// Gets the appropriate tier for a given speed.
  SpeedTier getTier(double speedKph) {
    if (speedKph <= 0) return stationary;
    if (speedKph < 5) return walking;
    if (speedKph < 30) return city;
    if (speedKph < 80) return suburban;
    return highway;
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'stationary': stationary.toMap(),
        'walking': walking.toMap(),
        'city': city.toMap(),
        'suburban': suburban.toMap(),
        'highway': highway.toMap(),
      };
}

/// Configuration for a single speed tier.
class SpeedTier {
  /// Creates a speed tier.
  const SpeedTier({
    required this.name,
    required this.minSpeedKph,
    required this.maxSpeedKph,
    required this.updateInterval,
    required this.distanceFilter,
    required this.accuracy,
  });

  /// Creates from a map.
  factory SpeedTier.fromMap(JsonMap map) {
    return SpeedTier(
      name: map['name'] as String? ?? 'unknown',
      minSpeedKph: (map['minSpeedKph'] as num?)?.toDouble() ?? 0,
      maxSpeedKph: (map['maxSpeedKph'] as num?)?.toDouble() ?? 999,
      updateInterval: (map['updateInterval'] as num?)?.toInt() ?? 10,
      distanceFilter: (map['distanceFilter'] as num?)?.toInt() ?? 10,
      accuracy: DesiredAccuracy.values.firstWhere(
        (e) => e.name == map['accuracy'],
        orElse: () => DesiredAccuracy.high,
      ),
    );
  }

  /// Descriptive name for this tier.
  final String name;

  /// Minimum speed for this tier in km/h.
  final double minSpeedKph;

  /// Maximum speed for this tier in km/h.
  final double maxSpeedKph;

  /// Update interval in seconds.
  final int updateInterval;

  /// Distance filter in meters.
  final int distanceFilter;

  /// Desired accuracy for this tier.
  final DesiredAccuracy accuracy;

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'name': name,
        'minSpeedKph': minSpeedKph,
        'maxSpeedKph': maxSpeedKph,
        'updateInterval': updateInterval,
        'distanceFilter': distanceFilter,
        'accuracy': accuracy.name,
      };
}

/// Battery level thresholds for optimization.
class BatteryThresholds {
  /// Creates battery thresholds.
  const BatteryThresholds({
    this.lowThreshold = 20,
    this.criticalThreshold = 10,
  });

  /// Creates from a map.
  factory BatteryThresholds.fromMap(JsonMap map) {
    return BatteryThresholds(
      lowThreshold: (map['lowThreshold'] as num?)?.toInt() ?? 20,
      criticalThreshold: (map['criticalThreshold'] as num?)?.toInt() ?? 10,
    );
  }

  /// Battery percentage below which is considered low.
  final int lowThreshold;

  /// Battery percentage below which is considered critical.
  final int criticalThreshold;

  /// Balanced thresholds.
  static const BatteryThresholds balanced = BatteryThresholds(
    lowThreshold: 20,
    criticalThreshold: 10,
  );

  /// Conservative thresholds - start saving earlier.
  static const BatteryThresholds conservative = BatteryThresholds(
    lowThreshold: 30,
    criticalThreshold: 15,
  );

  /// Gets the battery level category.
  BatteryLevel getLevel(int percent) {
    if (percent <= criticalThreshold) return BatteryLevel.critical;
    if (percent <= lowThreshold) return BatteryLevel.low;
    return BatteryLevel.normal;
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'lowThreshold': lowThreshold,
        'criticalThreshold': criticalThreshold,
      };
}

/// Battery level categories.
enum BatteryLevel {
  /// Normal battery level - no optimization needed.
  normal,

  /// Low battery - apply moderate optimization.
  low,

  /// Critical battery - apply aggressive optimization.
  critical,
}

/// Calculated adaptive settings based on current conditions.
class AdaptiveSettings {
  /// Creates adaptive settings.
  const AdaptiveSettings({
    required this.distanceFilter,
    required this.desiredAccuracy,
    required this.heartbeatInterval,
    required this.gpsEnabled,
    required this.reason,
  });

  /// Recommended distance filter in meters.
  final double distanceFilter;

  /// Recommended accuracy level.
  final DesiredAccuracy desiredAccuracy;

  /// Recommended heartbeat interval in seconds.
  final int heartbeatInterval;

  /// Whether GPS should be enabled.
  final bool gpsEnabled;

  /// Reason for these settings.
  final String reason;

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'distanceFilter': distanceFilter,
        'desiredAccuracy': desiredAccuracy.name,
        'heartbeatInterval': heartbeatInterval,
        'gpsEnabled': gpsEnabled,
        'reason': reason,
      };

  @override
  String toString() => 'AdaptiveSettings(filter: ${distanceFilter}m, '
      'accuracy: ${desiredAccuracy.name}, '
      'heartbeat: ${heartbeatInterval}s, '
      'gps: $gpsEnabled, '
      'reason: $reason)';
}
