# Activity Recognition Guide

Last updated: January 7, 2026

Understand and use activity signals to optimize tracking behavior.

## Supported activities
Typical states include: still, walking, running, cycling, inVehicle, unknown. Platform availability may vary.

## Usage
- Subscribe to motion/activity streams to react to changes.
- Increase accuracy when moving fast; relax when stationary to save power.
- Combine with geofences to trigger richer experiences only when relevant.

## Configuration tips
- Set `activityRecognitionInterval` to balance responsiveness and battery.
- Treat `unknown` conservatively (do not assume movement).
- Debounce rapid activity flapping before changing modes.

## Testing
- Simulate transitions (walk → run → drive) and ensure app reacts as expected.
- Validate on both platforms; detection fidelity differs between Android and iOS.
