# Configuration

Locus is highly configurable. You can either use pre-defined presets or create a fully custom configuration.

## Presets

Presets are the recommended way to start. They provide optimized settings for specific use cases.

- `Config.fitness()`: High accuracy (1-5m), high frequency. Ideal for running or cycling apps.
- `ConfigPresets.balanced`: Standard accuracy (10-25m), balanced battery usage.
- `Config.passive()`: Low power, relies on significant location changes. Minimal battery impact.

## Custom Configuration

You can customize individual parameters:

```dart
final config = Config(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 10,
  stopTimeout: 5,
  logLevel: LogLevel.verbose,
  // ... many more
);

await Locus.ready(config);
```

### Key Parameters

| Parameter           | Type              | Default                       | Description                                                      |
| :------------------ | :---------------- | :---------------------------- | :--------------------------------------------------------------- |
| `desiredAccuracy`   | `DesiredAccuracy` | `null` (use a preset)         | Target accuracy (navigation, high, medium, low, veryLow, lowest). |
| `distanceFilter`    | `double`          | `null` (use a preset)         | Minimum distance (meters) before a location update is triggered. |
| `stopTimeout`       | `int`             | `null` (use a preset)         | Minutes to wait after motion stops before powering down sensors. |
| `heartbeatInterval` | `int`             | `null` (use a preset)         | Interval (seconds) for an idle-state heartbeat event.            |

## HTTP Synchronization

Locus can automatically sync location data to your backend with batching and retry logic.

> **Note:** The `url` parameter is optional. Omit it for local-only testing.

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://your-server.com/locations',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
  },
  batchSync: true,
  maxBatchSize: 50,
));
```

### Testing without a backend

Use [webhook.site](https://webhook.site) to get a test endpoint:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://webhook.site/your-unique-id',
));
```

---

**Next:** [Adaptive Tracking](../core/adaptive-tracking.md)
