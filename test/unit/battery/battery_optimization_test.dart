import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('SyncPolicy', () {
    test('balanced preset behaviors', () {
      const policy = SyncPolicy.balanced;

      expect(policy.onWifi, SyncBehavior.immediate);
      expect(policy.onCellular, SyncBehavior.batch);
      expect(policy.onMetered, SyncBehavior.batch);
      expect(policy.onOffline, SyncBehavior.queue);
      expect(policy.batchSize, 20);
    });

    test('getBehavior returns immediate when charging', () {
      const policy = SyncPolicy.balanced;
      final behavior = policy.getBehavior(
        networkType: NetworkType.cellular,
        batteryPercent: 50,
        isCharging: true,
        isMetered: false,
        isForeground: true,
      );
      expect(behavior, SyncBehavior.immediate);
    });

    test('getBehavior applies low battery override', () {
      const policy = SyncPolicy(lowBatteryThreshold: 20);
      final behavior = policy.getBehavior(
        networkType: NetworkType.wifi,
        batteryPercent: 15,
        isCharging: false,
        isMetered: false,
        isForeground: true,
      );
      expect(behavior, SyncBehavior.manual);
    });

    test('getBehavior returns queue when offline', () {
      const policy = SyncPolicy.balanced;
      final behavior = policy.getBehavior(
        networkType: NetworkType.none,
        batteryPercent: 100,
        isCharging: true,
        isMetered: false,
        isForeground: true,
      );
      expect(behavior, SyncBehavior.queue);
    });

    test('foregroundOnly restricts background sync', () {
      const policy = SyncPolicy(foregroundOnly: true);
      final behavior = policy.getBehavior(
        networkType: NetworkType.wifi,
        batteryPercent: 100,
        isCharging: false,
        isMetered: false,
        isForeground: false,
      );
      expect(behavior, SyncBehavior.queue);
    });

    test('serialization round-trip preserves values', () {
      const policy = SyncPolicy(
        onWifi: SyncBehavior.batch,
        onCellular: SyncBehavior.queue,
        batchSize: 75,
        batchInterval: Duration(minutes: 10),
        lowBatteryThreshold: 25,
        preferWifi: false,
      );

      final map = policy.toMap();
      final restored = SyncPolicy.fromMap(map);

      expect(restored.onWifi, SyncBehavior.batch);
      expect(restored.onCellular, SyncBehavior.queue);
      expect(restored.batchSize, 75);
      expect(restored.batchInterval.inMinutes, 10);
      expect(restored.lowBatteryThreshold, 25);
      expect(restored.preferWifi, false);
    });
  });

  group('SyncDecision', () {
    test('proceed is truthy', () {
      expect(SyncDecision.proceed.shouldSync, true);
    });

    test('defer creates non-sync decision', () {
      final decision = SyncDecision.defer('No network');
      expect(decision.shouldSync, false);
      expect(decision.reason, 'No network');
    });

    test('batch includes size and delay', () {
      final decision = SyncDecision.batch(
        50,
        delay: const Duration(minutes: 5),
      );
      expect(decision.shouldSync, true);
      expect(decision.batchLimit, 50);
      expect(decision.delay?.inMinutes, 5);
    });
  });

  group('AdaptiveTrackingConfig', () {
    test('balanced preset has expected defaults', () {
      const config = AdaptiveTrackingConfig.balanced;
      expect(config.enabled, true);
      expect(config.activityOptimization, true);
      expect(config.stationaryGpsOff, true);
    });

    test('calculateSettings returns GPS off when stationary', () {
      const config = AdaptiveTrackingConfig(
        enabled: true,
        stationaryGpsOff: true,
      );

      final settings = config.calculateSettings(
        speedMps: 0,
        batteryPercent: 50,
        isCharging: false,
        isMoving: false,
        activity: ActivityType.still,
        isInGeofence: false,
      );

      expect(settings.gpsEnabled, false);
      expect(settings.reason.contains('Stationary'), true);
    });

    test('calculateSettings uses high performance when charging', () {
      const config = AdaptiveTrackingConfig.balanced;

      final settings = config.calculateSettings(
        speedMps: 0,
        batteryPercent: 10,
        isCharging: true,
        isMoving: false,
        activity: ActivityType.still,
        isInGeofence: false,
      );

      expect(settings.desiredAccuracy, DesiredAccuracy.high);
      expect(settings.gpsEnabled, true);
      expect(settings.reason.contains('Charging'), true);
    });

    test('calculateSettings returns minimal tracking on critical battery', () {
      const config = AdaptiveTrackingConfig.balanced;

      final settings = config.calculateSettings(
        speedMps: 20,
        batteryPercent: 5,
        isCharging: false,
        isMoving: true,
        activity: ActivityType.inVehicle,
        isInGeofence: false,
      );

      expect(settings.desiredAccuracy, DesiredAccuracy.low);
      expect(settings.gpsEnabled, false);
      expect(settings.reason.contains('Critical'), true);
    });

    test('serialization round-trip preserves values', () {
      const config = AdaptiveTrackingConfig(
        enabled: true,
        activityOptimization: false,
        stationaryDelay: Duration(seconds: 45),
        minAccuracyMeters: 200,
      );

      final map = config.toMap();
      final restored = AdaptiveTrackingConfig.fromMap(map);

      expect(restored.enabled, true);
      expect(restored.activityOptimization, false);
      expect(restored.stationaryDelay.inSeconds, 45);
      expect(restored.minAccuracyMeters, 200);
    });
  });

  group('SpeedTiers', () {
    test('getTier returns correct tier for speed', () {
      const tiers = SpeedTiers();

      expect(tiers.getTier(0).name, 'stationary');
      expect(tiers.getTier(3).name, 'walking');
      expect(tiers.getTier(15).name, 'city');
      expect(tiers.getTier(50).name, 'suburban');
      expect(tiers.getTier(100).name, 'highway');
    });

    test('conservative tiers have longer intervals', () {
      const conservative = SpeedTiers.conservative;
      const balanced = SpeedTiers.balanced;

      expect(
        conservative.stationary.updateInterval,
        greaterThan(balanced.stationary.updateInterval),
      );
    });
  });

  group('BatteryThresholds', () {
    test('getLevel returns correct category', () {
      const thresholds = BatteryThresholds(
        lowThreshold: 20,
        criticalThreshold: 10,
      );

      expect(thresholds.getLevel(50), BatteryLevel.normal);
      expect(thresholds.getLevel(15), BatteryLevel.low);
      expect(thresholds.getLevel(5), BatteryLevel.critical);
    });
  });

  group('PowerState', () {
    test('isLowBattery is true below 20%', () {
      const state = PowerState(batteryLevel: 15, isCharging: false);
      expect(state.isLowBattery, true);
    });

    test('isCriticalBattery is true below 10%', () {
      const state = PowerState(batteryLevel: 8, isCharging: false);
      expect(state.isCriticalBattery, true);
    });

    test('shouldRestrictTracking when critical and not charging', () {
      const state = PowerState(batteryLevel: 5, isCharging: false);
      expect(state.shouldRestrictTracking, true);
    });

    test('shouldRestrictTracking false when charging', () {
      const state = PowerState(batteryLevel: 5, isCharging: true);
      expect(state.shouldRestrictTracking, false);
    });

    test('shouldRestrictTracking when in power save mode', () {
      const state = PowerState(
        batteryLevel: 50,
        isCharging: false,
        isPowerSaveMode: true,
      );
      expect(state.shouldRestrictTracking, true);
    });

    test('optimizationSuggestion reflects battery state', () {
      const normal = PowerState(batteryLevel: 80, isCharging: false);
      expect(normal.optimizationSuggestion.level,
          OptimizationSuggestionLevel.none);

      const low = PowerState(batteryLevel: 15, isCharging: false);
      expect(low.optimizationSuggestion.level,
          OptimizationSuggestionLevel.moderate);

      const critical = PowerState(batteryLevel: 5, isCharging: false);
      expect(critical.optimizationSuggestion.level,
          OptimizationSuggestionLevel.maximum);
    });

    test('serialization round-trip preserves values', () {
      const state = PowerState(
        batteryLevel: 45,
        isCharging: true,
        chargingType: ChargingType.usb,
        isPowerSaveMode: true,
        isDozeMode: true,
      );

      final map = state.toMap();
      final restored = PowerState.fromMap(map);

      expect(restored.batteryLevel, 45);
      expect(restored.isCharging, true);
      expect(restored.chargingType, ChargingType.usb);
      expect(restored.isPowerSaveMode, true);
      expect(restored.isDozeMode, true);
    });

    test('charging device suggests no optimization', () {
      const state = PowerState(
        batteryLevel: 20,
        isCharging: true,
      );
      expect(state.optimizationSuggestion.level,
          equals(OptimizationSuggestionLevel.none));
      expect(state.optimizationSuggestion.canUseHighAccuracy, isTrue);
    });

    test('critical battery suggests maximum optimization and no high accuracy',
        () {
      const state = PowerState(
        batteryLevel: 5,
        isCharging: false,
      );
      expect(state.optimizationSuggestion.level,
          equals(OptimizationSuggestionLevel.maximum));
      expect(state.optimizationSuggestion.canUseHighAccuracy, isFalse);
    });

    test('power save mode suggests high optimization', () {
      const state = PowerState(
        batteryLevel: 50,
        isCharging: false,
        isPowerSaveMode: true,
      );
      expect(state.optimizationSuggestion.level,
          equals(OptimizationSuggestionLevel.high));
    });
  });

  group('BatteryStats', () {
    test('estimatedDrainPerHour calculates correctly', () {
      const stats = BatteryStats(
        estimatedDrainPercent: 10,
        trackingDurationMinutes: 60,
      );
      expect(stats.estimatedDrainPerHour, 10);
    });

    test('averageUpdateIntervalSeconds calculates correctly', () {
      const stats = BatteryStats(
        locationUpdatesCount: 61,
        trackingDurationMinutes: 10,
      );
      // 600 seconds / 60 intervals = 10 seconds
      expect(stats.averageUpdateIntervalSeconds, 10);
    });

    test('empty constructor creates zero values', () {
      const stats = BatteryStats.empty();
      expect(stats.gpsOnTimePercent, 0);
      expect(stats.locationUpdatesCount, 0);
      expect(stats.estimatedDrainPercent, null);
    });
  });

  group('BatteryBenchmark', () {
    test('tracks location updates', () {
      final benchmark = BatteryBenchmark();
      benchmark.start(initialBattery: 100);

      benchmark.recordLocationUpdate(accuracy: 10);
      benchmark.recordLocationUpdate(accuracy: 20);
      benchmark.recordSync();

      final result = benchmark.finish(currentBattery: 95);

      expect(result.locationUpdates, 2);
      expect(result.syncRequests, 1);
      expect(result.drainPercent, 5);
      expect(result.averageAccuracy, 15);
    });

    test('throws when not started', () {
      final benchmark = BatteryBenchmark();
      expect(
        () => benchmark.finish(currentBattery: 90),
        throwsStateError,
      );
    });

    test('tracks state changes', () {
      final benchmark = BatteryBenchmark();
      benchmark.start(initialBattery: 100);

      benchmark.recordStateChange('moving');
      // Simulate time passing would be needed for duration tracking
      benchmark.recordStateChange('stationary');

      final result = benchmark.finish(currentBattery: 100);
      expect(result.timeByState.keys, contains('moving'));
    });
  });
}
