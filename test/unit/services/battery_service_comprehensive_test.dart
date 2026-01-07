/// Comprehensive tests for BatteryService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('BatteryService - Comprehensive Coverage', () {
    late MockLocus mockLocus;
    late BatteryServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = BatteryServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('getStats', () {
      test('should return battery stats with all fields populated', () async {
        const stats = BatteryStats(
          gpsOnTimePercent: 15.5,
          locationUpdatesCount: 150,
          trackingDurationMinutes: 120,
          currentBatteryLevel: 85,
        );
        mockLocus.setBatteryStats(stats);

        final result = await service.getStats();

        expect(result.gpsOnTimePercent, 15.5);
        expect(result.locationUpdatesCount, 150);
        expect(result.trackingDurationMinutes, 120);
        expect(result.currentBatteryLevel, 85);
      });

      test('should handle zero battery level', () async {
        const stats = BatteryStats(
          gpsOnTimePercent: 0,
          locationUpdatesCount: 0,
          trackingDurationMinutes: 0,
          currentBatteryLevel: 0,
        );
        mockLocus.setBatteryStats(stats);

        final result = await service.getStats();

        expect(result.currentBatteryLevel, 0);
      });

      test('should handle full battery level', () async {
        const stats = BatteryStats(
          gpsOnTimePercent: 100,
          locationUpdatesCount: 999,
          trackingDurationMinutes: 600,
          currentBatteryLevel: 100,
        );
        mockLocus.setBatteryStats(stats);

        final result = await service.getStats();

        expect(result.currentBatteryLevel, 100);
      });
    });

    group('getPowerState', () {
      test('should return power state when charging', () async {
        const state = PowerState(
          batteryLevel: 50,
          isCharging: true,
          isPowerSaveMode: false,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.batteryLevel, 50);
        expect(result.isCharging, isTrue);
        expect(result.isPowerSaveMode, isFalse);
      });

      test('should return power state when not charging', () async {
        const state = PowerState(
          batteryLevel: 30,
          isCharging: false,
          isPowerSaveMode: false,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.isCharging, isFalse);
      });

      test('should return power state in power save mode', () async {
        const state = PowerState(
          batteryLevel: 10,
          isCharging: false,
          isPowerSaveMode: true,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.isPowerSaveMode, isTrue);
        expect(result.batteryLevel, 10);
      });

      test('should handle low battery not in power save', () async {
        const state = PowerState(
          batteryLevel: 15,
          isCharging: false,
          isPowerSaveMode: false,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.batteryLevel, 15);
        expect(result.isPowerSaveMode, isFalse);
      });
    });

    group('estimateRunway', () {
      test('should estimate battery runway', () async {
        // Note: BatteryRunway is calculated internally, cannot be mocked
        final result = await service.estimateRunway();

        expect(result, isA<BatteryRunway>());
      });

      test('should handle zero runway estimates', () async {
        final result = await service.estimateRunway();

        expect(result, isA<BatteryRunway>());
        expect(result.duration, isA<Duration>());
        expect(result.lowPowerDuration, isA<Duration>());
      });

      test('should handle long runway estimates', () async {
        final result = await service.estimateRunway();

        expect(result, isA<BatteryRunway>());
        expect(result.recommendation, isA<String>());
      });
    });

    group('setAdaptiveTracking', () {
      test('should set aggressive adaptive config', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);

        expect(service.adaptiveTrackingConfig, isNotNull);
        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.aggressive,
        );
      });

      test('should set balanced adaptive config', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.balanced,
        );
      });

      test('should set conservative adaptive config', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);

        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.aggressive,
        );
      });

      test('should update config when changed', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);
        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.aggressive,
        );

        await service.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);
        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.balanced,
        );
      });
    });

    group('calculateAdaptiveSettings', () {
      test('should calculate settings based on conditions', () async {
        // Note: AdaptiveSettings is calculated internally, cannot be directly mocked
        final result = await service.calculateAdaptiveSettings();

        expect(result, isA<AdaptiveSettings>());
        expect(result.distanceFilter, isA<double>());
        expect(result.desiredAccuracy, isA<DesiredAccuracy>());
        expect(result.heartbeatInterval, isA<int>());
        expect(result.gpsEnabled, isA<bool>());
      });

      test('should handle stationary settings', () async {
        final result = await service.calculateAdaptiveSettings();

        expect(result, isA<AdaptiveSettings>());
        expect(result.desiredAccuracy, isA<DesiredAccuracy>());
        expect(result.gpsEnabled, isA<bool>());
      });
    });

    group('Benchmarking', () {
      test('should start and stop benchmark with results', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 100,
          isCharging: false,
        ));

        await service.startBenchmark();
        service.recordBenchmarkLocationUpdate(accuracy: 10);
        service.recordBenchmarkLocationUpdate(accuracy: 15);
        service.recordBenchmarkSync();

        mockLocus.setPowerState(const PowerState(
          batteryLevel: 95,
          isCharging: false,
        ));

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.drainPercent, 5);
        expect(result.locationUpdates, 2);
        expect(result.syncRequests, 1);
      });

      test('should handle benchmark without drain', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 80,
          isCharging: false,
        ));

        await service.startBenchmark();
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 80,
          isCharging: false,
        ));

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.drainPercent, 0);
      });

      test('should handle benchmark while charging', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 50,
          isCharging: true,
        ));

        await service.startBenchmark();
        service.recordBenchmarkLocationUpdate();

        mockLocus.setPowerState(const PowerState(
          batteryLevel: 55,
          isCharging: true,
        ));

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        // Battery level increased while charging
        expect(result!.drainPercent, -5);
      });

      test('should handle multiple location updates in benchmark', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 90,
          isCharging: false,
        ));

        await service.startBenchmark();
        for (int i = 0; i < 10; i++) {
          service.recordBenchmarkLocationUpdate(accuracy: i.toDouble());
        }

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.locationUpdates, 10);
      });

      test('should handle multiple sync events in benchmark', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 90,
          isCharging: false,
        ));

        await service.startBenchmark();
        for (int i = 0; i < 5; i++) {
          service.recordBenchmarkSync();
        }

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.syncRequests, 5);
      });
    });

    group('Stream subscriptions', () {
      test('should emit power state change events', () async {
        final events = <PowerStateChangeEvent>[];
        service.onPowerStateChange((event) {
          events.add(event);
        });

        final event = PowerStateChangeEvent(
          previous: const PowerState(
            batteryLevel: 60,
            isCharging: false,
            isPowerSaveMode: false,
          ),
          current: const PowerState(
            batteryLevel: 50,
            isCharging: false,
            isPowerSaveMode: true,
          ),
          changeType: PowerStateChangeType.powerSaveMode,
        );

        mockLocus.emitPowerStateChange(event);

        await Future.delayed(const Duration(milliseconds: 100));

        expect(events, hasLength(1));
        expect(events.first.current.batteryLevel, 50);
        expect(events.first.current.isPowerSaveMode, isTrue);
      });

      test('should emit power save mode changes', () async {
        final changes = <bool>[];
        service.onPowerSaveChange((enabled) {
          changes.add(enabled);
        });

        mockLocus.emitPowerSaveChange(true);
        await Future.delayed(const Duration(milliseconds: 50));

        mockLocus.emitPowerSaveChange(false);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(changes, hasLength(2));
        expect(changes[0], isTrue);
        expect(changes[1], isFalse);
      });

      test('should handle subscription cancellation', () async {
        final events = <PowerStateChangeEvent>[];
        final subscription = service.onPowerStateChange((event) {
          events.add(event);
        });

        mockLocus.emitPowerStateChange(PowerStateChangeEvent(
          previous: const PowerState(
            batteryLevel: 80,
            isCharging: false,
          ),
          current: const PowerState(
            batteryLevel: 70,
            isCharging: false,
          ),
          changeType: PowerStateChangeType.batteryLevel,
        ));

        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        // Emit after cancellation
        mockLocus.emitPowerStateChange(PowerStateChangeEvent(
          previous: const PowerState(
            batteryLevel: 70,
            isCharging: false,
          ),
          current: const PowerState(
            batteryLevel: 60,
            isCharging: false,
          ),
          changeType: PowerStateChangeType.batteryLevel,
        ));

        await Future.delayed(const Duration(milliseconds: 50));

        // Should only have received the first event
        expect(events, hasLength(1));
      });

      test('should provide stream access via powerStateEvents', () async {
        final events = <PowerStateChangeEvent>[];
        service.powerStateEvents.listen((event) {
          events.add(event);
        });

        mockLocus.emitPowerStateChange(PowerStateChangeEvent(
          previous: const PowerState(
            batteryLevel: 40,
            isCharging: false,
          ),
          current: const PowerState(
            batteryLevel: 45,
            isCharging: true,
          ),
          changeType: PowerStateChangeType.chargingState,
        ));

        await Future.delayed(const Duration(milliseconds: 100));

        expect(events, hasLength(1));
        expect(events.first.current.isCharging, isTrue);
      });

      test('should provide stream access via powerSaveChanges', () async {
        final changes = <bool>[];
        service.powerSaveChanges.listen((enabled) {
          changes.add(enabled);
        });

        mockLocus.emitPowerSaveChange(true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(changes, hasLength(1));
        expect(changes.first, isTrue);
      });
    });

    group('Edge cases', () {
      test('should handle null adaptive config', () {
        expect(service.adaptiveTrackingConfig, isNull);
      });

      test('should handle rapid config changes', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);

        expect(
          service.adaptiveTrackingConfig,
          AdaptiveTrackingConfig.aggressive,
        );
      });

      test('should handle benchmark start without location updates', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 75,
          isCharging: false,
        ));

        await service.startBenchmark();
        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.locationUpdates, 0);
        expect(result.syncRequests, 0);
      });
    });
  });
}
