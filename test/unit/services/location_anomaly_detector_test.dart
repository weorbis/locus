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
    ),
  );
}

void main() {
  test('flags anomalous jump based on speed', () async {
    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    final locations = Stream.fromIterable([
      _locationAt(timestamp: now, lat: 0, lng: 0),
      _locationAt(
        timestamp: now.add(const Duration(seconds: 10)),
        lat: 1,
        lng: 1,
      ),
    ]);

    final anomalies = await LocationAnomalyDetector.watch(
      locations,
      config: const LocationAnomalyConfig(
        maxSpeedKph: 200,
        minDistanceMeters: 1000,
        minTimeDelta: Duration(seconds: 1),
        maxAccuracyMeters: 50,
      ),
    ).toList();

    expect(anomalies.length, 1);
    expect(anomalies.first.speedKph, greaterThan(200));
  });

  test('ignores jumps with poor accuracy', () async {
    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    final locations = Stream.fromIterable([
      _locationAt(timestamp: now, lat: 0, lng: 0, accuracy: 150),
      _locationAt(
        timestamp: now.add(const Duration(seconds: 10)),
        lat: 1,
        lng: 1,
        accuracy: 150,
      ),
    ]);

    final anomalies = await LocationAnomalyDetector.watch(
      locations,
      config: const LocationAnomalyConfig(
        maxSpeedKph: 50,
        maxAccuracyMeters: 100,
      ),
    ).toList();

    expect(anomalies, isEmpty);
  });

  test('ignores short movements', () async {
    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    final locations = Stream.fromIterable([
      _locationAt(timestamp: now, lat: 0, lng: 0),
      _locationAt(
        timestamp: now.add(const Duration(seconds: 30)),
        lat: 0.0001,
        lng: 0.0001,
      ),
    ]);

    final anomalies = await LocationAnomalyDetector.watch(
      locations,
      config: const LocationAnomalyConfig(
        maxSpeedKph: 30,
        minDistanceMeters: 500,
      ),
    ).toList();

    expect(anomalies, isEmpty);
  });
}
