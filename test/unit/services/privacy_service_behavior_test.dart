import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('PrivacyService behavior', () {
    late MockLocus mockLocus;
    late PrivacyServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = PrivacyServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('events emit add and remove changes', () async {
      final events = <PrivacyZoneEvent>[];
      final sub = service.events.listen(events.add);

      final zone = PrivacyZone.create(
        identifier: 'home',
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
      );

      await service.add(zone);
      await service.remove('home');

      await Future.delayed(Duration.zero);
      expect(events.length, 2);
      expect(events[0].type, PrivacyZoneEventType.added);
      expect(events[1].type, PrivacyZoneEventType.removed);

      await sub.cancel();
    });

    test('exclude zones drop locations', () async {
      final zone = PrivacyZone.create(
        identifier: 'private',
        latitude: 37.0,
        longitude: -122.0,
        radius: 500.0,
        action: PrivacyZoneAction.exclude,
      );

      await service.add(zone);

      final location = MockLocationExtension.mock(
        latitude: 37.0,
        longitude: -122.0,
      );
      final result = mockLocus.processLocationThroughPrivacyZones(location);

      expect(result.wasExcluded, isTrue);
      expect(result.processedLocation, isNull);
    });

    test('disabling a zone makes locations usable again', () async {
      final zone = PrivacyZone.create(
        identifier: 'obfuscate',
        latitude: 37.0,
        longitude: -122.0,
        radius: 500.0,
        action: PrivacyZoneAction.obfuscate,
      );

      await service.add(zone);
      await service.setEnabled('obfuscate', false);

      final location = MockLocationExtension.mock(
        latitude: 37.0,
        longitude: -122.0,
      );
      final result = mockLocus.processLocationThroughPrivacyZones(location);

      expect(result.wasAffected, isFalse);
      expect(result.isUsable, isTrue);
      expect(result.processedLocation, isNotNull);
    });
  });
}
