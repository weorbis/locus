# Event Streams Reference

Last updated: January 7, 2026

Guide to primary streams, when they emit, and how to consume them safely.

## Streams and emission rules
- `Locus.location.stream` — All location updates (moving and stationary).
- `Locus.location.motionChanges` — Emits when motion toggles (stationary ↔ moving).
- `Locus.location.heartbeats` — Periodic while stationary.
- `Locus.geofencing.events` — Geofence enter/exit/dwell.
- `Locus.geofencing.polygonEvents` — Polygon geofence transitions.
- `Locus.trips.events` — Trip lifecycle (start/update/stop).
- `Locus.battery.powerStateEvents` — Power state changes (charging/low/critical).
- `Locus.dataSync.httpEvents` — Sync attempts/results.

## Subscription best practices
- Store subscriptions and cancel in `dispose`/tearDown.
- Use `takeUntil`/`cancel` on navigation to prevent leaks.
- Debounce or buffer if UI does not need every location.
- Provide `onError` to avoid silent stream failures.
- Headless: register top-level/static handlers only.

## Location simulation fields

`Location.isMockProvider` is the OS-reported simulation flag (Android API 26+ via
`isMock`/`isFromMockProvider`,
iOS 15+), `null` when unreported. It is separate from `isMock`, which spoof
detection sets. Android history read from SQLite returns `null`; iOS history
keeps the flag. See [spoof detection](../guides/faq.md#can-i-detect-if-location-is-spoofedmocked).

## Expected frequencies
- Locations: driven by `distanceFilter`, `desiredAccuracy`, and motion state.
- Motion changes: on state transitions.
- Heartbeats: every `heartbeatInterval` while stationary.
- Geofences: on platform-detected boundary crossings.
- HTTP events: per sync attempt (success/failure).

## Error handling
- Log non-fatal errors; decide whether to retry or ignore.
- If a stream closes unexpectedly, re-subscribe after confirming `Locus.start()` is active.

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
