# HTTP Synchronization Guide

Last updated: January 7, 2026

Configure reliable HTTP sync with batching, retries, and offline queueing.

## Configure

```dart
await Locus.ready(ConfigPresets.balanced.copyWith(
  url: 'https://api.example.com/locations',
  headers: {'Authorization': 'Bearer <token>'},
  maxBatchSize: 50,
  autoSyncThreshold: 10,
  retryDelay: const Duration(seconds: 10),
));
```

## Request shape (default)
- Body: JSON array of location payloads.
- Headers: Include auth, content-type `application/json`, optional idempotency key.
- Response: 200/204 indicates success; non-2xx triggers retry with backoff.

## Batching and thresholds
- `autoSyncThreshold`: Triggers sync when queue reaches N records.
- `maxBatchSize`: Limits records per request to avoid server overload.
- `maxRetry` + `retryDelay` + `retryDelayMultiplier`: Control retry envelope.

## Offline handling
- Payloads queue in SQLite until network available.
- Set `disableAutoSyncOnCellular` if Wi‑Fi-only uploads are required.
- Use `syncQueue(limit: n)` to force a flush (e.g., on app foreground).

## Custom body
Use `setSyncBodyBuilder` to send a custom payload:

```dart
Future<JsonMap?> buildBody(List<Location> locations, JsonMap extras) async {
  return {
    'deviceId': extras['deviceId'],
    'locations': locations.map((l) => l.toJson()).toList(),
  };
}

await LocusSync.setSyncBodyBuilder(buildBody);
```

## Error handling
- Log and surface HTTP failures via `Locus.dataSync.httpEvents`.
- Treat 401/403 as auth failures; refresh tokens and retry.
- Implement server-side idempotency to avoid duplicates on retries.

## Testing checklist
- Verify success, 4xx, and 5xx responses.
- Simulate offline → online transitions and ensure queued payloads flush.
- Validate batch size and ordering on the server side.
