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
        DebugOverlay(),
    ],
  );
}
```

## Accessing Diagnostics

```dart
// Get current diagnostics snapshot
final diagnostics = await Locus.diagnostics.snapshot();

// Log entries
print('Error count: ${diagnostics.errorCount}');
print('Last errors: ${diagnostics.lastErrors}');

// Listen to diagnostic events
Locus.diagnostics.onEvent((event) {
  print('${event.level}: ${event.message}');
});

// Get performance metrics
final metrics = diagnostics.metrics;
print('Accuracy: ${metrics.accuracy}');
print('Battery impact: ${metrics.batteryImpact}');
```

## Error Recovery

Locus automatically attempts to recover from errors:

```dart
// Recovery is automatic, but you can manually trigger
await Locus.diagnostics.recoverFromError('location_service_failure');

// Listen for recovery events
Locus.diagnostics.onRecoveryAttempt((recovery) {
  print('Recovery: ${recovery.errorType} -> ${recovery.strategy}');
});
```

## Logging Configuration

Control verbosity of logs:

```dart
await Locus.config.set(
  NotificationConfig(
    logLevel: LogLevel.debug,  // verbose, debug, info, warning, error
  ),
);
```

**Next:** [Advanced Configuration](../core/configuration.md)
