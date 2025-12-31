/// Power state monitoring for battery-aware behavior.
///
/// Tracks device power state changes and provides events for
/// optimizing tracking behavior based on power conditions.
library;

import 'package:locus/src/models/common/json_map.dart';

/// Current power state of the device.
///
/// Used to make intelligent decisions about tracking behavior
/// based on battery level, charging state, and power save mode.
class PowerState {
  /// Current battery level (0-100).
  final int batteryLevel;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Type of charging connection.
  final ChargingType chargingType;

  /// Whether the device is in power save / low power mode.
  final bool isPowerSaveMode;

  /// Whether the device is in Doze mode (Android).
  final bool isDozeMode;

  /// Whether app is exempt from battery optimizations.
  final bool isBatteryOptimizationExempt;

  /// Estimated time to full charge (if charging).
  final Duration? timeToFullCharge;

  /// Estimated battery time remaining (if discharging).
  final Duration? timeRemaining;

  /// Creates a power state.
  const PowerState({
    required this.batteryLevel,
    required this.isCharging,
    this.chargingType = ChargingType.none,
    this.isPowerSaveMode = false,
    this.isDozeMode = false,
    this.isBatteryOptimizationExempt = false,
    this.timeToFullCharge,
    this.timeRemaining,
  });

  /// Default state when power info is unavailable.
  static const PowerState unknown = PowerState(
    batteryLevel: 50,
    isCharging: false,
    chargingType: ChargingType.none,
  );

  /// Whether battery is low (below 20%).
  bool get isLowBattery => batteryLevel < 20;

  /// Whether battery is critical (below 10%).
  bool get isCriticalBattery => batteryLevel < 10;

  /// Whether tracking should be restricted due to power state.
  ///
  /// Returns true if:
  /// - Battery is critical and not charging
  /// - Device is in Doze mode and not exempt
  /// - Power save mode is active
  bool get shouldRestrictTracking {
    if (isCharging) return false;
    if (isCriticalBattery) return true;
    if (isDozeMode && !isBatteryOptimizationExempt) return true;
    return isPowerSaveMode;
  }

  /// Suggested optimization level based on power state.
  PowerOptimizationSuggestion get optimizationSuggestion {
    if (isCharging) {
      return const PowerOptimizationSuggestion(
        level: OptimizationSuggestionLevel.none,
        reason: 'Device is charging',
        canUseHighAccuracy: true,
        canUseCellular: true,
        suggestedHeartbeatMultiplier: 1.0,
      );
    }

    if (isCriticalBattery) {
      return const PowerOptimizationSuggestion(
        level: OptimizationSuggestionLevel.maximum,
        reason: 'Critical battery level',
        canUseHighAccuracy: false,
        canUseCellular: false,
        suggestedHeartbeatMultiplier: 5.0,
      );
    }

    if (isPowerSaveMode || isDozeMode) {
      return const PowerOptimizationSuggestion(
        level: OptimizationSuggestionLevel.high,
        reason: 'Power save mode active',
        canUseHighAccuracy: false,
        canUseCellular: true,
        suggestedHeartbeatMultiplier: 3.0,
      );
    }

    if (isLowBattery) {
      return const PowerOptimizationSuggestion(
        level: OptimizationSuggestionLevel.moderate,
        reason: 'Low battery level',
        canUseHighAccuracy: true,
        canUseCellular: true,
        suggestedHeartbeatMultiplier: 2.0,
      );
    }

    return const PowerOptimizationSuggestion(
      level: OptimizationSuggestionLevel.none,
      reason: 'Normal battery level',
      canUseHighAccuracy: true,
      canUseCellular: true,
      suggestedHeartbeatMultiplier: 1.0,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'chargingType': chargingType.name,
        'isPowerSaveMode': isPowerSaveMode,
        'isDozeMode': isDozeMode,
        'isBatteryOptimizationExempt': isBatteryOptimizationExempt,
        if (timeToFullCharge != null)
          'timeToFullChargeSeconds': timeToFullCharge!.inSeconds,
        if (timeRemaining != null)
          'timeRemainingSeconds': timeRemaining!.inSeconds,
      };

  /// Creates from a map.
  factory PowerState.fromMap(JsonMap map) {
    return PowerState(
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? 50,
      isCharging: map['isCharging'] as bool? ?? false,
      chargingType: ChargingType.values.firstWhere(
        (e) => e.name == map['chargingType'],
        orElse: () => ChargingType.none,
      ),
      isPowerSaveMode: map['isPowerSaveMode'] as bool? ?? false,
      isDozeMode: map['isDozeMode'] as bool? ?? false,
      isBatteryOptimizationExempt:
          map['isBatteryOptimizationExempt'] as bool? ?? false,
      timeToFullCharge: map['timeToFullChargeSeconds'] != null
          ? Duration(seconds: (map['timeToFullChargeSeconds'] as num).toInt())
          : null,
      timeRemaining: map['timeRemainingSeconds'] != null
          ? Duration(seconds: (map['timeRemainingSeconds'] as num).toInt())
          : null,
    );
  }

  @override
  String toString() {
    return 'PowerState(battery: $batteryLevel%, '
        'charging: $isCharging ($chargingType), '
        'powerSave: $isPowerSaveMode, '
        'doze: $isDozeMode)';
  }
}

/// Type of charging connection.
enum ChargingType {
  /// Not charging.
  none,

  /// USB charging (typically slower).
  usb,

  /// AC wall adapter charging.
  ac,

  /// Wireless/Qi charging.
  wireless,

  /// Unknown charging type.
  unknown,
}

/// Power state change event.
///
/// Emitted when the device's power state changes significantly.
class PowerStateChangeEvent {
  /// Previous power state.
  final PowerState previous;

  /// Current power state.
  final PowerState current;

  /// What changed.
  final PowerStateChangeType changeType;

  /// Timestamp of the change.
  final DateTime timestamp;

  /// Creates a power state change event.
  PowerStateChangeEvent({
    required this.previous,
    required this.current,
    required this.changeType,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates from a map.
  factory PowerStateChangeEvent.fromMap(JsonMap map) {
    final previousData = map['previous'];
    final currentData = map['current'];

    return PowerStateChangeEvent(
      previous: previousData is Map
          ? PowerState.fromMap(Map<String, dynamic>.from(previousData))
          : PowerState.unknown,
      current: currentData is Map
          ? PowerState.fromMap(Map<String, dynamic>.from(currentData))
          : PowerState.unknown,
      changeType: PowerStateChangeType.values.firstWhere(
        (e) => e.name == map['changeType'],
        orElse: () => PowerStateChangeType.batteryLevel,
      ),
      timestamp: map['timestamp'] is String
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'previous': previous.toMap(),
        'current': current.toMap(),
        'changeType': changeType.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Types of power state changes.
enum PowerStateChangeType {
  /// Battery level changed.
  batteryLevel,

  /// Charging state changed (plugged/unplugged).
  chargingState,

  /// Power save mode toggled.
  powerSaveMode,

  /// Doze mode entered/exited.
  dozeMode,

  /// Battery optimization exemption changed.
  batteryOptimization,
}

/// Suggested optimization based on power state analysis.
class PowerOptimizationSuggestion {
  /// Suggested optimization level.
  final OptimizationSuggestionLevel level;

  /// Reason for this suggestion.
  final String reason;

  /// Whether high accuracy GPS is recommended.
  final bool canUseHighAccuracy;

  /// Whether cellular sync is recommended.
  final bool canUseCellular;

  /// Multiplier for heartbeat interval.
  ///
  /// 1.0 = normal, 2.0 = double interval, etc.
  final double suggestedHeartbeatMultiplier;

  /// Creates an optimization suggestion.
  const PowerOptimizationSuggestion({
    required this.level,
    required this.reason,
    required this.canUseHighAccuracy,
    required this.canUseCellular,
    required this.suggestedHeartbeatMultiplier,
  });

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'level': level.name,
        'reason': reason,
        'canUseHighAccuracy': canUseHighAccuracy,
        'canUseCellular': canUseCellular,
        'suggestedHeartbeatMultiplier': suggestedHeartbeatMultiplier,
      };
}

/// Optimization suggestion levels.
enum OptimizationSuggestionLevel {
  /// No optimization needed.
  none,

  /// Light optimization.
  light,

  /// Moderate optimization.
  moderate,

  /// High optimization.
  high,

  /// Maximum optimization (survival mode).
  maximum,
}
