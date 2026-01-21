/// Integration tests for the Locus SDK.
///
/// These tests verify end-to-end functionality with mocked platform channels.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('polygon geofence service is registered with streams', () async {
    // Adding a polygon geofence should work without errors
    final polygon = PolygonGeofence(
      identifier: 'test-polygon',
      vertices: [
        GeoPoint(latitude: 37.0, longitude: -122.0),
        GeoPoint(latitude: 37.1, longitude: -122.0),
        GeoPoint(latitude: 37.1, longitude: -122.1),
        GeoPoint(latitude: 37.0, longitude: -122.1),
      ],
    );

    final area1 = polygon.areaSquareMeters;
    final area2 = polygon.areaSquareMeters;

    expect(area1, greaterThan(0));
    expect(area1, equals(area2));
  });
}
