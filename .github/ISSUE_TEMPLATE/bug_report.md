---
name: Bug report
about: Report a reproducible bug in the tracking engine
title: "[BUG] "
labels: bug
---

## Summary

Provide a clear and concise description of the bug.

## Plugin Configuration

Please provide the `Config` you are using (redact any sensitive URLs/keys):

```dart
Config(
  desiredAccuracy: ...,
  distanceFilter: ...,
  // etc
)
```

## Steps to Reproduce

1.
2.
3.

## Expected Behavior

What did you expect to happen?

## Actual Behavior

What actually happened? (e.g., location not recorded, geofence not triggered)

## Environment

- **Plugin Version**:
- **Flutter Version**:
- **Devices Tested**: (e.g., Samsung S22 Android 13, iPhone 14 Pro iOS 16)

## Device Logs

If possible, please provide logs from `BackgroundGeolocation.getLog()` or `BackgroundGeolocation.emailLog()`:

```
Paste logs here
```

## Additional Context

Add any other context about the problem here (e.g., happens only in background, only when battery saver is on).
