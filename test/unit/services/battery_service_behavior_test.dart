import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('BatteryService behavior', () {
    late MockLocus mockLocus;
    late BatteryServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = BatteryServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('getStats reflects mock battery stats', () async {
      const stats = BatteryStats(
        gpsOnTimePercent: 12.5,
        locationUpdatesCount: 42,
        trackingDurationMinutes: 60,
        currentBatteryLevel: 72,
      );

      mockLocus.setBatteryStats(stats);

      final result = await service.getStats();
      expect(result.locationUpdatesCount, 42);
      expect(result.currentBatteryLevel, 72);
      expect(result.gpsOnTimePercent, 12.5);
    });

    test('getPowerState returns updated power state', () async {
      const state = PowerState(
        batteryLevel: 88,
        isCharging: false,
        isPowerSaveMode: true,
      );
      mockLocus.setPowerState(state);

      final result = await service.getPowerState();
      expect(result.batteryLevel, 88);
      expect(result.isPowerSaveMode, isTrue);
    });

    test('benchmark captures drain and activity counts', () async {
      mockLocus.setPowerState(const PowerState(
        batteryLevel: 80,
        isCharging: false,
      ));

      await service.startBenchmark();
      service.recordBenchmarkLocationUpdate(accuracy: 12.5);
      service.recordBenchmarkSync();

      mockLocus.setPowerState(const PowerState(
        batteryLevel: 75,
        isCharging: false,
      ));

      final result = await service.stopBenchmark();

      expect(result, isNotNull);
      expect(result!.drainPercent, 5);
      expect(result.locationUpdates, 1);
      expect(result.syncRequests, 1);
    });
  });
}
