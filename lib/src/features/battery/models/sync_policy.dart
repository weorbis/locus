/// Sync policy configuration for network-aware HTTP synchronization.
///
/// Allows fine-grained control over when and how location data is
/// synchronized to reduce battery consumption from network operations.
library;

import 'package:locus/src/shared/models/json_map.dart';

/// Network-aware sync policy configuration.
///
/// Control when and how location batches are synchronized based on
/// network type, battery state, and app state.
///
/// Example:
/// ```dart
/// final config = Config(
///   syncPolicy: SyncPolicy(
///     onWifi: SyncBehavior.immediate,
///     onCellular: SyncBehavior.batch,
///     onMetered: SyncBehavior.manual,
///     batchSize: 50,
///     batchInterval: Duration(minutes: 5),
///     lowBatteryThreshold: 20,
///     lowBatteryBehavior: SyncBehavior.manual,
///   ),
/// );
/// ```
class SyncPolicy {
  /// Sync behavior when connected to WiFi.
  final SyncBehavior onWifi;

  /// Sync behavior when on cellular data.
  final SyncBehavior onCellular;

  /// Sync behavior when on a metered connection.
  ///
  /// A metered connection is one where data usage is limited or charged.
  final SyncBehavior onMetered;

  /// Sync behavior when device is offline.
  ///
  /// Typically [SyncBehavior.queue] to store until connection returns.
  final SyncBehavior onOffline;

  /// Sync behavior when charging.
  ///
  /// When charging, power isn't as critical so can sync more aggressively.
  final SyncBehavior onCharging;

  /// Maximum number of locations per batch.
  final int batchSize;

  /// Time interval between automatic batch syncs.
  ///
  /// Used with [SyncBehavior.batch].
  final Duration batchInterval;

  /// Battery percentage below which to apply [lowBatteryBehavior].
  final int lowBatteryThreshold;

  /// Sync behavior when battery is below [lowBatteryThreshold].
  final SyncBehavior lowBatteryBehavior;

  /// Minimum time between sync attempts.
  ///
  /// Prevents excessive sync attempts that drain battery.
  final Duration minSyncInterval;

  /// Maximum age of a location before it must be synced.
  ///
  /// Forces sync of old locations even in manual mode.
  final Duration? maxLocationAge;

  /// Whether to prefer WiFi over cellular even if cellular is faster.
  final bool preferWifi;

  /// Whether to sync only when app is in foreground.
  final bool foregroundOnly;

  /// Creates a sync policy.
  const SyncPolicy({
    this.onWifi = SyncBehavior.immediate,
    this.onCellular = SyncBehavior.batch,
    this.onMetered = SyncBehavior.batch,
    this.onOffline = SyncBehavior.queue,
    this.onCharging = SyncBehavior.immediate,
    this.batchSize = 50,
    this.batchInterval = const Duration(minutes: 5),
    this.lowBatteryThreshold = 20,
    this.lowBatteryBehavior = SyncBehavior.manual,
    this.minSyncInterval = const Duration(seconds: 30),
    this.maxLocationAge,
    this.preferWifi = true,
    this.foregroundOnly = false,
  });

  /// Aggressive sync - always sync immediately.
  ///
  /// Most reliable delivery but highest battery usage.
  static const SyncPolicy aggressive = SyncPolicy(
    onWifi: SyncBehavior.immediate,
    onCellular: SyncBehavior.immediate,
    onMetered: SyncBehavior.immediate,
    onOffline: SyncBehavior.queue,
    batchSize: 1,
    minSyncInterval: Duration.zero,
    lowBatteryThreshold: 0,
  );

  /// Balanced sync - batch on cellular, immediate on WiFi.
  ///
  /// Good balance between reliability and battery life.
  static const SyncPolicy balanced = SyncPolicy(
    onWifi: SyncBehavior.immediate,
    onCellular: SyncBehavior.batch,
    onMetered: SyncBehavior.batch,
    onOffline: SyncBehavior.queue,
    batchSize: 20,
    batchInterval: Duration(minutes: 2),
    lowBatteryThreshold: 20,
    lowBatteryBehavior: SyncBehavior.batch,
  );

  /// Conservative sync - batch everywhere, skip on metered.
  ///
  /// Minimizes battery and data usage.
  static const SyncPolicy conservative = SyncPolicy(
    onWifi: SyncBehavior.batch,
    onCellular: SyncBehavior.batch,
    onMetered: SyncBehavior.manual,
    onOffline: SyncBehavior.queue,
    batchSize: 50,
    batchInterval: Duration(minutes: 10),
    lowBatteryThreshold: 30,
    lowBatteryBehavior: SyncBehavior.manual,
  );

  /// Ultra-conservative - only sync on WiFi when charging.
  ///
  /// Maximum battery savings, suitable for non-urgent data.
  static const SyncPolicy minimal = SyncPolicy(
    onWifi: SyncBehavior.batch,
    onCellular: SyncBehavior.queue,
    onMetered: SyncBehavior.queue,
    onOffline: SyncBehavior.queue,
    onCharging: SyncBehavior.immediate,
    batchSize: 100,
    batchInterval: Duration(minutes: 30),
    lowBatteryThreshold: 50,
    lowBatteryBehavior: SyncBehavior.queue,
    foregroundOnly: true,
  );

  /// Determines the sync behavior based on current state.
  SyncBehavior getBehavior({
    required NetworkType networkType,
    required int batteryPercent,
    required bool isCharging,
    required bool isMetered,
    required bool isForeground,
  }) {
    // Foreground-only mode
    if (foregroundOnly && !isForeground) {
      return SyncBehavior.queue;
    }

    // Low battery override
    if (batteryPercent < lowBatteryThreshold && !isCharging) {
      return lowBatteryBehavior;
    }

    // Charging overrides network-based behavior
    if (isCharging) {
      // Still respect offline state
      if (networkType == NetworkType.none) {
        return onOffline;
      }
      return onCharging;
    }

    // Network type based behavior
    switch (networkType) {
      case NetworkType.wifi:
        return onWifi;
      case NetworkType.cellular:
        return isMetered ? onMetered : onCellular;
      case NetworkType.ethernet:
        return onWifi; // Treat ethernet like WiFi
      case NetworkType.none:
        return onOffline;
    }
  }

  /// Creates a copy with the given fields replaced.
  SyncPolicy copyWith({
    SyncBehavior? onWifi,
    SyncBehavior? onCellular,
    SyncBehavior? onMetered,
    SyncBehavior? onOffline,
    SyncBehavior? onCharging,
    int? batchSize,
    Duration? batchInterval,
    int? lowBatteryThreshold,
    SyncBehavior? lowBatteryBehavior,
    Duration? minSyncInterval,
    Duration? maxLocationAge,
    bool? preferWifi,
    bool? foregroundOnly,
  }) {
    return SyncPolicy(
      onWifi: onWifi ?? this.onWifi,
      onCellular: onCellular ?? this.onCellular,
      onMetered: onMetered ?? this.onMetered,
      onOffline: onOffline ?? this.onOffline,
      onCharging: onCharging ?? this.onCharging,
      batchSize: batchSize ?? this.batchSize,
      batchInterval: batchInterval ?? this.batchInterval,
      lowBatteryThreshold: lowBatteryThreshold ?? this.lowBatteryThreshold,
      lowBatteryBehavior: lowBatteryBehavior ?? this.lowBatteryBehavior,
      minSyncInterval: minSyncInterval ?? this.minSyncInterval,
      maxLocationAge: maxLocationAge ?? this.maxLocationAge,
      preferWifi: preferWifi ?? this.preferWifi,
      foregroundOnly: foregroundOnly ?? this.foregroundOnly,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'onWifi': onWifi.name,
        'onCellular': onCellular.name,
        'onMetered': onMetered.name,
        'onOffline': onOffline.name,
        'onCharging': onCharging.name,
        'batchSize': batchSize,
        'batchIntervalMs': batchInterval.inMilliseconds,
        'lowBatteryThreshold': lowBatteryThreshold,
        'lowBatteryBehavior': lowBatteryBehavior.name,
        'minSyncIntervalMs': minSyncInterval.inMilliseconds,
        if (maxLocationAge != null)
          'maxLocationAgeMs': maxLocationAge!.inMilliseconds,
        'preferWifi': preferWifi,
        'foregroundOnly': foregroundOnly,
      };

  /// Creates from a map.
  factory SyncPolicy.fromMap(JsonMap map) {
    return SyncPolicy(
      onWifi: SyncBehavior.values.firstWhere(
        (e) => e.name == map['onWifi'],
        orElse: () => SyncBehavior.immediate,
      ),
      onCellular: SyncBehavior.values.firstWhere(
        (e) => e.name == map['onCellular'],
        orElse: () => SyncBehavior.batch,
      ),
      onMetered: SyncBehavior.values.firstWhere(
        (e) => e.name == map['onMetered'],
        orElse: () => SyncBehavior.batch,
      ),
      onOffline: SyncBehavior.values.firstWhere(
        (e) => e.name == map['onOffline'],
        orElse: () => SyncBehavior.queue,
      ),
      onCharging: SyncBehavior.values.firstWhere(
        (e) => e.name == map['onCharging'],
        orElse: () => SyncBehavior.immediate,
      ),
      batchSize: (map['batchSize'] as num?)?.toInt() ?? 50,
      batchInterval: Duration(
        milliseconds: (map['batchIntervalMs'] as num?)?.toInt() ?? 300000,
      ),
      lowBatteryThreshold: (map['lowBatteryThreshold'] as num?)?.toInt() ?? 20,
      lowBatteryBehavior: SyncBehavior.values.firstWhere(
        (e) => e.name == map['lowBatteryBehavior'],
        orElse: () => SyncBehavior.manual,
      ),
      minSyncInterval: Duration(
        milliseconds: (map['minSyncIntervalMs'] as num?)?.toInt() ?? 30000,
      ),
      maxLocationAge: map['maxLocationAgeMs'] != null
          ? Duration(milliseconds: (map['maxLocationAgeMs'] as num).toInt())
          : null,
      preferWifi: map['preferWifi'] as bool? ?? true,
      foregroundOnly: map['foregroundOnly'] as bool? ?? false,
    );
  }
}

/// Sync behavior options.
enum SyncBehavior {
  /// Sync immediately as locations are received.
  ///
  /// Highest reliability, highest power consumption.
  immediate,

  /// Batch locations and sync at intervals.
  ///
  /// Reduced power consumption, slight delay in delivery.
  batch,

  /// Queue locations for later sync.
  ///
  /// Only syncs when network conditions improve or user triggers.
  queue,

  /// No automatic sync - requires manual [Locus.sync()].
  ///
  /// Maximum control, suitable when battery is critical.
  manual,
}

/// Network connection type.
enum NetworkType {
  /// WiFi connection.
  wifi,

  /// Cellular data connection.
  cellular,

  /// Ethernet/wired connection.
  ethernet,

  /// No network connection.
  none,
}

/// Sync decision result from policy evaluation.
class SyncDecision {
  /// Whether sync should proceed.
  final bool shouldSync;

  /// Reason for the decision.
  final String reason;

  /// Number of locations to sync (if batching).
  final int? batchLimit;

  /// Suggested delay before sync.
  final Duration? delay;

  /// Creates a sync decision.
  const SyncDecision({
    required this.shouldSync,
    required this.reason,
    this.batchLimit,
    this.delay,
  });

  /// Sync should proceed immediately.
  static const SyncDecision proceed = SyncDecision(
    shouldSync: true,
    reason: 'Immediate sync allowed',
  );

  /// Sync should be deferred.
  static SyncDecision defer(String reason, {Duration? delay}) => SyncDecision(
        shouldSync: false,
        reason: reason,
        delay: delay,
      );

  /// Sync with batching.
  static SyncDecision batch(int size, {Duration? delay}) => SyncDecision(
        shouldSync: true,
        reason: 'Batched sync',
        batchLimit: size,
        delay: delay,
      );

  @override
  String toString() => 'SyncDecision(sync: $shouldSync, reason: $reason, '
      'batch: $batchLimit, delay: $delay)';
}
