# HTTP Synchronization Guide

Last updated: January 7, 2026

Configure reliable HTTP sync with batching, retries, headers, and offline queueing.

> **Note:** The `url` parameter is optional. If omitted, Locus reads from native GPS but doesn't upload anywhere. This is useful for local-only testing.

## Baseline configuration

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://your-server.com/locations',
  headers: {'Authorization': 'Bearer <token>'},
  maxBatchSize: 50,
  autoSyncThreshold: 10,
  retryDelay: const Duration(seconds: 10),
  retryDelayMultiplier: 2.0,
  maxRetry: 5,
));
```

## Quick testing

For testing without a backend, use [webhook.site](https://webhook.site) to get a test endpoint:

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://webhook.site/your-unique-id',
));
```

## Request and response

- Body: JSON array of location payloads by default (each with coords, activity, extras).
- Headers: `content-type: application/json`, auth header, optional idempotency key.
- Success: 200/204 → remove batch from queue. Non-2xx → retry with backoff.

## Batching and thresholds

- `autoSyncThreshold`: Fire sync when queue length reaches N.
- `maxBatchSize`: Cap payload size to protect servers and mobile radios.
- `maxRetry` / `retryDelay` / `retryDelayMultiplier`: Define backoff envelope.

## Offline handling

- Queue persists in SQLite until connectivity returns.
- Set `disableAutoSyncOnCellular` to enforce Wi‑Fi-only uploads.
- Call `syncQueue(limit: n)` on foreground/resume to flush early.

## Custom body

Use `setSyncBodyBuilder` to send domain-specific payloads:

```dart
Future<JsonMap?> buildBody(List<Location> locations, JsonMap extras) async {
  return {
    'deviceId': extras['deviceId'],
    'locations': locations.map((l) => l.toJson()).toList(),
  };
}

await Locus.dataSync.setSyncBodyBuilder(buildBody);
```

## Sync Control

- **Pause/Resume**: `await Locus.dataSync.pause()` / `resume()` to prevent syncs during state restoration.
- **Validation**: Use `Locus.dataSync.setPreSyncValidator(...)` to approve/reject syncs based on app state (e.g. valid user ID).

## Error handling

- Surface errors via `Locus.dataSync.httpEvents`; log status and body.
- 401/403: refresh tokens; `await Locus.dataSync.pause()` until renewed.
- Timeouts/DNS: rely on retries; avoid tight retry loops.
- Use server-side idempotency to prevent duplicates after retries.

## Testing checklist

- Cover 200/204, 4xx (auth/validation), and 5xx responses.
- Simulate offline → online and ensure queues drain.
- Validate batch size, ordering, and headers at the server.
- Verify backoff timing aligns with `retryDelay` and multiplier.
