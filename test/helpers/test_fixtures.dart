/// Shared test utilities and fixtures for Locus tests.
library;

import 'package:locus/locus.dart';

/// Creates a test location with the given parameters.
Location createTestLocation({
  required double lat,
  required double lng,
  double accuracy = 10,
  DateTime? timestamp,
  bool isMoving = false,
  double odometer = 0,
}) {
  return Location(
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      speed: 0,
      heading: 0,
      altitude: 0,
    ),
    timestamp: timestamp ?? DateTime.now(),
    isMoving: isMoving,
    uuid: 'test-${DateTime.now().millisecondsSinceEpoch}',
    odometer: odometer,
  );
}
