# Error Codes Reference

Last updated: January 7, 2026

This guide maps common Locus exceptions and native error codes to causes and recovery steps.

## Exceptions

### NotInitializedException
- **When it happens:** Calling Locus APIs before `Locus.ready()`.
- **Fix:** Call `await Locus.ready()` with a valid `Config` before other methods.

### SyncUrlNotConfiguredException
- **When it happens:** Sync enabled but no URL provided.
- **Fix:** Provide `url` in `Config` or disable sync.

### InsufficientPermissionsException
- **When it happens:** Required OS permissions not granted.
- **Fix:** Request permissions; guide the user to Settings if denied permanently.

### GeofenceLimitExceededException
- **When it happens:** Platform geofence limit reached.
- **Fix:** Remove unused geofences before adding new ones.

### TrackingProfilesNotConfiguredException
- **When it happens:** Profiles referenced but not configured.
- **Fix:** Define profiles in `Config` before use.

### PluginNotAvailableException
- **When it happens:** Platform channel not available (app not initialized or plugin not registered).
- **Fix:** Ensure Flutter engine initialized and plugin registered; retry after init.

### HeadlessRegistrationException
- **When it happens:** Headless callback not a top-level/static function.
- **Fix:** Register a top-level function and rebuild.

## Native error codes (1-5)
- **1:** Permission denied → Request permissions again or exit gracefully.
- **2:** Location provider disabled → Prompt user to enable location services.
- **3:** Network unavailable → Retry with exponential backoff; queue payloads offline.
- **4:** Storage error → Check disk space; clear queue or prune old data.
- **5:** Invalid request → Validate payload shape and required fields.

## Recovery checklist
- Confirm `Locus.ready` completed successfully.
- Verify permissions (foreground + background on Android; Always on iOS if needed).
- Ensure sync URL and headers are set before enabling sync.
- Keep geofence counts under platform limits (≈100 on Android, ≈20 on iOS per app).
- Use headless-safe callbacks for background execution.
