# Changelog

All notable changes to this project will be documented in this file.

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
