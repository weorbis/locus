import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/trips/models/trip_state.dart';

void main() {
  group('TripState.toSummary', () {
    TripState _makeState({
      required double distanceMeters,
      required int idleSeconds,
      required double maxSpeedKph,
      required DateTime startedAt,
    }) {
      return TripState(
        tripId: 'test-trip',
        createdAt: startedAt,
        startedAt: startedAt,
        startLocation: null,
        lastLocation: null,
        distanceMeters: distanceMeters,
        idleSeconds: idleSeconds,
        maxSpeedKph: maxSpeedKph,
        started: true,
        ended: false,
      );
    }

    test('averageSpeedKph never exceeds maxSpeedKph', () {
      // Short trip with high idle: 50m in 60s with 55s idle → 5s moving.
      // Raw avg = (50 / 5) * 3.6 = 36 km/h, but max was only 1.6.
      final start = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final end = start.add(const Duration(seconds: 60));
      final state = _makeState(
        distanceMeters: 50,
        idleSeconds: 55,
        maxSpeedKph: 1.6,
        startedAt: start,
      );

      final summary = state.toSummary(end);
      expect(summary, isNotNull);
      expect(summary!.averageSpeedKph, lessThanOrEqualTo(summary.maxSpeedKph));
      expect(summary.averageSpeedKph, 1.6);
    });

    test('averageSpeedKph uses total duration when movingSeconds is zero', () {
      // All idle: idle >= duration → movingSeconds clamped to 0 → falls back
      // to total duration.
      final start = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final end = start.add(const Duration(seconds: 60));
      final state = _makeState(
        distanceMeters: 100,
        idleSeconds: 120, // more idle than duration
        maxSpeedKph: 10,
        startedAt: start,
      );

      final summary = state.toSummary(end);
      expect(summary, isNotNull);
      // fallback: (100 / 60) * 3.6 = 6.0 km/h
      expect(summary!.averageSpeedKph, closeTo(6.0, 0.01));
    });

    test('normal trip produces sensible averageSpeedKph', () {
      // 10 km in 30 min, 5 min idle → 25 min moving.
      // avg = (10000 / 1500) * 3.6 = 24 km/h
      final start = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final end = start.add(const Duration(minutes: 30));
      final state = _makeState(
        distanceMeters: 10000,
        idleSeconds: 300,
        maxSpeedKph: 60,
        startedAt: start,
      );

      final summary = state.toSummary(end);
      expect(summary, isNotNull);
      expect(summary!.averageSpeedKph, closeTo(24.0, 0.01));
      expect(summary.averageSpeedKph, lessThanOrEqualTo(summary.maxSpeedKph));
    });

    test('returns null when startedAt is null', () {
      final state = TripState(
        tripId: 'test',
        createdAt: DateTime.utc(2026),
        startedAt: null,
        startLocation: null,
        lastLocation: null,
        distanceMeters: 0,
        idleSeconds: 0,
        maxSpeedKph: 0,
        started: false,
        ended: false,
      );
      expect(state.toSummary(DateTime.utc(2026)), isNull);
    });
  });
}
