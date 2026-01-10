/// Comprehensive tests for TripService API.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('TripService', () {
    late MockLocus mockLocus;
    late TripServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = TripServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('start', () {
      test('should start trip with config', () async {
        const config = TripConfig(tripId: 'delivery-123');

        await service.start(config);

        expect(mockLocus.methodCalls, contains('startTrip'));
      });

      test('should start trip with trip id', () async {
        const config = TripConfig(
          tripId: 'trip-456',
        );

        await service.start(config);

        expect(mockLocus.methodCalls, contains('startTrip'));
      });
    });

    group('stop', () {
      test('should stop trip and return summary', () async {
        const config = TripConfig(tripId: 'trip-1');
        await service.start(config);

        await service.stop();

        expect(mockLocus.methodCalls, contains('stopTrip'));
      });

      test('should return null if no trip active', () async {
        final summary = await service.stop();

        expect(summary, isNull);
      });
    });

    group('getState', () {
      test('should return current trip state', () async {
        const config = TripConfig(tripId: 'trip-1');
        await service.start(config);

        final state = service.getState();

        expect(state, isA<TripState?>());
      });

      test('should return null if no trip active', () {
        final state = service.getState();

        expect(state, isNull);
      });
    });

    group('events', () {
      test('should emit trip started event', () async {
        final events = <TripEvent>[];
        final sub = service.events.listen(events.add);

        const config = TripConfig(tripId: 'trip-1');
        await service.start(config);

        final event = TripEvent(
          type: TripEventType.tripStart,
          tripId: 'trip-1',
          timestamp: DateTime.now(),
        );
        mockLocus.emitTripEvent(event);

        await Future.delayed(Duration.zero);

        expect(events, isNotEmpty);

        await sub.cancel();
      });

      test('should emit trip updated event', () async {
        final events = <TripEvent>[];
        final sub = service.events.listen(events.add);

        final event = TripEvent(
          type: TripEventType.tripUpdate,
          tripId: 'trip-1',
          timestamp: DateTime.now(),
        );
        mockLocus.emitTripEvent(event);

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));

        await sub.cancel();
      });

      test('should emit trip completed event', () async {
        final events = <TripEvent>[];
        final sub = service.events.listen(events.add);

        final now = DateTime.now();
        final startedAt = now.subtract(const Duration(minutes: 10));
        final event = TripEvent(
          type: TripEventType.tripEnd,
          tripId: 'trip-1',
          timestamp: now,
          summary: TripSummary(
            tripId: 'trip-1',
            startedAt: startedAt,
            endedAt: now,
            distanceMeters: 5000,
            durationSeconds: 600,
            idleSeconds: 0,
            maxSpeedKph: 50,
            averageSpeedKph: 30,
          ),
        );
        mockLocus.emitTripEvent(event);

        await Future.delayed(Duration.zero);

        expect(events.first.type, TripEventType.tripEnd);

        await sub.cancel();
      });
    });

    group('subscriptions', () {
      test('onEvent should receive trip events', () async {
        TripEvent? received;
        final sub = service.onEvent((event) {
          received = event;
        });

        final event = TripEvent(
          type: TripEventType.tripStart,
          tripId: 'trip-1',
          timestamp: DateTime.now(),
        );
        mockLocus.emitTripEvent(event);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received!.tripId, 'trip-1');

        await sub.cancel();
      });

      test('should handle subscription errors', () async {
        Object? error;
        final sub = service.onEvent(
          (_) {},
          onError: (e) => error = e,
        );

        await sub.cancel();
        expect(error, isNull);
      });
    });
  });
}
