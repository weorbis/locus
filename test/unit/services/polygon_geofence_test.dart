import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeoPoint', () {
    test('creates with valid coordinates', () {
      const point = GeoPoint(latitude: 37.7749, longitude: -122.4194);
      expect(point.latitude, 37.7749);
      expect(point.longitude, -122.4194);
      expect(point.isValid, true);
    });

    test('isValid returns false for invalid latitude', () {
      const point = GeoPoint(latitude: 91.0, longitude: -122.4194);
      expect(point.isValid, false);
    });

    test('isValid returns false for invalid longitude', () {
      const point = GeoPoint(latitude: 37.7749, longitude: -181.0);
      expect(point.isValid, false);
    });

    test('serializes to and from map', () {
      const original = GeoPoint(latitude: 37.7749, longitude: -122.4194);
      final map = original.toMap();
      final restored = GeoPoint.fromMap(map);

      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
    });

    test('equality works correctly', () {
      const point1 = GeoPoint(latitude: 37.7749, longitude: -122.4194);
      const point2 = GeoPoint(latitude: 37.7749, longitude: -122.4194);
      const point3 = GeoPoint(latitude: 37.7750, longitude: -122.4194);

      expect(point1, equals(point2));
      expect(point1, isNot(equals(point3)));
    });
  });

  group('PolygonGeofence', () {
    late PolygonGeofence validPolygon;

    setUp(() {
      validPolygon = PolygonGeofence(
        identifier: 'test-polygon',
        vertices: [
          const GeoPoint(latitude: 37.0, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -121.9),
          const GeoPoint(latitude: 37.0, longitude: -121.9),
        ],
      );
    });

    test('creates with required parameters', () {
      expect(validPolygon.identifier, 'test-polygon');
      expect(validPolygon.vertices.length, 4);
      expect(validPolygon.notifyOnEntry, true);
      expect(validPolygon.notifyOnExit, true);
      expect(validPolygon.notifyOnDwell, false);
    });

    test('isValid returns true for valid polygon', () {
      expect(validPolygon.isValid, true);
    });

    test('isValid returns false for empty identifier', () {
      final polygon = PolygonGeofence(
        identifier: '',
        vertices: validPolygon.vertices,
      );
      expect(polygon.isValid, false);
    });

    test('isValid returns false for less than 3 vertices', () {
      final polygon = PolygonGeofence(
        identifier: 'invalid',
        vertices: [
          const GeoPoint(latitude: 37.0, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -122.0),
        ],
      );
      expect(polygon.isValid, false);
    });

    test('isValid returns false for invalid vertex coordinates', () {
      final polygon = PolygonGeofence(
        identifier: 'invalid',
        vertices: [
          const GeoPoint(latitude: 91.0, longitude: -122.0), // Invalid latitude
          const GeoPoint(latitude: 37.1, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -121.9),
        ],
      );
      expect(polygon.isValid, false);
    });

    test('centroid calculates correctly', () {
      final centroid = validPolygon.centroid;
      expect(centroid.latitude, closeTo(37.05, 0.01));
      expect(centroid.longitude, closeTo(-121.95, 0.01));
    });

    test('boundingBox calculates correctly', () {
      final bbox = validPolygon.boundingBox;
      expect(bbox[0], 37.0); // minLat
      expect(bbox[1], -122.0); // minLng
      expect(bbox[2], 37.1); // maxLat
      expect(bbox[3], -121.9); // maxLng
    });

    test('containsPoint returns true for point inside', () {
      // Point in the center of the square
      expect(validPolygon.containsPoint(37.05, -121.95), true);
    });

    test('containsPoint returns false for point outside', () {
      // Point outside the square
      expect(validPolygon.containsPoint(38.0, -121.95), false);
    });

    test('containsPoint returns false for point outside bounding box', () {
      // Point far outside
      expect(validPolygon.containsPoint(40.0, -100.0), false);
    });

    test('containsGeoPoint works correctly', () {
      const inside = GeoPoint(latitude: 37.05, longitude: -121.95);
      const outside = GeoPoint(latitude: 38.0, longitude: -121.95);

      expect(validPolygon.containsGeoPoint(inside), true);
      expect(validPolygon.containsGeoPoint(outside), false);
    });

    test('areaSquareMeters calculates non-zero area', () {
      expect(validPolygon.areaSquareMeters, greaterThan(0));
    });

    test('perimeterMeters calculates non-zero perimeter', () {
      expect(validPolygon.perimeterMeters, greaterThan(0));
    });

    test('serializes to and from map', () {
      final map = validPolygon.toMap();
      final restored = PolygonGeofence.fromMap(map);

      expect(restored.identifier, validPolygon.identifier);
      expect(restored.vertices.length, validPolygon.vertices.length);
      expect(restored.notifyOnEntry, validPolygon.notifyOnEntry);
      expect(restored.notifyOnExit, validPolygon.notifyOnExit);
      expect(restored.notifyOnDwell, validPolygon.notifyOnDwell);
    });

    test('serialization preserves extras', () {
      final polygon = PolygonGeofence(
        identifier: 'with-extras',
        vertices: validPolygon.vertices,
        extras: {'customKey': 'customValue'},
      );

      final map = polygon.toMap();
      final restored = PolygonGeofence.fromMap(map);

      expect(restored.extras, isNotNull);
      expect(restored.extras!['customKey'], 'customValue');
    });

    test('copyWith creates modified copy', () {
      final modified = validPolygon.copyWith(
        notifyOnDwell: true,
        loiteringDelay: 30000,
      );

      expect(modified.identifier, validPolygon.identifier);
      expect(modified.vertices, validPolygon.vertices);
      expect(modified.notifyOnDwell, true);
      expect(modified.loiteringDelay, 30000);
    });

    test('equality is based on identifier', () {
      final polygon1 = PolygonGeofence(
        identifier: 'same-id',
        vertices: validPolygon.vertices,
      );

      final polygon2 = PolygonGeofence(
        identifier: 'same-id',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      expect(polygon1, equals(polygon2));
    });
  });

  group('PolygonGeofence complex shapes', () {
    test('triangular polygon contains center point', () {
      final triangle = PolygonGeofence(
        identifier: 'triangle',
        vertices: [
          const GeoPoint(latitude: 0.0, longitude: 0.0),
          const GeoPoint(latitude: 1.0, longitude: 0.5),
          const GeoPoint(latitude: 0.0, longitude: 1.0),
        ],
      );

      // Center of triangle
      expect(triangle.containsPoint(0.3, 0.5), true);
      // Outside triangle
      expect(triangle.containsPoint(0.9, 0.1), false);
    });

    test('L-shaped polygon works correctly', () {
      // L-shape: bottom-left corner of a square + bottom extension
      final lShape = PolygonGeofence(
        identifier: 'l-shape',
        vertices: [
          const GeoPoint(latitude: 0.0, longitude: 0.0),
          const GeoPoint(latitude: 0.0, longitude: 1.0),
          const GeoPoint(latitude: 0.5, longitude: 1.0),
          const GeoPoint(latitude: 0.5, longitude: 0.5),
          const GeoPoint(latitude: 1.0, longitude: 0.5),
          const GeoPoint(latitude: 1.0, longitude: 0.0),
        ],
      );

      // Point in bottom part
      expect(lShape.containsPoint(0.2, 0.2), true);
      // Point in right part
      expect(lShape.containsPoint(0.7, 0.2), true);
      // Point in empty corner (top-right)
      expect(lShape.containsPoint(0.7, 0.7), false);
    });
  });

  group('PolygonGeofenceEvent', () {
    test('creates with required parameters', () {
      final polygon = PolygonGeofence(
        identifier: 'test',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      final event = PolygonGeofenceEvent(
        geofence: polygon,
        type: PolygonGeofenceEventType.enter,
        timestamp: DateTime.now(),
      );

      expect(event.geofence.identifier, 'test');
      expect(event.type, PolygonGeofenceEventType.enter);
      expect(event.triggerLocation, isNull);
    });

    test('serializes to and from map', () {
      final polygon = PolygonGeofence(
        identifier: 'test',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      final original = PolygonGeofenceEvent(
        geofence: polygon,
        type: PolygonGeofenceEventType.exit,
        timestamp: DateTime(2026, 1, 3, 12, 0, 0),
        triggerLocation: const GeoPoint(latitude: 0.5, longitude: 0.5),
      );

      final map = original.toMap();
      final restored = PolygonGeofenceEvent.fromMap(map);

      expect(restored.geofence.identifier, original.geofence.identifier);
      expect(restored.type, original.type);
      expect(restored.triggerLocation?.latitude, 0.5);
    });
  });

  group('PolygonGeofenceService', () {
    late PolygonGeofenceService service;
    late PolygonGeofence testPolygon;

    setUp(() {
      service = PolygonGeofenceService();
      testPolygon = PolygonGeofence(
        identifier: 'test-polygon',
        vertices: [
          const GeoPoint(latitude: 37.0, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -122.0),
          const GeoPoint(latitude: 37.1, longitude: -121.9),
          const GeoPoint(latitude: 37.0, longitude: -121.9),
        ],
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('addPolygonGeofence adds valid polygon', () async {
      final result = await service.addPolygonGeofence(testPolygon);
      expect(result, true);
      expect(service.count, 1);
      expect(service.polygons.first.identifier, 'test-polygon');
    });

    test('addPolygonGeofence rejects duplicate identifier', () async {
      await service.addPolygonGeofence(testPolygon);
      final result = await service.addPolygonGeofence(testPolygon);
      expect(result, false);
      expect(service.count, 1);
    });

    test('addPolygonGeofence throws for invalid polygon', () async {
      final invalidPolygon = PolygonGeofence(
        identifier: '',
        vertices: [],
      );

      expect(
        () => service.addPolygonGeofence(invalidPolygon),
        throwsArgumentError,
      );
    });

    test('addPolygonGeofences adds multiple polygons', () async {
      final polygon2 = PolygonGeofence(
        identifier: 'polygon-2',
        vertices: testPolygon.vertices,
      );

      final count = await service.addPolygonGeofences([testPolygon, polygon2]);
      expect(count, 2);
      expect(service.count, 2);
    });

    test('removePolygonGeofence removes existing polygon', () async {
      await service.addPolygonGeofence(testPolygon);
      final result = await service.removePolygonGeofence('test-polygon');
      expect(result, true);
      expect(service.count, 0);
    });

    test('removePolygonGeofence returns false for non-existent', () async {
      final result = await service.removePolygonGeofence('non-existent');
      expect(result, false);
    });

    test('removeAllPolygonGeofences clears all', () async {
      await service.addPolygonGeofence(testPolygon);
      await service.addPolygonGeofence(PolygonGeofence(
        identifier: 'polygon-2',
        vertices: testPolygon.vertices,
      ));

      await service.removeAllPolygonGeofences();
      expect(service.count, 0);
    });

    test('getPolygonGeofence returns polygon by identifier', () async {
      await service.addPolygonGeofence(testPolygon);
      final result = service.getPolygonGeofence('test-polygon');
      expect(result, isNotNull);
      expect(result!.identifier, 'test-polygon');
    });

    test('getPolygonGeofence returns null for non-existent', () {
      final result = service.getPolygonGeofence('non-existent');
      expect(result, isNull);
    });

    test('polygonExists returns correct value', () async {
      expect(service.polygonExists('test-polygon'), false);
      await service.addPolygonGeofence(testPolygon);
      expect(service.polygonExists('test-polygon'), true);
    });

    test('updatePolygonGeofence updates existing polygon', () async {
      await service.addPolygonGeofence(testPolygon);

      final updated = testPolygon.copyWith(notifyOnDwell: true);
      final result = await service.updatePolygonGeofence(updated);

      expect(result, true);
      expect(service.getPolygonGeofence('test-polygon')!.notifyOnDwell, true);
    });

    test('updatePolygonGeofence returns false for non-existent', () async {
      final result = await service.updatePolygonGeofence(testPolygon);
      expect(result, false);
    });

    test('getContainingPolygons returns matching polygons', () async {
      await service.addPolygonGeofence(testPolygon);

      // Point inside
      final inside = service.getContainingPolygons(37.05, -121.95);
      expect(inside, contains('test-polygon'));

      // Point outside
      final outside = service.getContainingPolygons(38.0, -121.95);
      expect(outside, isEmpty);
    });

    test('isLocationInAnyPolygon works correctly', () async {
      await service.addPolygonGeofence(testPolygon);

      expect(service.isLocationInAnyPolygon(37.05, -121.95), true);
      expect(service.isLocationInAnyPolygon(38.0, -121.95), false);
    });

    test('processLocationUpdate emits enter event', () async {
      await service.addPolygonGeofence(testPolygon);

      final events = <PolygonGeofenceEvent>[];
      service.events.listen(events.add);

      // Move from outside to inside
      service.processLocationUpdate(37.05, -121.95);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(events.length, 1);
      expect(events.first.type, PolygonGeofenceEventType.enter);
      expect(events.first.geofence.identifier, 'test-polygon');
    });

    test('processLocationUpdate emits exit event', () async {
      await service.addPolygonGeofence(testPolygon);

      final events = <PolygonGeofenceEvent>[];
      service.events.listen(events.add);

      // Enter first
      service.processLocationUpdate(37.05, -121.95);
      // Then exit
      service.processLocationUpdate(38.0, -121.95);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(events.length, 2);
      expect(events[0].type, PolygonGeofenceEventType.enter);
      expect(events[1].type, PolygonGeofenceEventType.exit);
    });

    test('isInsidePolygon tracks state correctly', () async {
      await service.addPolygonGeofence(testPolygon);

      expect(service.isInsidePolygon('test-polygon'), false);

      service.processLocationUpdate(37.05, -121.95);
      expect(service.isInsidePolygon('test-polygon'), true);

      service.processLocationUpdate(38.0, -121.95);
      expect(service.isInsidePolygon('test-polygon'), false);
    });

    test('resetState clears inside state', () async {
      await service.addPolygonGeofence(testPolygon);
      service.processLocationUpdate(37.05, -121.95);

      expect(service.isInsidePolygon('test-polygon'), true);

      service.resetState();
      expect(service.isInsidePolygon('test-polygon'), false);
    });

    test('restore initializes from persisted polygons', () {
      service.restore([testPolygon]);

      expect(service.count, 1);
      expect(service.polygonExists('test-polygon'), true);
    });

    test('persistence callback is called on changes', () async {
      List<PolygonGeofence>? persistedPolygons;
      service.setOnPersist((polygons) async {
        persistedPolygons = polygons;
      });

      await service.addPolygonGeofence(testPolygon);

      expect(persistedPolygons, isNotNull);
      expect(persistedPolygons!.length, 1);
    });
  });

  group('Locus polygon geofence API', () {
    late MockLocus mockLocus;
    late MockLocus original;

    setUp(() {
      original = MockLocus();
      mockLocus = MockLocus();
      Locus.setMockInstance(mockLocus);
    });

    tearDown(() {
      Locus.setMockInstance(original);
    });

    test('addPolygonGeofence adds a polygon', () async {
      final polygon = PolygonGeofence(
        identifier: 'test',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      final result = await Locus.geofencing.addPolygon(polygon);
      expect(result, true);
      expect(mockLocus.methodCalls, contains('addPolygonGeofence:test'));
    });

    test('removePolygonGeofence removes a polygon', () async {
      final polygon = PolygonGeofence(
        identifier: 'to-remove',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      await Locus.geofencing.addPolygon(polygon);
      final result = await Locus.geofencing.removePolygon('to-remove');

      expect(result, true);
      expect(
          mockLocus.methodCalls, contains('removePolygonGeofence:to-remove'));
    });

    test('getPolygonGeofences returns all polygons', () async {
      final polygon = PolygonGeofence(
        identifier: 'test',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      await Locus.geofencing.addPolygon(polygon);
      final polygons = await Locus.geofencing.getAllPolygons();

      expect(polygons.length, 1);
      expect(mockLocus.methodCalls, contains('getPolygonGeofences'));
    });

    test('polygonGeofenceExists checks existence', () async {
      final polygon = PolygonGeofence(
        identifier: 'exists-test',
        vertices: [
          const GeoPoint(latitude: 0, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 0),
          const GeoPoint(latitude: 1, longitude: 1),
        ],
      );

      expect(await Locus.geofencing.polygonExists('exists-test'), false);
      await Locus.geofencing.addPolygon(polygon);
      expect(await Locus.geofencing.polygonExists('exists-test'), true);
    });
  });
}
