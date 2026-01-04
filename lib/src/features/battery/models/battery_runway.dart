/// Battery runway estimation for predicting remaining tracking time.
///
/// Estimates how long location tracking can continue based on current
/// battery level, drain rate, and tracking profile.
library;

import 'package:locus/src/shared/models/json_map.dart';

/// Result of battery runway estimation.
///
/// Provides predictions for how long tracking can continue at current
/// and alternative power consumption rates.
///
/// Example:
/// ```dart
/// final runway = await Locus.estimateBatteryRunway();
/// print('At current rate: ${runway.duration.inHours}h ${runway.duration.inMinutes % 60}m');
/// print('In low power mode: ${runway.lowPowerDuration.inHours}h');
/// print('Recommendation: ${runway.recommendation}');
/// ```
class BatteryRunway {
  /// Estimated remaining tracking duration at current drain rate.
  ///
  /// Returns [Duration.zero] if battery is depleted or estimation
  /// cannot be performed.
  final Duration duration;

  /// Estimated remaining tracking duration in low power mode.
  ///
  /// Low power mode uses significant-change-only tracking with
  /// reduced GPS polling and sync frequency.
  final Duration lowPowerDuration;

  /// Human-readable recommendation based on current state.
  ///
  /// Examples:
  /// - "Battery sufficient for 4+ hours of tracking"
  /// - "Consider switching to low power mode"
  /// - "Battery critical - tracking may stop soon"
  final String recommendation;

  /// Current battery level (0-100).
  final int currentLevel;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Current drain rate in percent per hour.
  ///
  /// May be null if insufficient data to calculate.
  final double? drainRatePerHour;

  /// Low power mode drain rate in percent per hour.
  ///
  /// Estimated based on typical low-power tracking patterns.
  final double? lowPowerDrainRatePerHour;

  /// Confidence level of the estimation (0.0 - 1.0).
  ///
  /// Higher values indicate more reliable estimates based on
  /// longer observation periods and stable conditions.
  final double confidence;

  /// Minimum battery level required for reliable tracking.
  ///
  /// Below this level, tracking may become unreliable due to
  /// system power-saving measures.
  static const int minReliableLevel = 15;

  /// Critical battery level threshold.
  ///
  /// At or below this level, immediate action is recommended.
  static const int criticalLevel = 5;

  /// Creates a battery runway estimation.
  const BatteryRunway({
    required this.duration,
    required this.lowPowerDuration,
    required this.recommendation,
    required this.currentLevel,
    this.isCharging = false,
    this.drainRatePerHour,
    this.lowPowerDrainRatePerHour,
    this.confidence = 0.0,
  });

  /// Creates an estimation indicating insufficient data.
  const BatteryRunway.insufficientData({
    required this.currentLevel,
    this.isCharging = false,
  })  : duration = Duration.zero,
        lowPowerDuration = Duration.zero,
        recommendation = 'Insufficient tracking data for estimation',
        drainRatePerHour = null,
        lowPowerDrainRatePerHour = null,
        confidence = 0.0;

  /// Creates an estimation for a charging device.
  const BatteryRunway.charging({
    required this.currentLevel,
  })  : duration = const Duration(hours: 999),
        lowPowerDuration = const Duration(hours: 999),
        recommendation = 'Device is charging - unlimited tracking available',
        isCharging = true,
        drainRatePerHour = 0.0,
        lowPowerDrainRatePerHour = 0.0,
        confidence = 1.0;

  /// Whether the battery level is critical.
  bool get isCritical => currentLevel <= criticalLevel && !isCharging;

  /// Whether the battery level is low but not critical.
  bool get isLow =>
      currentLevel <= minReliableLevel &&
      currentLevel > criticalLevel &&
      !isCharging;

  /// Whether the estimation suggests switching to low power mode.
  bool get shouldSwitchToLowPower =>
      !isCharging && duration.inMinutes < 60 && lowPowerDuration > duration;

  /// Formatted duration string for display.
  String get formattedDuration => _formatDuration(duration);

  /// Formatted low power duration string for display.
  String get formattedLowPowerDuration => _formatDuration(lowPowerDuration);

  String _formatDuration(Duration d) {
    if (d.inHours >= 999) return 'Unlimited';
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'durationMinutes': duration.inMinutes,
        'lowPowerDurationMinutes': lowPowerDuration.inMinutes,
        'recommendation': recommendation,
        'currentLevel': currentLevel,
        'isCharging': isCharging,
        if (drainRatePerHour != null) 'drainRatePerHour': drainRatePerHour,
        if (lowPowerDrainRatePerHour != null)
          'lowPowerDrainRatePerHour': lowPowerDrainRatePerHour,
        'confidence': confidence,
        'isCritical': isCritical,
        'isLow': isLow,
        'shouldSwitchToLowPower': shouldSwitchToLowPower,
        'formattedDuration': formattedDuration,
        'formattedLowPowerDuration': formattedLowPowerDuration,
      };

  /// Creates from a map.
  factory BatteryRunway.fromMap(JsonMap map) {
    return BatteryRunway(
      duration: Duration(minutes: (map['durationMinutes'] as num?)?.toInt() ?? 0),
      lowPowerDuration:
          Duration(minutes: (map['lowPowerDurationMinutes'] as num?)?.toInt() ?? 0),
      recommendation: map['recommendation'] as String? ?? '',
      currentLevel: (map['currentLevel'] as num?)?.toInt() ?? 0,
      isCharging: map['isCharging'] as bool? ?? false,
      drainRatePerHour: (map['drainRatePerHour'] as num?)?.toDouble(),
      lowPowerDrainRatePerHour:
          (map['lowPowerDrainRatePerHour'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() {
    return 'BatteryRunway('
        'duration: $formattedDuration, '
        'lowPower: $formattedLowPowerDuration, '
        'level: $currentLevel%, '
        'charging: $isCharging, '
        'confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
  }
}

/// Calculator for battery runway estimation.
///
/// Uses battery statistics and current state to predict remaining
/// tracking time.
class BatteryRunwayCalculator {
  /// Low power mode drain rate multiplier.
  ///
  /// Assumes low power mode uses approximately 40% of normal drain.
  static const double lowPowerMultiplier = 0.4;

  /// Minimum tracking minutes required for reliable estimation.
  static const int minTrackingMinutes = 5;

  /// Default drain rate when no data is available (percent per hour).
  static const double defaultDrainRate = 5.0;

  /// Calculates battery runway from current statistics.
  ///
  /// [currentLevel] - Current battery percentage (0-100)
  /// [isCharging] - Whether device is currently charging
  /// [drainPercent] - Estimated drain since tracking started
  /// [trackingMinutes] - Duration of current tracking session
  /// [reserveLevel] - Battery level to reserve (default: 5%)
  static BatteryRunway calculate({
    required int currentLevel,
    required bool isCharging,
    double? drainPercent,
    int trackingMinutes = 0,
    int reserveLevel = 5,
  }) {
    // If charging, tracking is unlimited
    if (isCharging) {
      return BatteryRunway.charging(currentLevel: currentLevel);
    }

    // Calculate drain rate
    double? drainRatePerHour;
    double confidence = 0.0;

    if (drainPercent != null && trackingMinutes >= minTrackingMinutes) {
      drainRatePerHour = drainPercent / (trackingMinutes / 60);
      // Confidence increases with more tracking time, capped at 1.0
      confidence = (trackingMinutes / 60).clamp(0.0, 1.0);
    }

    // Use calculated rate or fall back to default
    final effectiveDrainRate = drainRatePerHour ?? defaultDrainRate;
    final lowPowerDrainRate = effectiveDrainRate * lowPowerMultiplier;

    // Calculate available battery (above reserve)
    final availableLevel = (currentLevel - reserveLevel).clamp(0, 100);

    // Calculate durations
    final durationMinutes = effectiveDrainRate > 0
        ? (availableLevel / effectiveDrainRate * 60).round()
        : 0;
    final lowPowerMinutes = lowPowerDrainRate > 0
        ? (availableLevel / lowPowerDrainRate * 60).round()
        : 0;

    // Generate recommendation
    final recommendation = _generateRecommendation(
      currentLevel: currentLevel,
      durationMinutes: durationMinutes,
      lowPowerMinutes: lowPowerMinutes,
      confidence: confidence,
    );

    return BatteryRunway(
      duration: Duration(minutes: durationMinutes),
      lowPowerDuration: Duration(minutes: lowPowerMinutes),
      recommendation: recommendation,
      currentLevel: currentLevel,
      isCharging: false,
      drainRatePerHour: drainRatePerHour,
      lowPowerDrainRatePerHour: lowPowerDrainRate,
      confidence: confidence,
    );
  }

  static String _generateRecommendation({
    required int currentLevel,
    required int durationMinutes,
    required int lowPowerMinutes,
    required double confidence,
  }) {
    if (currentLevel <= BatteryRunway.criticalLevel) {
      return 'Battery critical - tracking may stop soon. '
          'Connect to power or stop tracking.';
    }

    if (currentLevel <= BatteryRunway.minReliableLevel) {
      return 'Battery low - consider switching to low power mode '
          'for ${_formatMinutes(lowPowerMinutes)} of additional tracking.';
    }

    if (durationMinutes < 30) {
      return 'Less than 30 minutes remaining. '
          'Switch to low power mode for ${_formatMinutes(lowPowerMinutes)}.';
    }

    if (durationMinutes < 60) {
      return 'About ${_formatMinutes(durationMinutes)} remaining. '
          'Low power mode would extend to ${_formatMinutes(lowPowerMinutes)}.';
    }

    if (durationMinutes < 240) {
      return 'Battery sufficient for ${_formatMinutes(durationMinutes)} '
          'of tracking at current rate.';
    }

    if (confidence < 0.5) {
      return 'Battery at $currentLevel%. Gathering more data for accurate estimation.';
    }

    return 'Battery sufficient for 4+ hours of tracking.';
  }

  static String _formatMinutes(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
    return '${minutes}m';
  }
}
