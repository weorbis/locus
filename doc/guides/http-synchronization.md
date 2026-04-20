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

Sync is **active by default** as soon as you set `Config.url`. You do not need to call `resume()` during normal initialization. Pause is reserved for two cases:

- **Explicit pause** — `await Locus.dataSync.pause()` halts sync in-memory. Use this for app-specific state restoration (e.g. a temporary maintenance mode). This pause does **not** persist across process restarts — the next cold start begins with sync active again. Call `await Locus.dataSync.resume()` to clear.
- **Transport auth pause** — a `401` or `403` response from the backend automatically pauses sync **and persists the reason** via `ConfigManager` so the pause survives a process kill. This prevents retry storms from a stale token after the OS reaps the process. To clear, refresh credentials (or confirm the user has permission) and call `await Locus.dataSync.resume()`. Any successful `2xx` response also clears the persisted reason defensively.

For domain-level gating ("don't sync until a shift has started", "drop sync if no `driver_id`") use `Locus.dataSync.setPreSyncValidator(...)` — the validator rejects individual batches without blocking the transport, keeping items in the queue until the validator approves.

### Observing pause state in UI

The Dart-side `isPaused` value is kept in sync with native via the `syncPauseChange` event, which the native `SyncManager` fires on every transition (explicit `pause()`, 401/403 auto-pause, `resume()`, 2xx recovery, and an initial replay when a Dart listener first attaches). This means:

```dart
// Synchronous read — always reflects the latest event from native:
final paused = Locus.dataSync.isPaused;
final reason = Locus.dataSync.pauseReason; // 'app' | 'http_401' | 'http_403' | null

// Reactive UI binding — subscribe once, render from the stream:
Locus.dataSync.pauseChanges.listen((state) {
  if (state.isAuthFailure) {
    showReAuthBanner();
  }
});
```

The `SyncPauseState` carries both the boolean and the reason, so the UI can differentiate a user-initiated pause ("Sync paused", actionable resume button) from an auth failure ("Authentication expired — please sign in", push to login).

## Error handling

- Surface errors via `Locus.dataSync.httpEvents`; log status and body.
- **401**: the native side attempts one in-line header refresh via `setHeadersCallback`. If the refresh yields a fresh `Authorization` header, the original request retries automatically. If not, sync pauses persistently — refresh credentials in your app and call `resume()` to clear.
- **403**: treated identically to 401 (persistent pause) because refreshing credentials cannot fix a permission denial — your app must resolve the underlying authorization problem before calling `resume()`.
- **Timeouts/DNS**: retry with backoff via the built-in retry policy; avoid tight retry loops in host code.
- Use server-side idempotency keys to prevent duplicates after retries.

## Testing checklist

- Cover 200/204, 4xx (auth/validation), and 5xx responses.
- Simulate offline → online and ensure queues drain.
- Validate batch size, ordering, and headers at the server.
- Verify backoff timing aligns with `retryDelay` and multiplier.
