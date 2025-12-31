/// Battery statistics tracking for monitoring power consumption.
///
/// Provides metrics on GPS usage, location updates, and sync activity
/// to help developers understand and optimize battery consumption.
library;

import 'package:locus/src/models/common/json_map.dart';

/// Statistics about battery usage during location tracking.
///
/// Use these metrics to understand how your tracking configuration
/// affects battery consumption and to identify optimization opportunities.
///
/// Example:
/// ```dart
/// final stats = await Locus.getBatteryStats();
/// print('GPS active: ${stats.gpsOnTimePercent.toStringAsFixed(1)}%');
/// print('Drain estimate: ${stats.estimatedDrainPerHour}%/hr');
/// ```
class BatteryStats {
  /// Percentage of tracking time GPS was actively acquiring locations.
  ///
  /// Lower is better - indicates effective use of motion detection
  /// to disable GPS when stationary.
  final double gpsOnTimePercent;

  /// Total number of location updates received since tracking started.
  final int locationUpdatesCount;

  /// Number of HTTP sync requests made.
  ///
  /// Fewer, larger batches are more efficient than frequent small syncs.
  final int syncRequestsCount;

  /// Average horizontal accuracy of received locations in meters.
  ///
  /// Higher accuracy often means higher battery consumption.
  final double averageAccuracyMeters;

  /// Total tracking duration in minutes.
  final int trackingDurationMinutes;

  /// Estimated battery drain percentage since tracking started.
  ///
  /// May be null if system stats aren't available.
  final double? estimatedDrainPercent;

  /// Estimated drain per hour based on current patterns.
  ///
  /// Calculated from: estimatedDrainPercent / (trackingDurationMinutes / 60)
  double? get estimatedDrainPerHour {
    if (estimatedDrainPercent == null || trackingDurationMinutes < 1) {
      return null;
    }
    return estimatedDrainPercent! / (trackingDurationMinutes / 60);
  }

  /// Current optimization level being applied.
  final OptimizationLevel optimizationLevel;

  /// Time spent in each motion state.
  ///
  /// Keys include: 'moving', 'stationary', 'unknown'
  final Map<String, Duration> timeByState;

  /// Current battery level (0-100) if available.
  final int? currentBatteryLevel;

  /// Whether the device is currently charging.
  final bool? isCharging;

  /// Number of accuracy downgrades due to battery saving.
  final int accuracyDowngradeCount;

  /// Number of times GPS was disabled due to stationary detection.
  final int gpsDisabledCount;

  /// Average time between location updates in seconds.
  double? get averageUpdateIntervalSeconds {
    if (locationUpdatesCount < 2 || trackingDurationMinutes < 1) {
      return null;
    }
    return (trackingDurationMinutes * 60) / (locationUpdatesCount - 1);
  }

  /// Creates battery statistics.
  const BatteryStats({
    this.gpsOnTimePercent = 0,
    this.locationUpdatesCount = 0,
    this.syncRequestsCount = 0,
    this.averageAccuracyMeters = 0,
    this.trackingDurationMinutes = 0,
    this.estimatedDrainPercent,
    this.optimizationLevel = OptimizationLevel.none,
    this.timeByState = const {},
    this.currentBatteryLevel,
    this.isCharging,
    this.accuracyDowngradeCount = 0,
    this.gpsDisabledCount = 0,
  });

  /// Creates an empty stats object.
  const BatteryStats.empty()
      : gpsOnTimePercent = 0,
        locationUpdatesCount = 0,
        syncRequestsCount = 0,
        averageAccuracyMeters = 0,
        trackingDurationMinutes = 0,
        estimatedDrainPercent = null,
        optimizationLevel = OptimizationLevel.none,
        timeByState = const {},
        currentBatteryLevel = null,
        isCharging = null,
        accuracyDowngradeCount = 0,
        gpsDisabledCount = 0;

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'gpsOnTimePercent': gpsOnTimePercent,
        'locationUpdatesCount': locationUpdatesCount,
        'syncRequestsCount': syncRequestsCount,
        'averageAccuracyMeters': averageAccuracyMeters,
        'trackingDurationMinutes': trackingDurationMinutes,
        if (estimatedDrainPercent != null)
          'estimatedDrainPercent': estimatedDrainPercent,
        if (estimatedDrainPerHour != null)
          'estimatedDrainPerHour': estimatedDrainPerHour,
        'optimizationLevel': optimizationLevel.name,
        'timeByState': timeByState.map(
          (k, v) => MapEntry(k, v.inSeconds),
        ),
        if (currentBatteryLevel != null)
          'currentBatteryLevel': currentBatteryLevel,
        if (isCharging != null) 'isCharging': isCharging,
        'accuracyDowngradeCount': accuracyDowngradeCount,
        'gpsDisabledCount': gpsDisabledCount,
      };

  /// Creates from a map.
  factory BatteryStats.fromMap(JsonMap map) {
    final timeByStateRaw = map['timeByState'];
    final timeByState = <String, Duration>{};
    if (timeByStateRaw is Map) {
      for (final entry in timeByStateRaw.entries) {
        final seconds = entry.value as num?;
        if (seconds != null) {
          timeByState[entry.key.toString()] =
              Duration(seconds: seconds.toInt());
        }
      }
    }

    return BatteryStats(
      gpsOnTimePercent: (map['gpsOnTimePercent'] as num?)?.toDouble() ?? 0,
      locationUpdatesCount: (map['locationUpdatesCount'] as num?)?.toInt() ?? 0,
      syncRequestsCount: (map['syncRequestsCount'] as num?)?.toInt() ?? 0,
      averageAccuracyMeters:
          (map['averageAccuracyMeters'] as num?)?.toDouble() ?? 0,
      trackingDurationMinutes:
          (map['trackingDurationMinutes'] as num?)?.toInt() ?? 0,
      estimatedDrainPercent: (map['estimatedDrainPercent'] as num?)?.toDouble(),
      optimizationLevel: OptimizationLevel.values.firstWhere(
        (e) => e.name == map['optimizationLevel'],
        orElse: () => OptimizationLevel.none,
      ),
      timeByState: timeByState,
      currentBatteryLevel: (map['currentBatteryLevel'] as num?)?.toInt(),
      isCharging: map['isCharging'] as bool?,
      accuracyDowngradeCount:
          (map['accuracyDowngradeCount'] as num?)?.toInt() ?? 0,
      gpsDisabledCount: (map['gpsDisabledCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('BatteryStats(');
    buffer.write('gpsOn: ${gpsOnTimePercent.toStringAsFixed(1)}%, ');
    buffer.write('updates: $locationUpdatesCount, ');
    buffer.write('syncs: $syncRequestsCount, ');
    buffer.write('avgAccuracy: ${averageAccuracyMeters.toStringAsFixed(1)}m, ');
    buffer.write('duration: ${trackingDurationMinutes}min');
    if (estimatedDrainPerHour != null) {
      buffer.write(', drain: ${estimatedDrainPerHour!.toStringAsFixed(1)}%/hr');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// Battery optimization level.
///
/// Higher optimization means more aggressive battery saving but may
/// reduce location accuracy or update frequency.
enum OptimizationLevel {
  /// No battery optimization applied.
  ///
  /// Best accuracy and update frequency, highest power consumption.
  none,

  /// Balanced optimization.
  ///
  /// Moderate accuracy with reduced update frequency when stationary.
  balanced,

  /// Aggressive optimization.
  ///
  /// Priority on battery saving, may reduce accuracy and skip updates.
  aggressive,

  /// Ultra-low power mode.
  ///
  /// Significant location changes only, suitable for background monitoring.
  ultraLowPower,
}

/// Benchmark session for measuring battery consumption.
///
/// Use this to compare battery usage between different configurations.
///
/// Example:
/// ```dart
/// final benchmark = BatteryBenchmark();
/// await benchmark.start();
///
/// // ... run your tracking session ...
///
/// final result = await benchmark.finish();
/// print('Drain: ${result.drainPercent}% over ${result.duration.inMinutes} min');
/// ```
class BatteryBenchmark {
  DateTime? _startTime;
  int? _startBattery;
  int _locationUpdates = 0;
  int _syncRequests = 0;
  Duration _gpsOnTime = Duration.zero;
  DateTime? _gpsStartTime;
  double _totalAccuracy = 0;
  final Map<String, Duration> _timeByState = {};
  String _currentState = 'unknown';
  DateTime? _stateStartTime;

  /// Whether the benchmark is running.
  bool get isRunning => _startTime != null;

  /// Starts the benchmark session.
  ///
  /// [initialBattery] is the current battery level (0-100).
  void start({required int initialBattery}) {
    _startTime = DateTime.now();
    _startBattery = initialBattery;
    _locationUpdates = 0;
    _syncRequests = 0;
    _gpsOnTime = Duration.zero;
    _gpsStartTime = null;
    _totalAccuracy = 0;
    _timeByState.clear();
    _currentState = 'unknown';
    _stateStartTime = DateTime.now();
  }

  /// Records a location update.
  void recordLocationUpdate({double? accuracy}) {
    _locationUpdates++;
    if (accuracy != null) {
      _totalAccuracy += accuracy;
    }
  }

  /// Records an HTTP sync request.
  void recordSync() {
    _syncRequests++;
  }

  /// Records GPS being turned on.
  void recordGpsOn() {
    _gpsStartTime ??= DateTime.now();
  }

  /// Records GPS being turned off.
  void recordGpsOff() {
    if (_gpsStartTime != null) {
      _gpsOnTime += DateTime.now().difference(_gpsStartTime!);
      _gpsStartTime = null;
    }
  }

  /// Records a motion state change.
  void recordStateChange(String newState) {
    final now = DateTime.now();
    if (_stateStartTime != null) {
      final duration = now.difference(_stateStartTime!);
      _timeByState.update(
        _currentState,
        (existing) => existing + duration,
        ifAbsent: () => duration,
      );
    }
    _currentState = newState;
    _stateStartTime = now;
  }

  /// Finishes the benchmark and returns results.
  ///
  /// [currentBattery] is the current battery level (0-100).
  BenchmarkResult finish({required int currentBattery}) {
    if (_startTime == null || _startBattery == null) {
      throw StateError('Benchmark not started');
    }

    // Close any pending GPS time
    if (_gpsStartTime != null) {
      _gpsOnTime += DateTime.now().difference(_gpsStartTime!);
    }

    // Close current state
    if (_stateStartTime != null) {
      _timeByState.update(
        _currentState,
        (existing) => existing + DateTime.now().difference(_stateStartTime!),
        ifAbsent: () => DateTime.now().difference(_stateStartTime!),
      );
    }

    final duration = DateTime.now().difference(_startTime!);
    final drainPercent = _startBattery! - currentBattery;

    return BenchmarkResult(
      duration: duration,
      drainPercent: drainPercent.toDouble(),
      locationUpdates: _locationUpdates,
      syncRequests: _syncRequests,
      gpsOnPercent: duration.inSeconds > 0
          ? (_gpsOnTime.inSeconds / duration.inSeconds) * 100
          : 0,
      averageAccuracy:
          _locationUpdates > 0 ? _totalAccuracy / _locationUpdates : 0,
      timeByState: Map.unmodifiable(_timeByState),
    );
  }
}

/// Result of a battery benchmark session.
class BenchmarkResult {
  /// Total benchmark duration.
  final Duration duration;

  /// Battery drain percentage.
  final double drainPercent;

  /// Number of location updates received.
  final int locationUpdates;

  /// Number of sync requests made.
  final int syncRequests;

  /// Percentage of time GPS was active.
  final double gpsOnPercent;

  /// Average location accuracy in meters.
  final double averageAccuracy;

  /// Time spent in each motion state.
  final Map<String, Duration> timeByState;

  /// Drain rate per hour.
  double get drainPerHour {
    if (duration.inMinutes < 1) return 0;
    return drainPercent / (duration.inMinutes / 60);
  }

  /// Creates a benchmark result.
  const BenchmarkResult({
    required this.duration,
    required this.drainPercent,
    required this.locationUpdates,
    required this.syncRequests,
    required this.gpsOnPercent,
    required this.averageAccuracy,
    required this.timeByState,
  });

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'durationMinutes': duration.inMinutes,
        'drainPercent': drainPercent,
        'drainPerHour': drainPerHour,
        'locationUpdates': locationUpdates,
        'syncRequests': syncRequests,
        'gpsOnPercent': gpsOnPercent,
        'averageAccuracy': averageAccuracy,
        'timeByState': timeByState.map((k, v) => MapEntry(k, v.inSeconds)),
      };

  @override
  String toString() {
    return 'BenchmarkResult(duration: ${duration.inMinutes}min, '
        'drain: ${drainPercent.toStringAsFixed(1)}%, '
        'drainPerHour: ${drainPerHour.toStringAsFixed(1)}%/hr, '
        'updates: $locationUpdates, '
        'gpsOn: ${gpsOnPercent.toStringAsFixed(1)}%)';
  }
}
