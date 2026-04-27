# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Dart: `Locus.dataSync.pauseChanges` stream and `pauseReason` getter (#35)** — Reactive pause-state observation backed by a new native `syncPauseChange` event emitted on every transition (explicit pause/resume, 401/403 auto-pause, 2xx recovery, and an initial replay when a Dart listener first attaches via `LocusContainer.replayInitialState` / `SwiftLocusPlugin.onListen`). The Dart-side `isPaused` cache is no longer a lie — it mirrors the native source of truth automatically. UI code can now render "re-authentication required" banners reactively from `SyncPauseState.isAuthFailure` without polling `getLocationSyncBacklog`.

### Changed

- **Android/iOS/Dart: Sync is now active by default when `Config.url` is set (#35)** — Previously, both the native `SyncManager` and the Dart-side `LocusSync._isPaused` cache initialized to `true`, requiring every host app to call `Locus.dataSync.resume()` after `Locus.ready()` or else see zero HTTP traffic. The example app did not call `resume()` in its `_configure()` path, so anyone copying the example verbatim (including the reporter of #35) would stream locations in Dart but never hit the backend. The paused-by-default stance was a blunt guard against domain-context races — a concern now owned by `setPreSyncValidator` and the existing 401 header-refresh recovery path. Pause is now reserved for transport-level outcomes: `Locus.dataSync.pause()` (in-memory, explicit) and HTTP 401/403 responses (persistent — see below).

### Fixed

- **Android: 401-recovery retry crashes with `NetworkOnMainThreadException`** — When the backend returned 401, `attemptLocationHeadersRecovery` invoked `listener.onHeadersRefresh { headers -> retry() }` and called `retry()` directly on whichever thread the headers callback delivered on. Both delivery paths (the `LocusPlugin`/`MethodChannel.Result` bridge path and `HeadlessHeadersDispatcher.refreshHeaders`, which posts via `mainHandler.post`) deliver on the main thread, so the retry's `performHttpRequest` / `performBatchHttpRequest` ran their blocking `HttpURLConnection` calls on main and Android raised `NetworkOnMainThreadException`. The exception was caught by the existing `try/catch` and surfaced as a generic `HTTP sync failed` log, so the retry was silently dropped and the batch waited for the next drain cycle. The retry is now dispatched onto the same `executor` used by all other HTTP work, regardless of which thread the headers callback delivers on.
- **Android: Location/queue stores fail to open on Samsung's hardened SQLite** — `LocationStore.onConfigure` and `QueueStore.onConfigure` set durability pragmas with `db.execSQL("PRAGMA journal_mode=WAL")`. Samsung's SQLite (observed on SM A346E running Android 16) treats `PRAGMA journal_mode=WAL` as a query because it returns the resulting mode, and rejects it from `execSQL` with `SQLiteException: Queries can be performed using SQLiteDatabase query or rawQuery methods only.` Every `readableDatabase` / `writableDatabase` call then re-ran `onConfigure` and threw, so the location DB and the offline queue DB were effectively unusable on those devices — `getLocationSyncBacklog` returned errors, location writes silently failed, and the offline queue could not be drained. Both pragmas now use `rawQuery(...).use { it.moveToFirst() }`, matching the existing `checkpoint()` pattern and working on AOSP and Samsung alike.
- **Android/iOS: Auth-failure pause now persists across process restarts (#35)** — Previously, a 401 from the backend paused sync in memory only; the next cold start reset `isSyncPaused` to its default, which (given the new active-by-default behavior) could cause a retry storm against a stale token. `ConfigManager` now writes the pause reason (`http_401` / `http_403`) to `SharedPreferences` (Android) / `UserDefaults` (iOS) whenever sync pauses for auth reasons, and `SyncManager` reads it on init so the pause survives relaunch. Any 2xx response clears the persisted reason defensively (and `Locus.dataSync.resume()` clears it explicitly). An HTTP 403 response now also triggers the persistent pause (previously only 401 paused, and 403 retried forever) — a permission denial is an auth-class failure where retry-without-intervention cannot succeed. The 401 header-refresh recovery path (`onHeadersRefresh`) remains 401-only because a fresh token does not resolve a forbidden resource. Explicit `Locus.dataSync.pause()` stays in-memory only, so "pause for now" intent never leaks into the next process.
- **Android: Tracking stops when app is closed despite `foregroundService: true` (#34)** — `LocusPlugin.onDetachedFromEngine` unconditionally released native resources and tore down the foreground service whenever the Flutter UI detached (swipe-away or normal destroy), regardless of `stopOnTerminate`. This violated the documented "always-on" contract (`stopOnTerminate:false + enableHeadless:true + foregroundService:true`). The detach path now chooses between a *soft* detach (keep the foreground service + native managers alive and reclaim ownership on the next primary attach) and a *hard* detach (full teardown — the previous behavior), based on the live tracking state. `LocationTracker.release()` has been split into `releaseAll()` (hard teardown) and `releaseListeners()` (soft detach) with an idempotent `resumeTracking()` for takeover.
- **Android: `ForegroundService` did not survive task removal** — Added `onTaskRemoved` override that no-ops instead of inheriting the default stop behavior. Combined with `START_STICKY` and the soft-detach path, tracking now survives the user swiping the app away from recents on Samsung One UI, Xiaomi MIUI, and other OEMs with aggressive task killers.
- **Android/iOS: `Locus.isTracking()` returns `false` after process relaunch (#34)** — Tracking state was kept in a process-lifetime in-memory field only, so after the OS reaped a background process (or the user force-stopped and reopened), `isTracking()` would return `false` even when the foreground service / significant-location-change subscription was alive. Tracking state is now persisted to `bg_tracking_active` in `SharedPreferences` / `UserDefaults` on every `start`/`stop` and reconciled on `onAttachedToEngine` (Android) and plugin init (iOS): if the flag is set and permissions are intact, tracking is re-armed automatically. iOS also replaces the previous `startOnBoot`-only re-arm condition in the location delegate with a broader check that covers `stopOnTerminate:false` relaunches.

## [2.2.2] - 2026-04-05

### Breaking

- **Android/iOS: `maxRetry` default changed from `0` to `3`** — The previous default of `0` meant HTTP sync failures were never retried, silently stranding queued locations in the native database with no recovery path. The new default retries with exponential backoff (5s → 10s → 20s, capped by `maxRetryDelay`). Consumers that explicitly relied on `maxRetry: 0` to disable retries must now set it explicitly.

### Fixed

- **Android/iOS: Backlog drain stops after first failed batch** — When the sync drain encountered a batch that exhausted all retries (or was rejected by the pre-sync validator / sync body builder), the entire drain loop stopped. Remaining batch groups with different route contexts — which may have been perfectly syncable — were never attempted until the next `resumeSync()` call. The drain now tracks exhausted contexts per cycle and advances to the next context group. The exhausted set is cleared on each `resumeSync()` so previously failed contexts get a fresh chance.

## [2.2.1] - 2026-04-04

### Fixed

- **Android: ForegroundService SecurityException on SDK 36** — Wrapped `startForeground()` in a `SecurityException` catch block. On Android 14+ (SDK 34+), the OS throws when starting a foreground service with type `location` if runtime permissions were revoked between the Dart-side check and the native service start, or during a headless restart. The service now stops gracefully instead of crashing.
- **Android: Geofence registration without permission check** — Replaced `@SuppressLint("MissingPermission")` on `addGeofence()`, `addGeofences()`, and `startGeofencesInternal()` with explicit `ContextCompat.checkSelfPermission()` validation. Returns `PERMISSION_DENIED` error (or skips silently for internal calls) instead of letting the system throw an unhandled `PlatformException`.
- **Android: BootReceiver headless dispatch without permission check** — Added `ACCESS_FINE_LOCATION` runtime permission verification before dispatching the headless service on boot. Prevents `SecurityException` cascades when the user revoked location permission while the app was killed.

## [2.2.0] - 2026-03-20

### Added

- **Dart/Android/iOS: Dynamic notification updates** — New `Locus.updateNotification(title:, text:)` API to update notification content while tracking is active, without restarting the service. Useful for displaying live trip stats (distance, duration, etc.) in the notification.

### Platform Notes

- **Android**: Updates the persistent foreground service notification in-place. No additional permissions needed beyond what `PermissionService.requestAll()` already requests.
- **iOS**: Posts or replaces a local notification via `UNUserNotificationCenter`. The host app must obtain notification authorization **before** calling this method; if permission has not been requested or was denied, the call returns `false` silently. Locus will not trigger a permission dialog.

## [2.1.4] - 2026-03-12

### Breaking

- **Dart: Dynamic header APIs are now explicitly async** — `setHeadersCallback()` now returns `Future<void>` and must be awaited before starting tracking or sync flows that depend on fresh headers. `refreshHeaders()` now accepts `force: true` to bypass throttling for explicit recovery paths.

### Added

- **Dart: Headless sync registration APIs** — Added `registerHeadlessPreSyncValidator()` and `registerHeadlessHeadersCallback()` so terminated/background RouteHistory can validate task/auth context and recover headers without opening the app.
- **Dart: RouteHistory backlog inspection** — Added `getBacklog()` plus the `LocationSyncBacklog` and `LocationSyncBacklogGroup` models, including pending point count, pending batch count, paused state, quarantine count, last success/failure, and grouped summaries by task/session.
- **Android/iOS: Immutable per-point RouteHistory context** — Persisted location rows now retain route context (`ownerId`, `driverId`, `taskId`, `trackingSessionId`, `startedAt`) so queued RouteHistory batches are drained under the original task/session instead of relying on the app's current global extras at send time.

### Fixed

- **Dart: Explicit header refresh is now deterministic** — Explicit `refreshHeaders()` requests bypass throttling so auth recovery and tracking startup can force an immediate native header refresh.
- **Dart: Malformed HTTP sync events no longer break listeners** — `HttpEvent` parsing is now guarded so invalid payloads are ignored instead of terminating the stream.
- **Android/iOS: Custom sync body builder failures preserve queued data** — When a registered sync body builder throws or returns `null`, sync now treats it as a retryable failure and retains queued locations instead of falling back to a partial native body.
- **Android/iOS: RouteHistory batches are serialized and task-safe** — Native location sync now drains one route batch at a time, groups batches by immutable route context, and quarantines incomplete legacy rows instead of guessing task ownership.
- **Android/iOS: Native 401 recovery now retries once before pausing sync** — RouteHistory sync attempts one headless headers refresh on `401 Unauthorized`, updates dynamic headers, and retries the same batch once before pausing sync.
- **Android/iOS: Validator and sync diagnostics improved** — Added clearer diagnostics for skipped sync attempts, builder failures, headless header recovery failures, and queued RouteHistory backlog state to make production delivery issues easier to investigate.

## [2.1.3] - 2026-03-05

### Fixed

- **iOS: Dynamic sync headers applied to HTTP requests** — `dynamicHeaders` are now merged into request headers before sync requests are sent, ensuring refreshed auth tokens are included during background and foreground sync.
- **iOS: Privacy mode activation matches configured zones** — Native privacy mode is now enabled only when at least one privacy zone is actively enabled, preventing raw location persistence/sync from being disabled just because the privacy service exists.
- **iOS: Sync waits for persisted locations** — Location and geofence-triggered sync now runs after SQLite persistence completes, avoiding races where sync read an empty batch before the insert committed.

## [2.1.2] - 2026-03-03

### Added

- **Android/iOS: Pre-flight manifest permission validation** — Added `validateManifestPermissions()` check in `ready()` handler. Instead of crashing with a raw `SecurityException`/`PlatformException` when `ACCESS_NETWORK_STATE` or location permissions are missing, the plugin now emits structured error events through the EventChannel stream with `ERR_MISSING_MANIFEST` and `ERR_PERMISSION_DENIED` error codes.
- **Android: `ACCESS_NETWORK_STATE` permission** — Declared in plugin `AndroidManifest.xml` so host apps inherit it automatically.
- **Dart: `MissingManifestPermissionException` and `PermissionErrorEvent`** — Typed error models for permission-related failures, with `missingManifestPermission` added to `LocusErrorType` enum.
- **iOS: Structured permission error events** — Emits typed `PermissionErrorEvent` for denied/restricted location permission states instead of silently failing.

### Fixed

- **Dart: Trip summary average speed exceeding max speed** — `TripState.toSummary()` computed `averageSpeedKph` as `distance / movingSeconds` without capping it. When idle detection over-counted due to GPS jitter on short trips, `movingSeconds` shrunk to near-zero, producing an average speed higher than the observed `maxSpeedKph` (e.g., 36.6 km/h average vs 1.6 km/h max). Now falls back to total duration when `movingSeconds` is zero and clamps the result to never exceed `maxSpeedKph`.
- **Android: `SystemMonitor` `ConnectivityManager` hardening** — Wrapped `ConnectivityManager` calls in `runCatching` to handle `SecurityException` gracefully when `ACCESS_NETWORK_STATE` is missing at runtime.

## [2.1.1] - 2026-02-18

### Fixed

- **Android/iOS: Multi-engine singleton guard** — Added singleton pattern to prevent secondary Flutter engines (created by `flutter_background_service`, `geolocator`, etc.) from initializing duplicate native resources. Previously, when a background service engine was destroyed, its `LocusPlugin.onDetachedFromEngine()` would tear down shared native resources (Activity Recognition PendingIntents, connectivity listeners, database connections), killing the primary engine's active tracking. Secondary engines now skip native resource initialization and cleanup entirely.

## [2.1.0] - 2026-02-17

### Fixed

- **Android: ForegroundService crash on Android 14+** — Restructured to two-phase notification strategy, calling `startForeground()` immediately with a minimal notification before building the full one. Eliminates `ForegroundServiceDidNotStartInTimeException`. (#22)
- **Android: Odometer float precision loss** — Switched from 32-bit float to 64-bit long storage using `Double.toBits()`/`fromBits()` with automatic migration from legacy format.
- **Android: TrackingStats race condition** — Added `@Synchronized` to `onLocationUpdate()` and `onTrackingStop()` to prevent concurrent session field corruption.
- **Android: EventDispatcher race on eventSink** — Use captured local reference in `mainHandler.post` block to prevent null dereference if sink is cleared between check and use.
- **Android: SyncManager log exposure** — Sanitized error messages in `Log.e()` calls to strip URLs that may contain tokens or sensitive path segments.
- **Android: MotionManager null safety** — Replaced `!!` assertions with safe `?.let` pattern on `motionTriggerRunnable` and `stopTimeoutRunnable`.
- **Android: SystemMonitor null activeNetwork** — Added null check on `ConnectivityManager.activeNetwork` with early return.
- **Android: LocationEventProcessor privacy log** — Removed privacy mode config value from log output.
- **Android: TrackingStats integer overflow** — Explicit `Long` division for tracking minutes calculation.
- **Android: HeartbeatScheduler first beat** — Fire first heartbeat immediately instead of waiting one full interval.
- **Android: ForegroundService null actions** — Added `.filterNotNull()` on notification actions array.
- **Android: SQLite storage integrity** — Wrapped operations in transactions, `onUpgrade` no longer drops tables.
- **Android: HeadlessService SharedPreferences** — Aligned prefs name and key with ConfigManager.
- **Dart: RoutePoint unsafe cast** — Safe null-aware cast with fallback for `latitude`/`longitude`.
- **Dart: TripSummary unsafe DateTime.parse** — Use `DateTime.tryParse()` with fallback instead of throwing on malformed dates.
- **Dart: Location silent fallback** — Added debug-mode logging when coords fall back to (0,0) due to validation failure.
- **Dart: Adaptive heartbeat** — Stationary heartbeat now factors battery level instead of always using max interval.
- **Dart: Headless sync body builder** — Fixed callback to construct proper `SyncBodyContext` matching the typed contract instead of passing a raw Map.
- **iOS: SyncManager thread safety** — Thread-safe network state and URLSession lifecycle improvements.
- **iOS: SQLiteStorage memory safety** — All `sqlite3_bind_text` calls now use `SQLITE_TRANSIENT` to prevent use-after-free.
- **iOS: SQLiteStorage concurrency** — `createTables` moved inside queue.sync block.

### Changed

- **Adaptive tracking** — Stationary heartbeat uses averaged interval for normal battery level (previously always used max).
- **Event processing** — Spoof detection, privacy zone filtering, and polygon geofence detection now apply to heartbeat, motionChange, and schedule events (previously location-only).
- **AppLifecycleState.inactive** — Now treated as foreground to avoid unnecessary background transitions during permission dialogs and phone calls.
- **Config validation** — `maxMonitoredGeofences > 20` now produces a warning instead of an error for iOS compatibility.
- **Debug overlay tests** — Fixed `ink_sparkle.frag` shader issue in test environment using `NoSplash` theme.

### Added

- SSL pinning configuration options (`sslPinningCertificate`, `sslPinningFingerprints`).
- `LocusSync.isSyncReady()` method.
- Config URL format validation warnings.
- iOS log level `"off"` support.

## [2.0.1] - 2026-01-12

### Changed

- **Transfer of Ownership**: Project ownership officially transferred to the **WeOrbis** ecosystem.
- **License Change**: Relicensed from PolyForm Small Business License to **MIT License** for better community adoption and accessibility.
- **Repository URLs**: Updated all repository links to point to the new location at `github.com/weorbis/locus`.
- **Branding & Contact**: Updated contact emails to `info@weorbis.com` and `security@weorbis.com`. Removed all personal developer references to reflect organizational ownership.

## [2.0.0] - 2026-01-07

### Breaking

- **Removed v1.x facade methods**: All deprecated static methods were removed. Use the service-based API via `Locus.location`, `Locus.geofencing`, `Locus.privacy`, `Locus.trips`, `Locus.dataSync`, and `Locus.battery`. Core lifecycle methods (`ready`, `start`, `stop`, `getState`) remain on `Locus`.
- **Removed features**: `emailLog()` and `playSound()` have been removed.
- **url_launcher removed**: `DeviceOptimizationService.showManufacturerInstructions()` replaced with `getManufacturerInstructionsUrl()` returning a URL string. Apps should handle URL launching themselves.

### Added

- **v2.0 Service-Based API**: New domain-organized services accessible via static properties:
  - `Locus.location` - Location tracking, streaming, and queries
  - `Locus.geofencing` - Geofence CRUD, monitoring, and workflows
  - `Locus.privacy` - Privacy zone management
  - `Locus.trips` - Trip tracking and state
  - `Locus.dataSync` - HTTP sync, queue management, and policies
  - `Locus.battery` - Power state, adaptive tracking, and benchmarking
- **Migration CLI Tool**: `dart run locus:migrate` command for automated v1.x → v2.0 migration
  - Pattern-based detection of deprecated API usage
  - Dry-run mode for safe preview
  - Detailed migration suggestions with line numbers
  - **Monorepo support**: Automatically detects and processes multiple packages in monorepo workspaces
    - Discovers all Dart/Flutter packages in the workspace structure (supports `packages/`, `apps/`, `modules/`, etc.)
    - Pre-flight Locus SDK usage detection per package
    - Aggregates analysis results across all packages with per-package breakdown
    - Applies migrations to each package independently
    - Single backup for entire monorepo
    - Distinguishes between Flutter apps and packages in output
  - **Rollback support**: `--rollback` flag to restore from most recent backup
  - **Analysis-only mode**: `--analyze-only` to scan without migration suggestions
  - **Pattern filtering**: `--ignore-pattern` and `--only-category` options for targeted migrations
  - **Migration hints**: Smart suggestions for headless callbacks, config changes, and removed features
  - **70+ migration patterns**: Comprehensive coverage across all service categories
    - Location, Geofencing, Privacy, Trips, Sync, Battery, Diagnostics
    - Config parameter renames (url→syncUrl, httpTimeout→syncTimeout)
    - Removed feature detection with TODO comments
    - Headless callback pragma annotation hints
- **Service behavior tests**: Expanded unit coverage for the new v2.0 service APIs
  - Full suite now green (666 tests passing)
- **Dynamic headers support**: `setDynamicHeaders()` now works on both Android and iOS
- **Sync policy support (iOS)**: `setSyncPolicy()` handler added for iOS platform parity
- **Metered connection detection (iOS)**: `isMeteredConnection()` handler for WiFi-only sync
- **Tracking data cleanup helper**: `Locus.clearTrackingData()` for clearing stored locations and (optionally) the sync queue without stopping tracking

### Fixed

- **Android**: Fixed Kotlin stdlib version mismatch (was 1.9.22, now uses plugin's 2.1.0)
- **Android**: `setSyncPolicy()` now applies to ConfigManager immediately instead of being a no-op
- **Android**: Bulk `addGeofences()` now respects per-geofence `notifyOnEntry`/`notifyOnDwell` flags
- **Android**: `motionManager` properly stopped on plugin detach (prevents PendingIntent leak)
- **Android**: ConfigManager properties marked `@Volatile` for thread safety
- **Android**: BackgroundTaskManager uses `ConcurrentHashMap` for thread-safe task tracking
- **Android**: SyncManager graceful shutdown with `isReleased` flag to prevent callbacks after release
- **Android**: Database helpers (LocationStore, QueueStore) explicitly closed on detach
- **iOS**: `sendEvent` dispatched on main thread to prevent crashes from background delegates
- **iOS**: `isSyncPaused` made thread-safe with serial dispatch queue
- **iOS**: GeofenceManager cleanup added to stop monitoring and clear delegate on deinit
- **iOS**: Heartbeat timer properly invalidated when plugin deallocates
- **Build**: Removed hardcoded JDK path from gradle.properties
- **Build**: Removed unused `xml` dependency from pubspec.yaml
- **Build**: Added CoreLocation framework to iOS podspec

### Changed

- **MockLocus enhancements**: Added `emitPowerSaveChange()`, `emitPowerStateChange()`, and method call tracking for sync/battery APIs
- **Lint rules**: Added comprehensive lint rules (prefer_const_constructors, prefer_final_fields, unawaited_futures, cancel_subscriptions, close_sinks, etc.)

## [1.2.0] - 2026-01-03

### Breaking

- Internal imports were reorganized into feature-first barrels. Any direct imports under `package:locus/src/core/...`, `package:locus/src/services/...`, or `package:locus/src/models/...` from 1.1.x will break. Migrate to the public barrels exposed by [lib/locus.dart](lib/locus.dart) or, for advanced/internal use, the consolidated [lib/src/models.dart](lib/src/models.dart) and [lib/src/services.dart](lib/src/services.dart).

### Added

- **Polygon Geofences**: Define complex boundaries with arbitrary shapes using `PolygonGeofence`. Supports enter/exit detection with efficient ray-casting algorithm.
- **Privacy Zones**: New privacy protection feature allowing users to exclude, obfuscate, or reduce accuracy in sensitive areas.
- **Trip Tracking**: Automatic trip detection with start/end events, route recording, and trip summaries.
- **Geofence Workflows**: Multi-step geofence sequences with timeouts for complex location-based flows.
- **Tracking Profiles**: Pre-defined and custom tracking profiles with automatic switching rules.
- **Battery Runway**: Estimate remaining tracking time based on current battery drain rate.

### Changed

- **Architecture**: Restructured codebase to feature-first organization (MVVM pattern). Code is now organized by domain (location, geofencing, battery, etc.) rather than by layer (models, services).
- **Import Paths**: Barrel exports simplified. Use `import 'package:locus/locus.dart'` for all public APIs.

### Fixed

- Android: guarded foreground service startup for null intents/notification permission errors and prevented stale geofence payloads from persisting when privacy mode is enabled; geofence restore now clears persisted entries on Play Services failures to keep Dart and native in sync.
- Android: cleaned up cached headless Flutter engines after idle to avoid leaks.
- iOS: startTracking now requests/validates permission before enabling, and significant-change monitoring runs only with Always authorization.
- Dart: start returns disabled state when native start fails instead of assuming enabled; destroy now also invokes native stop/cleanup hooks.
- Dart: location queries honor limit/offset without loading unbounded history; trip engine awaits persistence to avoid dropped saves; enqueue now surfaces native failures instead of returning empty ids.

## [1.1.0] - 2026-01-01

### Added

- **Testability**: Refactored `Locus` to support mocking via `setMockInstance()`, enabling robust unit testing for apps using the SDK.
- **Structured Logging**: Replaced flat-file logging with SQLite-based structured logs on Android and iOS. Added `Locus.getLog()` returning `List<LogEntry>`.
- **Authentication Handling**: Implemented smart 401 Unauthorized handling. Sync pauses automatically on 401; use `Locus.resumeSync()` after token refresh.
- **Permissions Workflow**: Added `PermissionAssistant` to manage complex permission sequences (Location, Activity, Notification) with UI callbacks.
- **Device Optimization**: Added `DeviceOptimizationService` to detect OEM battery restrictions and guide users to "Don't Kill My App" instructions (Android).
- **Configuration Presets**: Added `Config.fitness()` and `Config.passive()` factory constructors for quick setup.
- **iOS Data Persistence**: New `SQLiteStorage` engine for iOS, providing high-performance persistent storage (replacing `UserDefaults`).
- **Custom Sync Body Builder**: Added `Locus.setSyncBodyBuilder()` to allow full control over HTTP request body structure. Ideal for backends requiring custom JSON envelopes (e.g., `{ ownerId, taskId, polygons: [...] }`).
- **Headless Sync Body Builder**: Added `Locus.registerHeadlessSyncBodyBuilder()` for background sync with custom body formats, even when the app is terminated.
- **Native Sync Envelope Support**: The `extras` config field is now merged at the top level of HTTP sync bodies on both Android and iOS. Combined with `httpRootProperty`, this enables custom JSON structures without Dart callbacks.
- **Developer Experience (DX) Improvements**:
  - Added `locus_errors.dart` with descriptive exception types (`NotInitializedException`, `SyncUrlNotConfiguredException`, `HeadlessRegistrationException`, etc.).
  - Headless registration now prints detailed instructions when callback handles fail.
  - Native sync adds debug logs explaining why sync was skipped (no URL, paused, etc.).
  - Config validator now warns about common issues: `extras` without `httpRootProperty`, `autoSync` without `batchSync`, `enableHeadless` without `stopOnTerminate: false`.
- Centralized `LocusConstants` for all SDK parameters.
- Proper `toString()` implementations for core models.

### Fixed

- **iOS Storage**: Migrated storage to SQLite to resolve data truncation issues.
- **Platform Parity**: Implemented confidence threshold filtering for motion activity on iOS.
- **Error Handling**: Standardized error responses across platforms.
- **Lifecycle Management**: Fixed iOS `SyncManager` lifecycle issues.
- **Test Stability**: Resolved unit and integration test flakiness.

### Changed

- Refactored `StorageManager` to utilize the new SQLite backend.
- Simplified internal method channel handlers.
- Updated native battery stats to include detailed drain estimates.

## [1.0.0] - 2025-12-31

### Initial Release

- Background location tracking for Android and iOS.
- Activity recognition and motion state updates.
- Native geofencing support.
- HTTP auto-sync with retry logic.
- Adaptive tracking and sync policies.
- Spoof detection and battery optimization features.
