import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('PrivacyZone', () {
    test('can be created with required parameters', () {
      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      expect(zone.identifier, 'home');
      expect(zone.latitude, 37.7749);
      expect(zone.longitude, -122.4194);
      expect(zone.radius, 100.0);
      expect(zone.action, PrivacyZoneAction.obfuscate);
      expect(zone.obfuscationRadius, 500.0);
      expect(zone.enabled, true);
    });

    test('can be created with exclude action', () {
      final zone = PrivacyZone.create(
        identifier: 'work',
        latitude: 37.7849,
        longitude: -122.4094,
        radius: 50.0,
        action: PrivacyZoneAction.exclude,
      );

      expect(zone.action, PrivacyZoneAction.exclude);
    });

    test('isValid returns true for valid zone', () {
      final zone = PrivacyZone.create(
        identifier: 'test',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      expect(zone.isValid, true);
    });

    test('isValid returns false for empty identifier', () {
      final zone = PrivacyZone.create(
        identifier: '',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      expect(zone.isValid, false);
    });

    test('isValid returns false for invalid latitude', () {
      final zone = PrivacyZone.create(
        identifier: 'test',
        latitude: 95.0, // Invalid
        longitude: -122.4194,
        radius: 100.0,
      );

      expect(zone.isValid, false);
    });

    test('isValid returns false for zero radius', () {
      final zone = PrivacyZone.create(
        identifier: 'test',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 0.0,
      );

      expect(zone.isValid, false);
    });

    test('containsLocation returns true for point inside zone', () {
      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      // Point very close to center
      expect(zone.containsLocation(37.7749, -122.4194), true);
      expect(zone.containsLocation(37.77495, -122.41945), true);
    });

    test('containsLocation returns false for point outside zone', () {
      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      // Point far away
      expect(zone.containsLocation(37.78, -122.42), false);
    });

    test('serializes to map correctly', () {
      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
        action: PrivacyZoneAction.obfuscate,
        obfuscationRadius: 300.0,
        label: 'Home Zone',
      );

      final map = zone.toMap();

      expect(map['identifier'], 'home');
      expect(map['latitude'], 37.7749);
      expect(map['longitude'], -122.4194);
      expect(map['radius'], 100.0);
      expect(map['action'], 'obfuscate');
      expect(map['obfuscationRadius'], 300.0);
      expect(map['label'], 'Home Zone');
      expect(map['enabled'], true);
    });

    test('deserializes from map correctly', () {
      final map = {
        'identifier': 'work',
        'latitude': 37.7849,
        'longitude': -122.4094,
        'radius': 50.0,
        'action': 'exclude',
        'enabled': false,
        'createdAt': '2024-01-01T00:00:00.000Z',
      };

      final zone = PrivacyZone.fromMap(map);

      expect(zone.identifier, 'work');
      expect(zone.latitude, 37.7849);
      expect(zone.action, PrivacyZoneAction.exclude);
      expect(zone.enabled, false);
    });

    test('copyWith creates modified copy', () {
      final original = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      final modified = original.copyWith(
        radius: 200.0,
        enabled: false,
      );

      expect(modified.identifier, 'home'); // Unchanged
      expect(modified.radius, 200.0);
      expect(modified.enabled, false);
      expect(modified.updatedAt, isNotNull);
    });

    test('equality is based on identifier', () {
      final zone1 = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      final zone2 = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.0, // Different coords
        longitude: -122.0,
        radius: 200.0,
      );

      expect(zone1, equals(zone2));
      expect(zone1.hashCode, equals(zone2.hashCode));
    });
  });

  group('PrivacyZoneResult', () {
    test('wasAffected returns true when excluded', () {
      final location = _createTestLocation();
      final result = PrivacyZoneResult(
        originalLocation: location,
        processedLocation: null,
        wasExcluded: true,
      );

      expect(result.wasAffected, true);
      expect(result.isUsable, false);
    });

    test('wasAffected returns true when obfuscated', () {
      final location = _createTestLocation();
      final result = PrivacyZoneResult(
        originalLocation: location,
        processedLocation: location,
        wasObfuscated: true,
      );

      expect(result.wasAffected, true);
      expect(result.isUsable, true);
    });

    test('wasAffected returns false when not affected', () {
      final location = _createTestLocation();
      final result = PrivacyZoneResult(
        originalLocation: location,
        processedLocation: location,
      );

      expect(result.wasAffected, false);
      expect(result.isUsable, true);
    });
  });

  group('PrivacyZoneService', () {
    late PrivacyZoneService service;

    setUp(() {
      service = PrivacyZoneService(seed: 42); // Deterministic for testing
    });

    tearDown(() async {
      await service.dispose();
    });

    group('zone management', () {
      test('addZone adds a new zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        );

        await service.addZone(zone);

        expect(service.zoneCount, 1);
        expect(service.hasZone('home'), true);
      });

      test('addZone throws for invalid zone', () async {
        final zone = PrivacyZone.create(
          identifier: '', // Invalid
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        );

        expect(() => service.addZone(zone), throwsArgumentError);
      });

      test('addZones adds multiple zones', () async {
        final zones = [
          PrivacyZone.create(
            identifier: 'home',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100.0,
          ),
          PrivacyZone.create(
            identifier: 'work',
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 50.0,
          ),
        ];

        await service.addZones(zones);

        expect(service.zoneCount, 2);
      });

      test('removeZone removes existing zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        final result = await service.removeZone('home');

        expect(result, true);
        expect(service.zoneCount, 0);
      });

      test('removeZone returns false for non-existent zone', () async {
        final result = await service.removeZone('non-existent');
        expect(result, false);
      });

      test('removeAllZones clears all zones', () async {
        await service.addZones([
          PrivacyZone.create(
            identifier: 'home',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100.0,
          ),
          PrivacyZone.create(
            identifier: 'work',
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 50.0,
          ),
        ]);

        await service.removeAllZones();

        expect(service.zoneCount, 0);
      });

      test('getZone returns zone by identifier', () async {
        final zone = PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        );

        await service.addZone(zone);

        final retrieved = service.getZone('home');
        expect(retrieved?.identifier, 'home');
      });

      test('updateZone updates existing zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        final updated = service.getZone('home')!.copyWith(radius: 200.0);
        final result = await service.updateZone(updated);

        expect(result, true);
        expect(service.getZone('home')?.radius, 200.0);
      });

      test('setZoneEnabled enables/disables zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        await service.setZoneEnabled('home', false);

        expect(service.getZone('home')?.enabled, false);
        expect(service.enabledZones.length, 0);

        await service.setZoneEnabled('home', true);

        expect(service.getZone('home')?.enabled, true);
        expect(service.enabledZones.length, 1);
      });
    });

    group('location processing', () {
      test('processLocation returns unmodified for location outside zones',
          () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        // Location far from the zone
        final location = _createTestLocation(latitude: 38.0, longitude: -123.0);
        final result = service.processLocation(location);

        expect(result.wasAffected, false);
        expect(result.processedLocation, equals(location));
        expect(result.matchedZones, isEmpty);
      });

      test('processLocation excludes location in exclude zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
          action: PrivacyZoneAction.exclude,
        ));

        final location = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final result = service.processLocation(location);

        expect(result.wasExcluded, true);
        expect(result.processedLocation, isNull);
        expect(result.matchedZones.length, 1);
      });

      test('processLocation obfuscates location in obfuscate zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
          action: PrivacyZoneAction.obfuscate,
          obfuscationRadius: 500.0,
        ));

        final location = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final result = service.processLocation(location);

        expect(result.wasObfuscated, true);
        expect(result.processedLocation, isNotNull);
        expect(result.processedLocation!.coords.latitude,
            isNot(equals(location.coords.latitude)));
        expect(result.processedLocation!.extras?['_privacyObfuscated'], true);
      });

      test('exclude action takes precedence over obfuscate', () async {
        // Overlapping zones with different actions
        await service.addZones([
          PrivacyZone.create(
            identifier: 'obfuscate-zone',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 200.0,
            action: PrivacyZoneAction.obfuscate,
          ),
          PrivacyZone.create(
            identifier: 'exclude-zone',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100.0,
            action: PrivacyZoneAction.exclude,
          ),
        ]);

        final location = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final result = service.processLocation(location);

        expect(result.wasExcluded, true);
        expect(result.wasObfuscated, false);
      });

      test('processLocation respects disabled zones', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
          action: PrivacyZoneAction.exclude,
          enabled: false,
        ));

        final location = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final result = service.processLocation(location);

        expect(result.wasAffected, false);
      });

      test('processLocations filters out excluded locations', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
          action: PrivacyZoneAction.exclude,
        ));

        final locations = [
          _createTestLocation(
              latitude: 37.7749, longitude: -122.4194), // Inside
          _createTestLocation(latitude: 38.0, longitude: -123.0), // Outside
          _createTestLocation(
              latitude: 37.7749, longitude: -122.4194), // Inside
        ];

        final processed = service.processLocations(locations);

        expect(processed.length, 1); // Only the outside location
        expect(processed[0].coords.latitude, 38.0);
      });

      test('isLocationAffected returns true for location in zone', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        final inside = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final outside = _createTestLocation(latitude: 38.0, longitude: -123.0);

        expect(service.isLocationAffected(inside), true);
        expect(service.isLocationAffected(outside), false);
      });

      test('getMatchingZones returns all matching zones', () async {
        await service.addZones([
          PrivacyZone.create(
            identifier: 'zone1',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100.0,
          ),
          PrivacyZone.create(
            identifier: 'zone2',
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 200.0,
          ),
          PrivacyZone.create(
            identifier: 'zone3',
            latitude: 38.0,
            longitude: -123.0,
            radius: 100.0,
          ),
        ]);

        final location = _createTestLocation(
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final matching = service.getMatchingZones(location);

        expect(matching.length, 2);
        expect(
            matching.map((z) => z.identifier), containsAll(['zone1', 'zone2']));
      });
    });

    group('events', () {
      test('emits event when zone is added', () async {
        final events = <PrivacyZoneEvent>[];
        service.zoneChanges.listen(events.add);

        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        await Future.delayed(Duration.zero);

        expect(events.length, 1);
        expect(events[0].type, PrivacyZoneEventType.added);
        expect(events[0].zone.identifier, 'home');
      });

      test('emits event when zone is removed', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        final events = <PrivacyZoneEvent>[];
        service.zoneChanges.listen(events.add);

        await service.removeZone('home');

        await Future.delayed(Duration.zero);

        expect(events.length, 1);
        expect(events[0].type, PrivacyZoneEventType.removed);
      });

      test('emits event when zone is updated', () async {
        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        final events = <PrivacyZoneEvent>[];
        service.zoneChanges.listen(events.add);

        await service.setZoneEnabled('home', false);

        await Future.delayed(Duration.zero);

        expect(events.length, 1);
        expect(events[0].type, PrivacyZoneEventType.updated);
      });
    });

    group('persistence callback', () {
      test('calls onPersist when zones change', () async {
        final persisted = <List<PrivacyZone>>[];
        final service = PrivacyZoneService(
          onPersist: (zones) async => persisted.add(zones),
        );

        await service.addZone(PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        ));

        expect(persisted.length, 1);
        expect(persisted[0].length, 1);

        await service.dispose();
      });
    });
  });

  group('Locus privacy zone API', () {
    late MockLocus mock;

    setUp(() {
      mock = MockLocus();
      Locus.setMockInstance(mock);
    });

    tearDown(() {
      Locus.setMockInstance(MockLocus());
    });

    test('addPrivacyZone adds a zone', () async {
      await Locus.privacy.add(PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      ));

      final zones = await Locus.privacy.getAll();
      expect(zones.length, 1);
      expect(mock.methodCalls, contains('addPrivacyZone:home'));
    });

    test('removePrivacyZone removes a zone', () async {
      await Locus.privacy.add(PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      ));

      final result = await Locus.privacy.remove('home');
      expect(result, true);

      final zones = await Locus.privacy.getAll();
      expect(zones.length, 0);
    });

    test('getPrivacyZone retrieves specific zone', () async {
      await Locus.privacy.add(PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      ));

      final zone = await Locus.privacy.get('home');
      expect(zone?.identifier, 'home');
    });

    test('setPrivacyZoneEnabled toggles zone', () async {
      await Locus.privacy.add(PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      ));

      await Locus.privacy.setEnabled('home', false);

      final zone = await Locus.privacy.get('home');
      expect(zone?.enabled, false);
    });
  });
}

Location _createTestLocation({
  double latitude = 37.7749,
  double longitude = -122.4194,
}) {
  return Location(
    uuid: 'test-${DateTime.now().millisecondsSinceEpoch}',
    timestamp: DateTime.now(),
    coords: Coords(
      latitude: latitude,
      longitude: longitude,
      accuracy: 10.0,
    ),
  );
}
