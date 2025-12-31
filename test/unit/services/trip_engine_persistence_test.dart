import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

class _MemoryTripStore implements TripStore {
  TripState? _state;

  @override
  Future<void> clear() async {
    _state = null;
  }

  @override
  Future<TripState?> load() async => _state;

  @override
  Future<void> save(TripState state) async {
    _state = state;
  }
}

Location _locationAt({
  required DateTime timestamp,
  required double lat,
  required double lng,
}) {
  return Location(
    uuid: timestamp.microsecondsSinceEpoch.toString(),
    timestamp: timestamp,
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: 5,
    ),
  );
}

void main() {
  test('trip engine persists and restores state', () async {
    final store = _MemoryTripStore();
    final engine = TripEngine(store: store);
    final controller = StreamController<Location>();

    await engine.start(
        const TripConfig(startOnMoving: false), controller.stream);

    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    controller.add(_locationAt(timestamp: now, lat: 0, lng: 0));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final saved = await store.load();
    expect(saved, isNotNull);
    expect(saved!.started, true);

    final restoredEngine = TripEngine(store: store);
    final secondController = StreamController<Location>();
    await restoredEngine.start(
        const TripConfig(startOnMoving: false), secondController.stream);

    expect(restoredEngine.state?.tripId, saved.tripId);

    await controller.close();
    await secondController.close();
    engine.dispose();
    restoredEngine.dispose();
  });
}
