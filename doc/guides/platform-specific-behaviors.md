# Platform-Specific Behaviors

Last updated: January 7, 2026

Key runtime differences between Android and iOS that affect tracking, geofencing, and background execution.

## Android
- **Doze/App Standby:** Background work delayed; use foreground service with notification to stay alive.
- **Permissions:** Fine + Background location often required; request foreground first, then background.
- **Geofence limits:** Typically ~100 per app; keep identifiers stable.
- **Foreground service timeout:** Must call `startForeground` promptly with a notification.
- **Battery optimizations:** Some OEMs (Xiaomi, Huawei, Samsung) are aggressive—document exemption steps to users.

## iOS
- **Background modes:** Enable Location Updates and Background Fetch as needed.
- **Significant-change vs. standard updates:** SLC is lower power but less precise; standard updates pause when app suspended unless background mode active.
- **Approximate location:** iOS may grant reduced accuracy; prompt user to allow precise if needed.
- **Geofence limits:** ~20 regions per app; keep fences focused.
- **Background task limits:** Tasks must finish quickly; incomplete work may be terminated.

## Cross-platform recommendations
- Keep geofence counts under platform limits; prune unused fences.
- Provide clear permission rationale and fallback UX when denied.
- Tune `distanceFilter`, `desiredAccuracy`, and heartbeat intervals per platform power expectations.
- Handle reduced accuracy gracefully (avoid rejecting coarse fixes outright).
- Log platform state (power, connectivity, permission status) to aid troubleshooting.
