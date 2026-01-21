import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('GeofenceService behavior', () {
    late MockLocus mockLocus;
    late GeofenceServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = GeofenceServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('events stream emits geofence events from mock', () async {
      final events = <GeofenceEvent>[];
      final sub = service.events.listen(events.add);

      final geofence = MockGeofenceExtension.mock(identifier: 'office');
      mockLocus.emitGeofenceEvent(GeofenceEvent(
        geofence: geofence,
        action: GeofenceAction.enter,
        location: MockLocationExtension.mock(),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.geofence.identifier, 'office');
      expect(events.first.action, GeofenceAction.enter);

      await sub.cancel();
    });

    test('polygonEvents emits enter event on location update', () async {
      final polygon = PolygonGeofence(
        identifier: 'campus',
        vertices: [
          const GeoPoint(latitude: 37.0, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -121.9),
          const GeoPoint(latitude: 37.0, longitude: -121.9),
        ],
      );

      await service.addPolygon(polygon);

      final events = <PolygonGeofenceEvent>[];
      final sub = service.polygonEvents.listen(events.add);

      mockLocus.emitPolygonGeofenceEvent(PolygonGeofenceEvent(
        geofence: polygon,
        type: PolygonGeofenceEventType.enter,
        timestamp: DateTime.now(),
        triggerLocation: const GeoPoint(latitude: 37.05, longitude: -121.95),
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first.type, PolygonGeofenceEventType.enter);
      expect(events.first.geofence.identifier, 'campus');

      await sub.cancel();
    });
  });
}
