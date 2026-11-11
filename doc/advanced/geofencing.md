# Geofencing

Locus provides a high-performance native geofencing system that can receive
OS-eligible events while the Flutter UI engine is absent or the app is in the
background. Android force-stop and iOS user force-quit remain platform-owned
stop boundaries. Locus supports both **circular geofences** (radius-based) and
**polygon geofences** (arbitrary shapes).

## Circular Geofences

### Adding a Geofence

You can add geofences at any time, even before starting the main tracking service.

```dart
await Locus.geofencing.add(const Geofence(
  identifier: 'office_zone',
  radius: 100, // meters
  latitude: 37.7749,
  longitude: -122.4194,
  notifyOnEntry: true,
  notifyOnExit: true,
  notifyOnDwell: true,
  loiteringDelay: 30000, // 30 seconds for dwell
));
```

### Listening to Events

Geofence events are delivered via the geofencing events stream.

```dart
Locus.geofencing.events.listen((event) {
  print('Geofence ${event.geofence.identifier}: ${event.action}');
});
```

### Event Object

The `GeofenceEvent` provides:

- `geofence.identifier`: The unique ID you assigned.
- `action`: `enter`, `exit`, or `dwell`.
- `location`: The location that triggered the event.

### Removing Geofences

```dart
// Remove by ID
await Locus.geofencing.remove('office_zone');

// Remove all
await Locus.geofencing.removeAll();
```

---

## Polygon Geofences

For complex boundaries like campus areas, delivery zones, or property lines, use polygon geofences.

### Adding a Polygon Geofence

Define the boundary with a list of vertices (minimum 3 points):

```dart
await Locus.geofencing.addPolygon(PolygonGeofence(
  identifier: 'campus_boundary',
  vertices: [
    GeoPoint(latitude: 37.7749, longitude: -122.4194),
    GeoPoint(latitude: 37.7759, longitude: -122.4184),
    GeoPoint(latitude: 37.7769, longitude: -122.4204),
    GeoPoint(latitude: 37.7739, longitude: -122.4214),
  ],
  extras: {'name': 'Main Campus', 'type': 'restricted'},
));
```

### Listening to Polygon Events

```dart
Locus.geofencing.polygonEvents.listen((event) {
  print('Polygon ${event.geofence.identifier}: ${event.type}');
  // event.type is PolygonGeofenceEventType.enter or .exit
  // event.triggerLocation is the triggering location
});
```

### Managing Polygon Geofences

```dart
// Get all polygon geofences
final polygons = await Locus.geofencing.getAllPolygons();

// Check if a polygon exists
final exists = await Locus.geofencing.polygonExists('campus_boundary');

// Remove a polygon
await Locus.geofencing.removePolygon('campus_boundary');

// Remove all polygons
await Locus.geofencing.removeAllPolygons();
```

### Point-in-Polygon Detection

You can manually check if a point is inside any polygon:

```dart
final service = PolygonGeofenceService();
final isInside = service.isLocationInAnyPolygon(37.7755, -122.4190);

// Or get all containing polygons
final containing = service.getContainingPolygons(37.7755, -122.4190);
```

### Polygon Validation

Polygons are validated on creation:

- Minimum 3 vertices required
- Vertices must form a valid polygon (no self-intersections)
- Coordinates must be valid lat/lng values

```dart
// Check if a polygon is valid before adding
final polygon = PolygonGeofence(...);
if (polygon.isValid) {
  await Locus.geofencing.addPolygon(polygon);
}
```

---

## Platform Limitations

### iOS Geofence Limit

iOS enforces a **hard limit of 20 monitored circular regions** per app. This is a platform restriction from Apple's Core Location framework.

When you exceed this limit, Locus will automatically:
1. Remove the oldest geofences to stay within the limit
2. Emit a `geofenceschange` event with the removed identifiers
3. Log a warning message

**Recommendations:**
- For applications needing more than 20 zones, use **Polygon Geofences** instead (unlimited, processed in Dart)
- Implement dynamic geofence loading based on user location
- Consider using the `Config.maxMonitoredGeofences` setting to control the limit

```dart
await Locus.ready(Config(
  maxMonitoredGeofences: 15, // Leave room for other regions
  // ...
));
```

### Android Geofence Limit

Android has a higher limit (typically 100 geofences per app), but this may vary by device manufacturer.

---

## Geofence Workflows

For complex geofence-based logic (e.g., "enter zone A, then zone B within 5 minutes"), use the workflow engine:

```dart
final workflow = GeofenceWorkflow(
  id: 'check_in_flow',
  steps: [
    GeofenceWorkflowStep(
      id: 'step-1',
      geofenceIdentifier: 'entrance',
      action: GeofenceAction.enter,
    ),
    GeofenceWorkflowStep(
      id: 'step-2',
      geofenceIdentifier: 'check_in_desk',
      action: GeofenceAction.dwell,
      cooldownSeconds: 300,
    ),
  ],
);

Locus.geofencing.registerWorkflows([workflow]);

Locus.geofencing.workflowEvents.listen((event) {
  if (event.status == GeofenceWorkflowStatus.completed) {
    print('Check-in flow completed!');
  }
});
```

---

### Workflow persistence

When using `GeofenceWorkflowEngine` directly, pass a `WorkflowStateStore` to
save progress after each completed step, and call `loadState()` after
registering workflows to restore it.

Saves run one at a time. Requests made while a save is running collapse into
one, which writes the newest state. `dispose()` waits for that final save.
A failed save is logged as `workflow_state_save_failed` under
`locus.geofence_workflow` and is not retried.

**Next:** [Privacy Zones](privacy-zones.md)
