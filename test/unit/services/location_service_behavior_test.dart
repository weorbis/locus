import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('LocationService behavior', () {
    late MockLocus mockLocus;
    late LocationServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = LocationServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('getSummary returns empty summary when no locations exist', () async {
      final summary = await service.getSummary();

      expect(summary.locationCount, 0);
      expect(summary.totalDistanceMeters, 0);
      expect(summary.movingDuration, Duration.zero);
      expect(summary.stationaryDuration, Duration.zero);
      expect(summary.periodStart, isNull);
      expect(summary.periodEnd, isNull);
    });

    test('getSummary uses date filter to scope locations', () async {
      final day = DateTime(2026, 1, 1, 9);
      final laterSameDay = day.add(const Duration(minutes: 10));
      final nextDay = day.add(const Duration(days: 1));

      mockLocus.emitLocation(MockLocationExtension.mock(
        timestamp: day,
        isMoving: false,
      ));
      mockLocus.emitLocation(MockLocationExtension.mock(
        timestamp: laterSameDay,
        isMoving: false,
      ));
      mockLocus.emitLocation(MockLocationExtension.mock(
        timestamp: nextDay,
        isMoving: true,
      ));

      final summary = await service.getSummary(
        date: DateTime(2026, 1, 1),
      );

      expect(summary.locationCount, 2);
      expect(summary.totalDistanceMeters, 0);
      expect(summary.movingDuration, Duration.zero);
      expect(summary.stationaryDuration, const Duration(minutes: 10));
      expect(summary.periodStart, day);
      expect(summary.periodEnd, laterSameDay);
    });

    test('getSummary respects query filters', () async {
      final first = DateTime(2026, 1, 1, 10);
      final second = first.add(const Duration(minutes: 1));

      mockLocus.emitLocation(MockLocationExtension.mock(
        timestamp: first,
        isMoving: false,
      ));
      mockLocus.emitLocation(MockLocationExtension.mock(
        timestamp: second,
        isMoving: true,
      ));

      final summary = await service.getSummary(
        query: const LocationQuery(isMoving: true),
      );

      expect(summary.locationCount, 1);
      expect(summary.movingDuration, Duration.zero);
      expect(summary.stationaryDuration, Duration.zero);
      expect(summary.periodStart, second);
      expect(summary.periodEnd, second);
    });
  });
}
