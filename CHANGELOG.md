# Changelog

All notable changes to this project will be documented in this file.

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
