# Introduction

**Locus** is a battle-tested background geolocation SDK for Flutter. It provides high-performance, battery-optimized location tracking, geofencing, and automated data synchronization.

## Why Locus?

Building reliable background location tracking in Flutter is challenging due to:

- Native permission complexities (Background, Always, Precise).
- OS-level battery optimizations (Doze mode, App Standby).
- Data loss during offline periods.
- Platform inconsistencies between Android and iOS.

Locus abstracts these complexities into a single, unified API.

## Core Pillars

1.  **Reliability**: Persistent SQLite storage ensures no location is lost, even if the app or device restarts.
2.  **Efficiency**: Adaptive tracking profiles adjust based on motion activity and battery levels.
3.  **Simplicity**: Get started with 5 lines of code, or customize every parameter.
4.  **Testability**: Built-in mock instances and testing utilities.

## Next Steps

- [Quick Start Guide](guides/quickstart.md)
- [Route Replay](guides/route-replay.md)
- [Installation](setup/installation.md)
- [Platform Configuration](setup/platform-configuration.md)
