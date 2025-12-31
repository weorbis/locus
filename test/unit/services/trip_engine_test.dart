import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

Location _locationAt({
  required DateTime timestamp,
  required double lat,
  required double lng,
  double accuracy = 5,
  bool? isMoving,
}) {
  return Location(
    uuid: timestamp.microsecondsSinceEpoch.toString(),
    timestamp: timestamp,
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
    ),
    isMoving: isMoving,
  );
}

void main() {
  test('trip starts when movement threshold met', () async {
    final engine = TripEngine();
    final controller = StreamController<Location>();
    await engine.start(
      const TripConfig(
        startOnMoving: true,
        startDistanceMeters: 10,
        startSpeedKph: 1,
        updateIntervalSeconds: 1,
      ),
      controller.stream,
    );

    final events = <TripEvent>[];
    engine.events.listen(events.add);

    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    controller.add(_locationAt(timestamp: now, lat: 0, lng: 0));
    controller.add(_locationAt(
      timestamp: now.add(const Duration(seconds: 10)),
      lat: 0.001,
      lng: 0.001,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(events.any((event) => event.type == TripEventType.tripStart), true);
    controller.close();
    engine.dispose();
  });

  test('route deviation emits event', () async {
    final engine = TripEngine();
    final controller = StreamController<Location>();
    await engine.start(
      TripConfig(
        startOnMoving: false,
        updateIntervalSeconds: 1,
        route: const [
          RoutePoint(latitude: 0, longitude: 0),
          RoutePoint(latitude: 0, longitude: 1),
        ],
        routeDeviationThresholdMeters: 50,
      ),
      controller.stream,
    );

    final events = <TripEvent>[];
    engine.events.listen(events.add);

    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    controller.add(_locationAt(timestamp: now, lat: 1, lng: 1));
    controller.add(_locationAt(
      timestamp: now.add(const Duration(seconds: 5)),
      lat: 1.001,
      lng: 1.001,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      events.any((event) => event.type == TripEventType.routeDeviation),
      true,
    );
    controller.close();
    engine.dispose();
  });
}
