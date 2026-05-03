# locus

## Tech Stack

- **Framework**: Flutter
- **Language**: Dart
- **Package Manager**: flutter pub

## Commands

```bash
# Get dependencies
flutter pub get

# Build
flutter build

# Test
flutter test

# Run
flutter run

# Analyze
flutter analyze
```

## Project Structure

Locus is a **Flutter plugin** (not an application) — a background geolocation SDK with native Android/iOS implementations and a minimal Dart facade.

```
locus/
├── lib/                          # Dart SDK (public API)
│   ├── locus.dart                # Single entry point — barrel re-exports only
│   └── src/
│       ├── core/                 # Platform channels, abstract interface, event streams, lifecycle
│       ├── config/               # Config, presets, validators, enums, constants
│       ├── features/             # Feature-first modules, each with models/ + services/
│       │   ├── location/         # Core tracking, quality analysis, spoof/anomaly detection
│       │   ├── geofencing/       # Circular + polygon geofences, workflow engine
│       │   ├── battery/          # Adaptive tracking, runway estimation, power state
│       │   ├── privacy/          # Privacy zones (exclude / obfuscate / reduce)
│       │   ├── trips/            # Trip detection, route recording, persistent trip store
│       │   ├── sync/             # HTTP queue, batch sync, retry, connectivity handling
│       │   ├── tracking/         # Tracking profiles, rule-based profile switching
│       │   └── diagnostics/      # Logging, debug overlay widget, error recovery
│       ├── services/             # Service interfaces + default implementations
│       ├── shared/               # Cross-cutting models (Coords, Activity, Battery, …)
│       └── testing/              # MockLocus — for host-app tests
├── android/src/main/kotlin/dev/locus/
│   ├── LocusPlugin.kt            # FlutterPlugin entry; wires method + event channels
│   ├── core/                     # ConfigManager, LocationTracker, StateManager, TrackingLifecycleController
│   ├── location/                 # FusedLocationProvider client wrapper
│   ├── activity/                 # MotionManager (ActivityRecognitionClient)
│   ├── geofence/                 # GeofencingClient bindings
│   ├── receiver/                 # Boot, notification action, geofence, activity broadcast receivers
│   ├── service/                  # ForegroundService, HeadlessService, HeadlessValidationService
│   └── storage/                  # Persistent queue, SharedPreferences wrappers
├── ios/Classes/                  # Swift + ObjC plugin (CLLocationManager, CMMotionActivityManager)
├── bin/                          # Dart CLI executables — setup, doctor, migrate, locus
├── test/                         # unit/ integration/ benchmark/ fixtures/ helpers/ mocks/
├── doc/                          # guides/ core/ reference/ advanced/ setup/ api/ testing/
└── example/                      # Example Flutter app consuming the plugin
```

Host apps import **only** `package:locus/locus.dart`. Everything under `lib/src/` is an implementation detail and not part of the semver contract. The `bin/` tools (`setup`, `doctor`) are declared as `executables:` in `pubspec.yaml` and run via `dart run locus:<tool>`.

## Code Style & Conventions

- Follow Dart style guide and effective Dart
- Use `dart format` for code formatting
- Prefer Riverpod for state management (if applicable)
- Use freezed for immutable models (if applicable)
- Separate presentation, domain, and data layers

## Key Dependencies

**Runtime** (see `pubspec.yaml`):

- `permission_handler` — Runtime prompts for location (fine, coarse, background), notifications, activity recognition, and battery-optimization exemption.
- `logging` — Structured `Logger` tree exposed through `LocusDiagnostics` and the debug overlay.
- `args` — Argument parsing for CLI executables (`bin/setup.dart`, `bin/doctor.dart`, `bin/migrate.dart`). CLI-only; reachable from `bin/` only, so Flutter tree-shakes it from host app bundles.

Anything previously delegated to a Dart-side helper now lives in native code: HTTP sync, queue/UUID generation, and OEM/manufacturer detection all run on the platform side and are exposed to Dart through `LocusChannels.methods` (e.g., `sync`, `getDiagnosticsMetadata`).

**Dev / test**:

- `flutter_test` — Widget + unit test harness.
- `flutter_lints` — Baseline lint set referenced by `analysis_options.yaml`.

**Native dependencies** (declared in `android/build.gradle` and the iOS podspec — relevant when changing platform code):

- Android: `play-services-location`, `play-services-activity-recognition`, `androidx.work`, `androidx.core`.
- iOS: `CoreLocation`, `CoreMotion`, `UserNotifications`.

The SDK deliberately keeps its Dart dependency surface **minimal** — no Riverpod, no freezed, no code-gen. All models are hand-written immutable data classes. This keeps plugin install size small, compile times fast, and avoids dragging host-app state-management opinions into an SDK. **Do not add runtime Dart dependencies without explicit approval** — every one becomes a transitive dependency for every consuming app.

## Quality Standards

- Quality over speed — always
- Spec before code for non-trivial changes (use the design-spec skill)
- Write or update tests alongside every change
- Evidence-based debugging: reproduce → trace → fix → verify
- Follow existing patterns in this codebase — consistency over preference

## Architecture

Locus is a **feature-first plugin** with a thin Dart facade over native implementations. Dependencies point inward: outer layers may depend on inner layers, never the reverse.

**Layers** (outer → inner):

1. **Host app** — consumes `package:locus/locus.dart` only. Never imports `lib/src/*`.
2. **Public API** (`lib/locus.dart`) — barrel exposing the `Locus` singleton, configs, models, events, and services.
3. **Feature modules** (`lib/src/features/<name>/`) — self-contained; each ships `models/` (pure data) and `services/` (behavior). Features depend on `shared/` and `core/`, **never on each other**.
4. **Core** (`lib/src/core/`) — the platform boundary:
   - `LocusInterface` — abstract contract.
   - `MethodChannelLocus` — default platform-channel implementation.
   - `locus_streams.dart` — typed event streams.
   - `locus_channels.dart` — channel names (single source of truth).
   - `locus_lifecycle.dart`, `locus_headless.dart` — lifecycle + headless entry points.
5. **Shared** (`lib/src/shared/`) — cross-cutting data types (`Coords`, `Activity`, `Battery`, event types). Zero behavior.
6. **Native** (`android/`, `ios/`) — owns the long-lived process: Android `ForegroundService` + `HeadlessService`, iOS background location delegates, persistent queue, geofence registration, activity recognition. Native emits typed events; Dart translates via `lib/src/core/event_mapper.dart`.

**Patterns**:

- **Platform Interface pattern** — `LocusInterface` + `MethodChannelLocus` lets `MockLocus` (`lib/src/testing/`) be swapped in via `Locus.setInstance(...)` for host-app tests.
- **Barrel exports per feature** — each feature exposes its public surface through `<feature>.dart`; everything else is package-private.
- **Event-sourced state** — native is the source of truth. `Locus.isTracking()` calls the platform; Dart never caches tracking state.
- **Headless execution** — Dart callbacks registered via `Locus.registerHeadlessTask` run in a second engine after the UI is killed. All headless entry points require `@pragma('vm:entry-point')`. See `doc/guides/headless-execution.md`.
- **CLI isolation** — `bin/` programs are pure Dart; they must not import `package:flutter/*`.

**Non-negotiables**:

- A feature must **never** import another feature's `models/` or `services/` — route through `shared/` or an event stream.
- `lib/src/` must **never** use `dart:io` for platform detection — go through `LocusInterface`.
- Native code must survive `onDetachedFromEngine` — the Flutter engine detaches whenever the UI is swiped away, and the background service must keep running.
- `stopOnTerminate: false` + `enableHeadless: true` + `foregroundService: true` is the canonical "always-on tracking" configuration; any change in lifecycle handling must be validated against it (see issue #34).

Reference: [`doc/core/architecture.md`](doc/core/architecture.md).

## Investigation & Research Rules

- All findings must cite concrete evidence (file:line, test output, logs)
- Use confidence labels: CONFIRMED, LIKELY, POSSIBLE
- Never guess at behavior — trace the actual code path
- When researching unfamiliar APIs or packages, search the web for current documentation
- Use the investigate, bug-hunt, or arch-audit skills for structured analysis
- Every fix must be verified — run tests, check build, confirm behavior
