/// Comprehensive tests for BatteryService API.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('BatteryService', () {
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
      test('should return current battery statistics', () async {
        const stats = BatteryStats(
          gpsOnTimePercent: 15.5,
          locationUpdatesCount: 100,
          trackingDurationMinutes: 120,
          currentBatteryLevel: 85,
        );
        mockLocus.setBatteryStats(stats);

        final result = await service.getStats();

        expect(result.gpsOnTimePercent, 15.5);
        expect(result.locationUpdatesCount, 100);
        expect(result.trackingDurationMinutes, 120);
        expect(result.currentBatteryLevel, 85);
      });

      test('should return empty stats when not tracking', () async {
        mockLocus.setBatteryStats(const BatteryStats.empty());

        final result = await service.getStats();

        expect(result.gpsOnTimePercent, 0.0);
        expect(result.locationUpdatesCount, 0);
      });
    });

    group('getPowerState', () {
      test('should return current power state', () async {
        const state = PowerState(
          batteryLevel: 75,
          isCharging: false,
          isPowerSaveMode: false,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.batteryLevel, 75);
        expect(result.isCharging, isFalse);
        expect(result.isPowerSaveMode, isFalse);
      });

      test('should detect charging state', () async {
        const state = PowerState(
          batteryLevel: 50,
          isCharging: true,
          isPowerSaveMode: false,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.isCharging, isTrue);
      });

      test('should detect power save mode', () async {
        const state = PowerState(
          batteryLevel: 15,
          isCharging: false,
          isPowerSaveMode: true,
        );
        mockLocus.setPowerState(state);

        final result = await service.getPowerState();

        expect(result.isPowerSaveMode, isTrue);
        expect(result.batteryLevel, 15);
      });
    });

    group('estimateRunway', () {
      test('should return charging runway when charging', () async {
        mockLocus.setBatteryStats(const BatteryStats(
          currentBatteryLevel: 50,
          isCharging: true,
          trackingDurationMinutes: 60,
        ));
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 50,
          isCharging: true,
        ));

        final runway = await service.estimateRunway();

        expect(runway.isCharging, isTrue);
        expect(runway.currentLevel, 50);
        expect(runway.recommendation, contains('charging'));
      });

      test('should estimate duration based on drain rate', () async {
        mockLocus.setBatteryStats(const BatteryStats(
          currentBatteryLevel: 80,
          isCharging: false,
          trackingDurationMinutes: 60,
          estimatedDrainPercent: 10.0, // 10% drain in 60 mins
        ));
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 80,
          isCharging: false,
        ));

        final runway = await service.estimateRunway();

        expect(runway.isCharging, isFalse);
        expect(runway.currentLevel, 80);
        expect(runway.duration.inMinutes, greaterThan(0));
      });

      test('should return insufficient data for short tracking', () async {
        mockLocus.setBatteryStats(const BatteryStats(
          currentBatteryLevel: 90,
          trackingDurationMinutes: 2, // Too short
        ));

        final runway = await service.estimateRunway();

        expect(runway.confidence, 0.0);
        expect(runway.recommendation, contains('Insufficient'));
      });
    });

    group('setAdaptiveTracking', () {
      test('should set balanced configuration', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

        expect(mockLocus.methodCalls, contains('setAdaptiveTracking'));
      });

      test('should set aggressive configuration', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.aggressive);

        expect(mockLocus.methodCalls, contains('setAdaptiveTracking'));
      });

      test('should set disabled configuration', () async {
        await service.setAdaptiveTracking(AdaptiveTrackingConfig.disabled);

        expect(mockLocus.methodCalls, contains('setAdaptiveTracking'));
      });
    });

    group('adaptiveTrackingConfig', () {
      test('should return null initially', () {
        final config = service.adaptiveTrackingConfig;

        expect(config, isNull);
      });

      test('should return set configuration', () async {
        await mockLocus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

        final config = service.adaptiveTrackingConfig;

        expect(config, isNotNull);
      });
    });

    group('calculateAdaptiveSettings', () {
      test('should calculate settings based on conditions', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 50,
          isCharging: false,
        ));

        final settings = await service.calculateAdaptiveSettings();

        expect(settings, isA<AdaptiveSettings>());
        expect(settings.gpsEnabled, isTrue);
        expect(settings.distanceFilter, greaterThan(0));
        expect(settings.heartbeatInterval, greaterThan(0));
      });

      test('should disable GPS on critical battery', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 5,
          isCharging: false,
          isPowerSaveMode: true,
        ));
        await mockLocus.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

        final settings = await service.calculateAdaptiveSettings();

        expect(settings.gpsEnabled, isFalse);
        expect(settings.reason, contains('critical'));
      });

      test('should optimize for low battery', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 15,
          isCharging: false,
        ));

        final settings = await service.calculateAdaptiveSettings();

        expect(settings.heartbeatInterval, greaterThan(30));
      });
    });

    group('benchmark', () {
      test('should track battery drain during benchmark', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 80,
          isCharging: false,
        ));

        await service.startBenchmark();

        // Simulate some activity
        service.recordBenchmarkLocationUpdate(accuracy: 10.0);
        service.recordBenchmarkLocationUpdate(accuracy: 15.0);
        service.recordBenchmarkSync();

        // Simulate battery drain
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 75,
          isCharging: false,
        ));

        final result = await service.stopBenchmark();

        expect(result, isNotNull);
        expect(result!.drainPercent, 5);
        expect(result.locationUpdates, 2);
        expect(result.syncRequests, 1);
      });

      test('should return null when no benchmark is running', () async {
        final result = await service.stopBenchmark();

        expect(result, isNull);
      });

      test('should track multiple location updates', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 90,
          isCharging: false,
        ));

        await service.startBenchmark();

        for (var i = 0; i < 10; i++) {
          service.recordBenchmarkLocationUpdate(accuracy: 12.0);
        }

        mockLocus.setPowerState(const PowerState(
          batteryLevel: 88,
          isCharging: false,
        ));
        final result = await service.stopBenchmark();

        expect(result!.locationUpdates, 10);
        expect(result.drainPercent, 2);
      });

      test('should track sync operations', () async {
        mockLocus.setPowerState(const PowerState(
          batteryLevel: 70,
          isCharging: false,
        ));

        await service.startBenchmark();

        for (var i = 0; i < 5; i++) {
          service.recordBenchmarkSync();
        }

        mockLocus.setPowerState(const PowerState(
          batteryLevel: 68,
          isCharging: false,
        ));
        final result = await service.stopBenchmark();

        expect(result!.syncRequests, 5);
      });
    });

    group('powerStateEvents', () {
      test('should emit power state changes', () async {
        final events = <PowerStateChangeEvent>[];
        final sub = service.powerStateEvents.listen(events.add);

        mockLocus.setPowerState(
          const PowerState(batteryLevel: 80, isCharging: false),
        );

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.current.batteryLevel, 80);

        await sub.cancel();
      });

      test('should detect low battery transition', () async {
        final events = <PowerStateChangeEvent>[];
        final sub = service.powerStateEvents.listen(events.add);

        mockLocus.setPowerState(
          const PowerState(
            batteryLevel: 15,
            isCharging: false,
            isPowerSaveMode: true,
          ),
        );

        await Future.delayed(Duration.zero);

        expect(events.first.current.isPowerSaveMode, isTrue);

        await sub.cancel();
      });
    });

    group('powerSaveChanges', () {
      test('should emit power save mode changes', () async {
        final states = <bool>[];
        final sub = service.powerSaveChanges.listen(states.add);

        mockLocus.emitPowerSaveChange(true);
        mockLocus.emitPowerSaveChange(false);

        await Future.delayed(Duration.zero);

        expect(states, [true, false]);

        await sub.cancel();
      });
    });

    group('subscriptions', () {
      test('onPowerStateChange should receive events', () async {
        PowerStateChangeEvent? received;
        final sub = service.onPowerStateChange((event) {
          received = event;
        });

        mockLocus.setPowerState(
          const PowerState(batteryLevel: 60, isCharging: false),
        );

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received!.current.batteryLevel, 60);

        await sub.cancel();
      });

      test('onPowerSaveChange should receive mode changes', () async {
        bool? received;
        final sub = service.onPowerSaveChange((mode) {
          received = mode;
        });

        mockLocus.emitPowerSaveChange(true);

        await Future.delayed(Duration.zero);

        expect(received, isTrue);

        await sub.cancel();
      });

      test('should handle subscription errors', () async {
        Object? error;
        final sub = service.onPowerStateChange(
          (_) {},
          onError: (e) => error = e,
        );

        await sub.cancel();
        expect(error, isNull);
      });
    });
  });
}
