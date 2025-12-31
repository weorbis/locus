import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

Location _locationAt({
  required DateTime timestamp,
  required double lat,
  required double lng,
  double accuracy = 5,
}) {
  return Location(
    uuid: timestamp.microsecondsSinceEpoch.toString(),
    timestamp: timestamp,
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      speed: 0,
    ),
  );
}

void main() {
  test('quality analyzer produces scores', () async {
    final controller = StreamController<Location>();
    final future = LocationQualityAnalyzer.analyze(
      controller.stream,
      config: const LocationQualityConfig(maxAccuracyMeters: 10),
    ).take(2).toList();

    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    controller.add(_locationAt(timestamp: now, lat: 0, lng: 0, accuracy: 5));
    controller.add(
      _locationAt(
        timestamp: now.add(const Duration(seconds: 5)),
        lat: 0.0001,
        lng: 0.0001,
        accuracy: 15,
      ),
    );

    await controller.close();

    final qualities = await future;
    expect(qualities.length, 2);
    expect(qualities.first.overallScore, greaterThanOrEqualTo(0));
  });

  test('quality analyzer flags spoof suspicion', () async {
    final controller = StreamController<Location>();
    final stream = LocationQualityAnalyzer.analyze(controller.stream);

    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    controller.add(_locationAt(timestamp: now, lat: 0, lng: 0));
    controller.add(_locationAt(
      timestamp: now.add(const Duration(seconds: 1)),
      lat: 0,
      lng: 0,
    ));

    final results = await stream.take(2).toList();
    await controller.close();

    expect(results.last.isSpoofSuspected, true);
  });
}
