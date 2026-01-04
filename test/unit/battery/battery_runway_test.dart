import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/battery/models/battery_runway.dart';

void main() {
  group('BatteryRunway', () {
    test('reports charging state correctly', () {
      final runway = BatteryRunway.charging(currentLevel: 50);

      expect(runway.isCharging, isTrue);
      expect(runway.duration.inHours, 999);
      expect(runway.lowPowerDuration.inHours, 999);
      expect(runway.confidence, 1.0);
      expect(runway.isCritical, isFalse);
      expect(runway.isLow, isFalse);
      expect(runway.shouldSwitchToLowPower, isFalse);
      expect(runway.formattedDuration, 'Unlimited');
    });

    test('reports insufficient data correctly', () {
      final runway = BatteryRunway.insufficientData(currentLevel: 80);

      expect(runway.duration, Duration.zero);
      expect(runway.lowPowerDuration, Duration.zero);
      expect(runway.confidence, 0.0);
      expect(runway.recommendation, contains('Insufficient'));
    });

    test('identifies critical battery level', () {
      final runway = BatteryRunway(
        duration: const Duration(minutes: 10),
        lowPowerDuration: const Duration(minutes: 25),
        recommendation: 'Critical',
        currentLevel: 5,
      );

      expect(runway.isCritical, isTrue);
      expect(runway.isLow, isFalse);
    });

    test('identifies low battery level', () {
      final runway = BatteryRunway(
        duration: const Duration(minutes: 30),
        lowPowerDuration: const Duration(minutes: 75),
        recommendation: 'Low',
        currentLevel: 12,
      );

      expect(runway.isCritical, isFalse);
      expect(runway.isLow, isTrue);
    });

    test('suggests switching to low power when beneficial', () {
      final runway = BatteryRunway(
        duration: const Duration(minutes: 45),
        lowPowerDuration: const Duration(minutes: 120),
        recommendation: 'Consider low power',
        currentLevel: 25,
      );

      expect(runway.shouldSwitchToLowPower, isTrue);
    });

    test('does not suggest low power when duration is sufficient', () {
      final runway = BatteryRunway(
        duration: const Duration(minutes: 180),
        lowPowerDuration: const Duration(minutes: 450),
        recommendation: 'Sufficient',
        currentLevel: 75,
      );

      expect(runway.shouldSwitchToLowPower, isFalse);
    });

    test('formats duration correctly', () {
      expect(
        BatteryRunway(
          duration: const Duration(hours: 2, minutes: 30),
          lowPowerDuration: Duration.zero,
          recommendation: '',
          currentLevel: 50,
        ).formattedDuration,
        '2h 30m',
      );

      expect(
        BatteryRunway(
          duration: const Duration(minutes: 45),
          lowPowerDuration: Duration.zero,
          recommendation: '',
          currentLevel: 50,
        ).formattedDuration,
        '45m',
      );

      expect(
        BatteryRunway(
          duration: const Duration(days: 1, hours: 5),
          lowPowerDuration: Duration.zero,
          recommendation: '',
          currentLevel: 50,
        ).formattedDuration,
        '1d 5h',
      );
    });

    test('serializes to and from map correctly', () {
      const original = BatteryRunway(
        duration: Duration(minutes: 120),
        lowPowerDuration: Duration(minutes: 300),
        recommendation: 'Test recommendation',
        currentLevel: 65,
        isCharging: false,
        drainRatePerHour: 2.5,
        lowPowerDrainRatePerHour: 1.0,
        confidence: 0.8,
      );

      final map = original.toMap();
      final restored = BatteryRunway.fromMap(map);

      expect(restored.duration.inMinutes, original.duration.inMinutes);
      expect(restored.lowPowerDuration.inMinutes,
          original.lowPowerDuration.inMinutes);
      expect(restored.recommendation, original.recommendation);
      expect(restored.currentLevel, original.currentLevel);
      expect(restored.isCharging, original.isCharging);
      expect(restored.drainRatePerHour, original.drainRatePerHour);
      expect(
          restored.lowPowerDrainRatePerHour, original.lowPowerDrainRatePerHour);
      expect(restored.confidence, original.confidence);
    });
  });

  group('BatteryRunwayCalculator', () {
    test('returns charging state when device is charging', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 50,
        isCharging: true,
        drainPercent: 10,
        trackingMinutes: 60,
      );

      expect(runway.isCharging, isTrue);
      expect(runway.duration.inHours, 999);
    });

    test('calculates runway from drain rate', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 55, // 55% - 5% reserve = 50% available
        isCharging: false,
        drainPercent: 10, // 10% in 60 minutes = 10%/hr
        trackingMinutes: 60,
      );

      // 50% available / 10%/hr = 5 hours = 300 minutes
      expect(runway.duration.inMinutes, 300);
      expect(runway.drainRatePerHour, closeTo(10.0, 0.1));
      expect(runway.confidence, closeTo(1.0, 0.1));
    });

    test('uses default drain rate when insufficient data', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 55, // 50% available after reserve
        isCharging: false,
        drainPercent: null,
        trackingMinutes: 2, // Less than minimum
      );

      // Uses default 5%/hr: 50% / 5%/hr = 10 hours = 600 minutes
      expect(runway.duration.inMinutes, 600);
      expect(runway.drainRatePerHour, isNull);
      expect(runway.confidence, 0.0);
    });

    test('calculates low power duration with multiplier', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 55,
        isCharging: false,
        drainPercent: 10,
        trackingMinutes: 60,
      );

      // Low power = 10%/hr * 0.4 = 4%/hr
      // 50% / 4%/hr = 12.5 hours = 750 minutes
      expect(runway.lowPowerDuration.inMinutes, 750);
      expect(runway.lowPowerDrainRatePerHour, closeTo(4.0, 0.1));
    });

    test('respects reserve level', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 10, // Only 5% available after reserve
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 60,
        reserveLevel: 5,
      );

      // 5% available / 5%/hr = 1 hour = 60 minutes
      expect(runway.duration.inMinutes, 60);
    });

    test('generates critical recommendation at low levels', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 5,
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 60,
      );

      expect(runway.recommendation, contains('critical'));
    });

    test('generates low battery recommendation', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 12,
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 60,
      );

      expect(runway.recommendation, contains('low'));
    });

    test('generates sufficient battery recommendation for high levels', () {
      final runway = BatteryRunwayCalculator.calculate(
        currentLevel: 80,
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 60,
      );

      expect(runway.recommendation, contains('sufficient'));
    });

    test('increases confidence with longer tracking time', () {
      final shortTracking = BatteryRunwayCalculator.calculate(
        currentLevel: 50,
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 15,
      );

      final longTracking = BatteryRunwayCalculator.calculate(
        currentLevel: 50,
        isCharging: false,
        drainPercent: 5,
        trackingMinutes: 90,
      );

      expect(longTracking.confidence, greaterThan(shortTracking.confidence));
    });
  });
}
