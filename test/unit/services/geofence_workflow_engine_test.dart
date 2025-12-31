import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

GeofenceEvent _event(String id, GeofenceAction action) {
  return GeofenceEvent(
    geofence: Geofence(
      identifier: id,
      radius: 100,
      latitude: 0,
      longitude: 0,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: false,
    ),
    action: action,
  );
}

void main() {
  test('workflow enforces sequence', () async {
    final controller = StreamController<GeolocationEvent<dynamic>>();
    final engine = GeofenceWorkflowEngine(events: controller.stream);
    engine.registerWorkflows([
      const GeofenceWorkflow(
        id: 'workflow-1',
        steps: [
          GeofenceWorkflowStep(
            id: 'step-1',
            geofenceIdentifier: 'pickup',
            action: GeofenceAction.enter,
          ),
          GeofenceWorkflowStep(
            id: 'step-2',
            geofenceIdentifier: 'dropoff',
            action: GeofenceAction.enter,
          ),
        ],
      ),
    ]);
    engine.start();

    final events = <GeofenceWorkflowEvent>[];
    engine.events.listen(events.add);

    controller.add(GeolocationEvent<GeofenceEvent>(
      type: EventType.geofence,
      data: _event('dropoff', GeofenceAction.enter),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(events.first.status, GeofenceWorkflowStatus.violation);

    controller.add(GeolocationEvent<GeofenceEvent>(
      type: EventType.geofence,
      data: _event('pickup', GeofenceAction.enter),
    ));
    controller.add(GeolocationEvent<GeofenceEvent>(
      type: EventType.geofence,
      data: _event('dropoff', GeofenceAction.enter),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      events.any((event) => event.status == GeofenceWorkflowStatus.completed),
      true,
    );

    await controller.close();
    engine.dispose();
  });

  test('workflow enforces cooldown', () async {
    final controller = StreamController<GeolocationEvent<dynamic>>();
    final engine = GeofenceWorkflowEngine(events: controller.stream);
    engine.registerWorkflows([
      const GeofenceWorkflow(
        id: 'workflow-2',
        steps: [
          GeofenceWorkflowStep(
            id: 'step-1',
            geofenceIdentifier: 'pickup',
            action: GeofenceAction.enter,
            cooldownSeconds: 10,
          ),
        ],
      ),
    ]);
    engine.start();

    final events = <GeofenceWorkflowEvent>[];
    engine.events.listen(events.add);

    controller.add(GeolocationEvent<GeofenceEvent>(
      type: EventType.geofence,
      data: _event('pickup', GeofenceAction.enter),
    ));
    controller.add(GeolocationEvent<GeofenceEvent>(
      type: EventType.geofence,
      data: _event('pickup', GeofenceAction.enter),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      events.any((event) => event.status == GeofenceWorkflowStatus.violation),
      true,
    );

    await controller.close();
    engine.dispose();
  });
}
