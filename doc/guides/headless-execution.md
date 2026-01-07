# Headless Execution Guide

Last updated: January 7, 2026

Run Locus logic when the app process is killed or in the background using headless callbacks.

## When headless runs
- Location events, geofence events, sync retries, and heartbeat events can trigger headless handlers.
- Platform invokes the registered top-level callback in a background isolate.

## Requirements
- Register a **top-level or static** function (closures are not supported).
- Avoid UI work; perform lightweight logic (queue, log, notify server).
- Keep work short to satisfy platform watchdogs.

## Setup

```dart
// main.dart
void locusHeadlessCallback(HeadlessEvent event) async {
  switch (event.type) {
    case HeadlessEventType.location:
      final location = event.location;
      // Process or enqueue
      break;
    case HeadlessEventType.geofence:
      // Handle geofence action
      break;
    case HeadlessEventType.sync:
      // Inspect sync results
      break;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Locus.registerHeadlessCallback(locusHeadlessCallback);
  runApp(const MyApp());
}
```

## Best practices
- Minimize CPU/network usage; prefer enqueueing work for foreground processing.
- Guard against missing permissions or disabled services.
- Use try/catch around all async calls; log errors.
- Avoid blocking the callback; return promptly after scheduling work.

## Validation
- Simulate app termination, then trigger a geofence/heartbeat to confirm callback fires.
- Check logs for headless execution and ensure no uncaught exceptions.
