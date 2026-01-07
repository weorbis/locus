import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('applies profile based on speed rule', () async {
    final controller = StreamController<GeolocationEvent<dynamic>>();
    Config? applied;

    final manager = TrackingProfileManager(
      applyConfig: (config) async {
        applied = config;
      },
      events: controller.stream,
    );

    manager.setProfiles({
      TrackingProfile.enRoute: const Config(distanceFilter: 10),
      TrackingProfile.standby: const Config(distanceFilter: 100),
    });
    manager.setRules([
      const TrackingProfileRule(
        profile: TrackingProfile.enRoute,
        type: TrackingProfileRuleType.speedAbove,
        speedKph: 5,
        cooldownSeconds: 0,
      ),
    ]);
    await manager.startAutomation();

    final location = Location(
      uuid: '1',
      timestamp: DateTime.utc(2025, 1, 1),
      coords: const Coords(
        latitude: 0,
        longitude: 0,
        accuracy: 5,
        speed: 3,
      ),
    );

    controller.add(GeolocationEvent<Location>(
      type: EventType.location,
      data: location,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(applied?.distanceFilter, 10);

    await controller.close();
    await manager.dispose();
  });
}
