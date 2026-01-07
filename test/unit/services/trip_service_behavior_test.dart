import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('TripService behavior', () {
    late MockLocus mockLocus;
    late TripServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = TripServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('start initializes state and stop returns summary', () async {
      const config = TripConfig(tripId: 'trip-123');

      await service.start(config);

      final state = service.getState();
      expect(state, isNotNull);
      expect(state!.tripId, 'trip-123');
      expect(state.started, isTrue);

      final summary = await service.stop();
      expect(summary, isNotNull);
      expect(summary!.tripId, 'trip-123');
      expect(summary.endedAt, isNotNull);
    });

    test('events stream emits trip events from mock', () async {
      final events = <TripEvent>[];
      final sub = service.events.listen(events.add);

      mockLocus.emitTripEvent(TripEvent(
        type: TripEventType.tripUpdate,
        tripId: 'trip-123',
        timestamp: DateTime.now(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.type, TripEventType.tripUpdate);

      await sub.cancel();
    });
  });
}
