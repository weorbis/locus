# Diagnostics & Debugging

## Overview

The Diagnostics feature provides comprehensive debugging, logging, and error recovery tools for troubleshooting Locus behavior in development and production.

## Key Features

- **Error Logging**: Track all SDK errors with stack traces
- **Performance Metrics**: Monitor tracking quality and battery impact
- **Recovery Strategies**: Automatic error recovery and state restoration
- **Debug Overlay**: Visual debugging widget for development
- **Event Inspection**: View raw platform events for debugging

## Using the Debug Overlay

The Debug Overlay provides real-time visibility into SDK state:

```dart
import 'package:locus/locus.dart';

// In your MaterialApp or scaffold
@override
Widget build(BuildContext context) {
  return Stack(
    children: [
      // Your app content
      MyApp(),
      
      // Add debug overlay
      if (kDebugMode)
        const LocusDebugOverlay(),
    ],
  );
}
```

## Accessing Diagnostics

```dart
// Get current diagnostics snapshot
final diagnostics = await Locus.getDiagnostics();
print('Captured at: ${diagnostics.capturedAt}');
print('Queue size: ${diagnostics.queue.length}');

// Log entries
final logs = await Locus.getLog();
print('Log entries: ${logs.length}');
```

## Reliability Events And Metrics

For production monitoring, subscribe to `Locus.reliability` and snapshot `Locus.metrics`. Reliability events are intended for alerting and incident timelines; metrics are counters you can send to dashboards.

```dart
final reliabilitySub = Locus.reliability.listen((event) {
  switch (event) {
    case SyncStalled():
      reportWarning('locus_sync_stalled', event.toString());
    case SyncUnrecoverable():
      reportCritical('locus_sync_unrecoverable', event.toString());
    case QuarantineGrew():
      reportWarning('locus_quarantine_grew', event.toString());
    default:
      reportInfo('locus_reliability', event.toString());
  }
});

final metrics = await Locus.metrics.snapshot();
print(metrics.toJson());
```

The SDK also emits `tracking_heartbeat` structured log entries while active. These include pending, sent, dropped, quarantined, pause-state, and last-success-age fields, which are useful for detecting silent stops.

`Locus.reliability` and `Locus.metrics` are per Dart isolate. Foreground UI subscriptions do not automatically receive events emitted from a headless isolate; use the structured logs for cross-isolate monitoring.

## Error Recovery

Locus automatically attempts to recover from errors:

```dart
Locus.setErrorHandler(ErrorRecoveryConfig(
  onError: (error, context) {
    return error.suggestedRecovery ?? RecoveryAction.retry;
  },
  maxRetries: 3,
  retryDelay: Duration(seconds: 5),
));

// Listen for error events
Locus.errorRecoveryManager?.errors.listen((error) {
  print('Error: ${error.type.name} - ${error.message}');
});
```

## Logging Configuration

Control verbosity of logs:

```dart
await Locus.setConfig(const Config(
  logLevel: LogLevel.debug, // verbose, debug, info, warning, error
));
```

**Next:** [Advanced Configuration](../core/configuration.md)
