/// Comprehensive tests for GeofenceService API.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import '../../helpers/helpers.dart';

void main() {
  group('GeofenceService', () {
    late MockLocus mockLocus;
    late GeofenceServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = GeofenceServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('events', () {
      test('should emit geofence crossing events', () async {
        final events = <GeofenceEvent>[];
        final sub = service.events.listen(events.add);

        final geofence = GeofenceFactory().named('test').at(37.0, -122.0).build();
        final event = GeofenceEvent(
          geofence: geofence,
          action: GeofenceAction.enter,
          location: LocationFactory().at(37.0, -122.0).build(),
        );

        mockLocus.emitGeofenceEvent(event);

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.action, GeofenceAction.enter);

        await sub.cancel();
      });
    });

    group('add', () {
      test('should add single geofence', () async {
        final geofence = GeofenceFactory()
            .named('office')
            .at(37.7749, -122.4194)
            .withRadius(100)
            .build();

        final result = await service.add(geofence);

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('addGeofence'));
      });

      test('should add geofence with custom settings', () async {
        final geofence = GeofenceFactory()
            .named('warehouse')
            .at(37.4219, -122.084)
            .withRadius(200)
            .notifyOnEntry()
            .notifyOnExit()
            .notifyOnDwell(delayMs: 300000)
            .build();

        final result = await service.add(geofence);

        expect(result, isTrue);
      });
    });

    group('addAll', () {
      test('should add multiple geofences', () async {
        final geofences = [
          GeofenceFactory().named('home').at(37.0, -122.0).build(),
          GeofenceFactory().named('work').at(37.1, -122.1).build(),
          GeofenceFactory().named('gym').at(37.2, -122.2).build(),
        ];

        final result = await service.addAll(geofences);

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('addGeofences'));
      });

      test('should handle empty list', () async {
        final result = await service.addAll([]);

        expect(result, isTrue);
      });
    });

    group('remove', () {
      test('should remove geofence by identifier', () async {
        final geofence = GeofenceFactory().named('test').at(37.0, -122.0).build();
        await service.add(geofence);

        final result = await service.remove('test');

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('removeGeofence'));
      });

      test('should return false for non-existent geofence', () async {
        final result = await service.remove('non-existent');

        expect(result, isFalse);
      });
    });

    group('removeAll', () {
      test('should remove all geofences', () async {
        await service.add(GeofenceFactory().named('g1').at(37.0, -122.0).build());
        await service.add(GeofenceFactory().named('g2').at(37.1, -122.1).build());

        final result = await service.removeAll();

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('removeGeofences'));
      });
    });

    group('getAll', () {
      test('should return all registered geofences', () async {
        final g1 = GeofenceFactory().named('home').at(37.0, -122.0).build();
        final g2 = GeofenceFactory().named('work').at(37.1, -122.1).build();

        await service.add(g1);
        await service.add(g2);

        final result = await service.getAll();

        expect(result.length, 2);
      });

      test('should return empty list when no geofences', () async {
        final result = await service.getAll();

        expect(result, isEmpty);
      });
    });

    group('get', () {
      test('should return geofence by identifier', () async {
        final geofence = GeofenceFactory().named('test').at(37.0, -122.0).build();
        await service.add(geofence);

        final result = await service.get('test');

        expect(result, isNotNull);
        expect(result?.identifier, 'test');
      });

      test('should return null for non-existent geofence', () async {
        final result = await service.get('non-existent');

        expect(result, isNull);
      });
    });

    group('exists', () {
      test('should return true for existing geofence', () async {
        final geofence = GeofenceFactory().named('test').at(37.0, -122.0).build();
        await service.add(geofence);

        final result = await service.exists('test');

        expect(result, isTrue);
      });

      test('should return false for non-existent geofence', () async {
        final result = await service.exists('non-existent');

        expect(result, isFalse);
      });
    });

    group('startMonitoring', () {
      test('should start geofence-only monitoring', () async {
        final result = await service.startMonitoring();

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('startGeofences'));
      });
    });

    group('polygon geofences', () {
      test('should add polygon geofence', () async {
        final polygon = PolygonGeofenceFactory()
            .named('campus')
            .addVertices([
              (37.42, -122.08),
              (37.43, -122.08),
              (37.43, -122.07),
              (37.42, -122.07),
            ])
            .build();

        final result = await service.addPolygon(polygon);

        expect(result, isTrue);
        expect(mockLocus.methodCalls, contains('addPolygonGeofence'));
      });

      test('should add multiple polygon geofences', () async {
        final polygons = [
          PolygonGeofenceFactory().named('zone1').addVertices([
            (37.0, -122.0),
            (37.01, -122.0),
            (37.01, -122.01),
          ]).build(),
          PolygonGeofenceFactory().named('zone2').addVertices([
            (37.1, -122.1),
            (37.11, -122.1),
            (37.11, -122.11),
          ]).build(),
        ];

        final count = await service.addPolygons(polygons);

        expect(count, 2);
      });

      test('should remove polygon geofence', () async {
        final polygon = PolygonGeofenceFactory().named('test').addVertices([
          (37.0, -122.0),
          (37.01, -122.0),
          (37.01, -122.01),
        ]).build();

        await service.addPolygon(polygon);
        final result = await service.removePolygon('test');

        expect(result, isTrue);
      });

      test('should remove all polygon geofences', () async {
        await service.addPolygon(
          PolygonGeofenceFactory().named('p1').addVertices([
            (37.0, -122.0),
            (37.01, -122.0),
            (37.0, -122.01),
          ]).build(),
        );

        await service.removeAllPolygons();

        expect(mockLocus.methodCalls, contains('removeAllPolygonGeofences'));
      });

      test('should get all polygon geofences', () async {
        await service.addPolygon(
          PolygonGeofenceFactory().named('poly1').addVertices([
            (37.0, -122.0),
            (37.01, -122.0),
            (37.0, -122.01),
          ]).build(),
        );

        final result = await service.getAllPolygons();

        expect(result, isA<List<PolygonGeofence>>());
      });
    });

    group('subscriptions', () {
      test('onGeofence should receive geofence events', () async {
        GeofenceEvent? received;
        final sub = service.onGeofence((event) {
          received = event;
        });

        final geofence = GeofenceFactory().named('test').at(37.0, -122.0).build();
        final event = GeofenceEvent(
          geofence: geofence,
          action: GeofenceAction.enter,
          location: LocationFactory().at(37.0, -122.0).build(),
        );

        mockLocus.emitGeofenceEvent(event);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received!.geofence.identifier, 'test');

        await sub.cancel();
      });

      test('should handle subscription errors', () async {
        Object? error;
        final sub = service.onGeofence(
          (_) {},
          onError: (e) => error = e,
        );

        await sub.cancel();
        expect(error, isNull);
      });
    });
  });
}
