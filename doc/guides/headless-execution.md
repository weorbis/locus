# Headless Execution Guide

Last updated: January 7, 2026

Run Locus logic when the app is terminated or backgrounded using headless callbacks.

## Lifecycle overview
- Platform wakes a background isolate on eligible events (location, geofence, heartbeat, sync).
- Your registered top-level callback executes; no UI is available.
- Process may be killed at any time; keep work short and resilient.

## Requirements
- Register a **top-level or static** function (no closures/instance methods).
- Add `@pragma('vm:entry-point')` to prevent tree shaking.
- Do not access Widgets or BuildContext; use pure Dart code and lightweight I/O.

## Setup

```dart
// main.dart
@pragma('vm:entry-point')
Future<void> locusHeadlessCallback(HeadlessEvent event) async {
  try {
    switch (event.type) {
      case HeadlessEventType.location:
        final loc = event.location;
        // e.g., enqueue for later sync
        break;
      case HeadlessEventType.geofence:
        // e.g., persist geofence transition
        break;
      case HeadlessEventType.sync:
        // inspect sync result, adjust policy if needed
        break;
      case HeadlessEventType.heartbeat:
        // optional lightweight health signal
        break;
    }
  } catch (e, st) {
    // Log defensively; avoid throws
    // e.g., await HeadlessLogger.log('$e\n$st');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Locus.registerHeadlessCallback(locusHeadlessCallback);
  runApp(const MyApp());
}
```

## Best practices
- Keep callbacks under a few hundred milliseconds; offload heavy work to queued tasks.
- Guard every branch with try/catch; never let exceptions escape.
- Avoid network calls when offline; enqueue instead.
- Respect user consent: skip work if permissions or policy are revoked.
- Test on real devices; emulators may suspend differently.

## Validation checklist
- Kill the app, trigger a geofence or heartbeat, and verify the callback logs.
- Confirm no crashes in headless logs and that queued data appears on next foreground launch.
- On Android, ensure the foreground service notification is configured so headless can run reliably.

## Process lifecycle guarantees

Locus honors three independent lifecycle guarantees when the canonical always-on
configuration is used (`stopOnTerminate: false`, `enableHeadless: true`,
`foregroundService: true`):

| Event | What happens |
|---|---|
| User swipes the app away from recents | The Flutter UI engine is destroyed, but the Android foreground service and iOS CoreLocation subscription stay alive. Location events continue to flow; headless callbacks fire in place of the (now gone) UI event sink. On the next app launch, `Locus.isTracking()` returns `true` without any Dart-side re-start. |
| User force-stops the app (or the OS reaps the background process) | The foreground service is killed with the process. The persisted `bg_tracking_active` flag remains `true`. On the next attach (manual launch, boot receiver, or iOS significant-location-change relaunch) Locus automatically re-arms tracking if location permission is still granted. If the user revoked permission, the flag is cleared and no silent retry loop runs. |
| App relaunches while the service is still running (swipe-away case) | The new Flutter engine attaches; the plugin detects the soft-detached primary and transfers ownership of the native managers to the new plugin instance, rebinding all listeners. No duplicate subscriptions are created; no events are lost. |

If you rely on the opposite behavior — *stop tracking when the user swipes the app
away* — set `stopOnTerminate: true`. That path calls `stopTracking()` explicitly,
which stops the foreground service (via `context.stopService`) and clears the
persisted flag in the same atomic step.

### OEM caveats

Aggressive task killers on Samsung One UI, Xiaomi MIUI, and Huawei EMUI may still
reap the foreground service outside the Android contract. Use
`PermissionAssistant.requestBackgroundWorkflow` to steer the user through OEM
battery-optimization exemptions; see `doc/guides/permissions.md`.
