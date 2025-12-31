# Changelog

All notable changes to Locus will be documented in this file.

## [1.0.0] - 2025-12-31

### Initial Release

Locus is a background geolocation SDK for Flutter, providing pure primitives for location-aware applications.

### Features

#### Core Tracking

- **Background Location Tracking** - Continuous tracking on Android and iOS
- **Activity Recognition** - Detect walking, running, driving, stationary states
- **Native Geofencing** - Enter/exit/dwell events with stored geofence management
- **Trip Lifecycle** - Start/update/end events with route deviation detection
- **Headless Execution** - Background events when app is terminated
- **Start on Boot** - Resume tracking after device restart (Android)

#### Battery Optimization

- **Adaptive Tracking** - Speed-based GPS tuning with configurable speed tiers
- **Sync Policies** - Network-aware sync behavior (WiFi, cellular, metered)
- **Power State Monitoring** - Real-time battery level and charging detection
- **Battery Stats** - Comprehensive tracking power metrics
- **Significant Location Changes** - Ultra-low power monitoring (~500m)

#### Data Management

- **HTTP Auto-Sync** - Automatic location upload with retry logic and exponential backoff
- **Offline Queue** - Custom payload sync with idempotency support
- **Batch Sync** - Efficiently upload multiple location points
- **Logging** - Rotation-based file logging

#### Advanced Capabilities

- **Enhanced Spoof Detection** - 13-factor analysis with confidence scoring
- **Geofence Workflows** - Sequenced multi-step geofence chains
- **Tracking Profiles** - Switch between off-duty, standby, en-route, arrived modes
- **Schedule Windows** - Time-based tracking activation
- **Error Recovery** - Centralized error handling with retries and backoff

### Platform Support

- **Android**: API 26+ (Android 8.0)
- **iOS**: iOS 14.0+
