/// Comprehensive tests for PrivacyService API.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('PrivacyService', () {
    late MockLocus mockLocus;
    late PrivacyServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = PrivacyServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('add', () {
      test('should add privacy zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'home',
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 100.0,
        );

        await service.add(zone);

        expect(mockLocus.methodCalls, contains('addPrivacyZone'));
      });

      test('should add obfuscation zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'office',
          latitude: 37.4219,
          longitude: -122.084,
          radius: 200.0,
          action: PrivacyZoneAction.obfuscate,
          obfuscationRadius: 500.0,
        );

        await service.add(zone);

        expect(mockLocus.methodCalls, contains('addPrivacyZone'));
      });

      test('should add exclude zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'private',
          latitude: 40.7580,
          longitude: -73.9855,
          radius: 300.0,
          action: PrivacyZoneAction.exclude,
        );

        await service.add(zone);

        expect(mockLocus.methodCalls, contains('addPrivacyZone'));
      });
    });

    group('addAll', () {
      test('should add multiple privacy zones', () async {
        final zones = [
          PrivacyZone.create(
            identifier: 'home',
            latitude: 37.0,
            longitude: -122.0,
            radius: 100.0,
          ),
          PrivacyZone.create(
            identifier: 'work',
            latitude: 37.1,
            longitude: -122.1,
            radius: 150.0,
          ),
        ];

        await service.addAll(zones);

        expect(mockLocus.methodCalls, contains('addPrivacyZones'));
      });
    });

    group('remove', () {
      test('should remove privacy zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        );
        await service.add(zone);

        final result = await service.remove('test');

        expect(result, isTrue);
      });

      test('should return false for non-existent zone', () async {
        final result = await service.remove('non-existent');

        expect(result, isFalse);
      });
    });

    group('removeAll', () {
      test('should remove all zones', () async {
        await service.add(PrivacyZone.create(
          identifier: 'z1',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        ));

        await service.removeAll();

        expect(mockLocus.methodCalls, contains('removeAllPrivacyZones'));
      });
    });

    group('get', () {
      test('should return zone by identifier', () async {
        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        );
        await service.add(zone);

        final result = await service.get('test');

        expect(result, isNotNull);
      });

      test('should return null for non-existent zone', () async {
        final result = await service.get('non-existent');

        expect(result, isNull);
      });
    });

    group('getAll', () {
      test('should return all privacy zones', () async {
        await service.add(PrivacyZone.create(
          identifier: 'z1',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        ));
        await service.add(PrivacyZone.create(
          identifier: 'z2',
          latitude: 37.1,
          longitude: -122.1,
          radius: 100.0,
        ));

        final result = await service.getAll();

        expect(result.length, 2);
      });
    });

    group('setEnabled', () {
      test('should enable zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
          enabled: false,
        );
        await service.add(zone);

        final result = await service.setEnabled('test', true);

        expect(result, isTrue);
      });

      test('should disable zone', () async {
        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        );
        await service.add(zone);

        final result = await service.setEnabled('test', false);

        expect(result, isTrue);
      });
    });

    group('events', () {
      test('should emit zone added events', () async {
        final events = <PrivacyZoneEvent>[];
        final sub = service.events.listen(events.add);

        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        );
        await service.add(zone);

        await Future.delayed(Duration.zero);

        expect(events, isNotEmpty);

        await sub.cancel();
      });
    });

    group('subscriptions', () {
      test('onChange should receive events', () async {
        PrivacyZoneEvent? received;
        final sub = service.onChange((event) {
          received = event;
        });

        final zone = PrivacyZone.create(
          identifier: 'test',
          latitude: 37.0,
          longitude: -122.0,
          radius: 100.0,
        );
        await service.add(zone);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);

        await sub.cancel();
      });
    });
  });
}
