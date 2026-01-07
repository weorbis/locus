# Event Streams Reference

Last updated: January 7, 2026

Quick guide to the primary streams exposed by Locus, when they emit, and how to consume them safely.

## Streams and emission rules

- `Locus.location.stream` — All location updates (moving and stationary). Emits after every processed fix.
- `Locus.location.motionChanges` — Emits when motion state toggles (stationary ↔ moving).
- `Locus.location.heartbeats` — Emits periodic heartbeat locations while stationary.
- `Locus.geofencing.events` — Emits geofence enter/exit/dwell events.
- `Locus.geofencing.polygonEvents` — Emits polygon geofence transitions.
- `Locus.trips.events` — Emits trip lifecycle events (start/update/stop).
- `Locus.battery.powerStateEvents` — Emits power state changes (charging/low/critical).
- `Locus.dataSync.httpEvents` — Emits sync attempts and results.

## Subscription best practices

- Store subscriptions and cancel them in `dispose`/teardown to avoid leaks.
- Prefer `takeUntil` or manual cancellation when leaving screens.
- Use `debounce` or buffering if UI does not need every location.
- Handle errors: `stream.listen(onData, onError: ...)` to avoid silent failures.
- In headless mode, only register top-level/static callbacks.

## Expected frequencies

- Locations: depends on `distanceFilter`, `desiredAccuracy`, and motion state.
- Motion changes: only on state transition.
- Heartbeats: every `heartbeatInterval` while stationary.
- Geofences: on boundary crossings (enter/exit/dwell) based on platform detection.
- HTTP events: per sync attempt (success/failure).

## Error handling

- Streams may surface platform errors; log and continue when non-fatal.
- If a stream completes unexpectedly, re-subscribe after ensuring `Locus.start()` is active.

## Sample usage

```dart
late final StreamSubscription<Location> _sub;

void initState() {
  super.initState();
  _sub = Locus.location.stream.listen(
    (loc) => debugPrint('Location ${loc.coords.latitude}, ${loc.coords.longitude}'),
    onError: (err, st) => debugPrint('Location stream error: $err'),
  );
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```
