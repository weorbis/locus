# Performance Optimization Guide

Last updated: January 7, 2026

Practical tips to balance accuracy and battery for Locus.

## Tuning knobs
- **desiredAccuracy:** Lower accuracy reduces GPS usage; consider `balanced` for most apps.
- **distanceFilter:** Increase to reduce update frequency; smaller values yield more updates and drain.
- **heartbeatInterval:** Adjust stationary heartbeat; lengthen to save power.
- **activityRecognitionInterval:** Longer intervals reduce motion polling cost.
- **batch sync:** Enable batching to cut HTTP overhead; tune `maxBatchSize` and thresholds.

## Profiles
- Use Config presets (e.g., balanced, lowPower) as starting points; adjust for your use case.
- For trip-intensive apps, favor higher accuracy while moving and relaxed settings when stationary.

## Battery-aware behavior
- Leverage adaptive tracking if available to auto-scale based on battery and motion.
- Pause or throttle sync on low power; avoid large payloads on poor networks.

## Geofencing vs. continuous tracking
- Prefer geofences for coarse presence detection; fall back to continuous tracking only when inside regions of interest.
- Keep geofence counts lean to reduce platform overhead.

## Diagnostics
- Monitor `battery.powerStateEvents` to observe drain conditions.
- Inspect diagnostics/queue size; large queues may indicate connectivity issues.

## Validation checklist
- Measure battery impact over 60–120 minutes in foreground and background.
- Verify accuracy meets product requirements in urban vs. rural tests.
- Confirm sync volume and frequency meet backend SLAs.
