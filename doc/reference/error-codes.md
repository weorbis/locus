# Error Codes Reference

Last updated: January 7, 2026

Common exceptions and native error codes with causes and fixes.

## Exceptions

### NotInitializedException
- **When:** Locus APIs called before `Locus.ready()` completes.
- **Fix:** Await `Locus.ready()` with a valid `Config` during startup.

### SyncUrlNotConfiguredException
- **When:** Sync enabled but no `url` provided.
- **Fix:** Supply `url` in `Config` or disable sync.

### InsufficientPermissionsException
- **When:** Required OS permissions missing or downgraded.
- **Fix:** Request permissions; direct users to Settings if permanently denied.

### GeofenceLimitExceededException
- **When:** Platform geofence limit exceeded.
- **Fix:** Remove stale fences; keep counts within platform caps.

### TrackingProfilesNotConfiguredException
- **When:** Profiles referenced before being defined.
- **Fix:** Define profiles in `Config` before use.

### PluginNotAvailableException
- **When:** Platform channel unavailable (app not initialized or plugin not registered).
- **Fix:** Ensure Flutter engine is initialized; retry after startup.

### HeadlessRegistrationException
- **When:** Headless callback is not top-level/static or missing entry-point pragma.
- **Fix:** Register a top-level function with `@pragma('vm:entry-point')`.

### MissingManifestPermissionException
- **When:** Required permissions not declared in `AndroidManifest.xml`.
- **Fix:** Add missing `<uses-permission>` entries to your manifest.

## Native error codes (1-6)
- **1:** Permission denied → Request again; if denied, degrade gracefully.
- **2:** Provider disabled → Prompt to enable location services.
- **3:** Network unavailable → Queue payloads; retry with backoff.
- **4:** Storage error → Check disk space; clear/prune queue; retry after recovery.
- **5:** Invalid request → Validate payload and required fields.
- **6:** Missing manifest permission → Add required `<uses-permission>` declarations.

## Event stream error codes
- **ERR_MISSING_MANIFEST:** Permission not declared in the manifest. Emitted during `Locus.ready()` on Android when required permissions are missing from `AndroidManifest.xml`.
- **ERR_PERMISSION_DENIED:** User has not granted a required runtime permission. Emitted on both Android and iOS when location or network permissions are denied.

## Recovery checklist
- Ensure `Locus.ready` succeeded before other calls.
- Verify manifest declarations include all required permissions (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_NETWORK_STATE`).
- Verify runtime permissions (foreground + background on Android; Always on iOS when needed).
- Set sync URL/headers before enabling auto sync.
- Keep geofence counts under platform limits (≈100 Android, ≈20 iOS per app).
- Use headless-safe callbacks for background execution.
