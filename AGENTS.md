# locus

Locus is a **Flutter plugin, not an application**: a background geolocation SDK with native
Android (Kotlin) and iOS (Swift) implementations behind a thin Dart facade. Host apps import only
`package:locus/locus.dart` — everything under `lib/src/` is an implementation detail and outside
the semver contract. Dependencies, executables, and the SDK version live in `pubspec.yaml`.

## Commands

```bash
flutter pub get
flutter analyze --fatal-infos --fatal-warnings    # CI treats infos and warnings as errors
dart format --set-exit-if-changed --output=none .
flutter test --coverage
dart run tool/sync_version.dart --check           # version pins in sync with pubspec

# Native lanes run from the example app, not from the plugin root
example/android/gradlew --project-dir example/android :locus:testDebugUnitTest :locus:lintDebug
example/android/gradlew --project-dir example/android :locus:assembleDebugAndroidTest
# Install the resulting dev.locus.test APK on a dedicated emulator, then:
adb shell am instrument -w dev.locus.test/dev.locus.core.ConfigSnapshotInstrumentation
swift test --package-path ios
LOCUS_NATIVE_TEST_MODULE=locus swift test --package-path ios --scratch-path ios/.build-lowercase
cd example && flutter test                        # example widgets and harness
bash tool/android_process_recovery_smoke.sh       # process-death recovery smoke

cd example && flutter run                         # the plugin has no runnable entry point
```

`.github/workflows/pipeline.yml` is the real gate: code quality, `pana` score threshold 130,
Android JVM tests/lint/instrumentation compilation, and iOS helper tests plus builds under
**both** CocoaPods and SwiftPM. It does not currently execute an Android emulator matrix.
The release job runs on main/master pushes and creates a release only when the pubspec version
has no remote tag; publishing to pub.dev is manual.

## Structure

```
lib/
├── locus.dart                # Single public entry point — barrel re-exports only
└── src/
    ├── core/                 # Platform boundary: channels, LocusInterface, streams, lifecycle
    ├── config/               # Config, presets, validators, enums, constants
    ├── features/             # Feature-first modules, each with models/ + services/
    │                         #   location, geofencing, battery, privacy, trips, sync,
    │                         #   tracking, diagnostics
    ├── services/             # Service interfaces + default implementations
    ├── shared/               # Cross-cutting data types (Coords, Activity, Battery, events)
    └── testing/              # MockLocus — for host-app tests
android/src/main/kotlin/dev/locus/   # LocusPlugin + core/ location/ activity/ geofence/
                                     # receiver/ service/ storage/
ios/locus/Sources/locus/             # Swift + ObjC plugin (CocoaPods and SwiftPM)
bin/                                 # Pure-Dart CLIs: locus, setup, doctor, migrate
test/                                # unit/ integration/ benchmark/ fixtures/ helpers/ mocks/
doc/                                 # Published guides; doc/core/architecture.md is canonical
example/                             # Example app — also the host for every native test lane
```

`bin/` tools are declared as `executables:` in `pubspec.yaml` and run via `dart run locus:<tool>`.

## Architecture

Feature-first, dependencies point inward, outer layers never imported by inner ones:
host app → public barrel (`lib/locus.dart`) → feature modules → core → shared → native.

Native owns the long-lived process (Android `ForegroundService` + `HeadlessService`, iOS
background location delegates, persistent queue, geofence registration, activity recognition) and
emits typed events that `lib/src/core/event_mapper.dart` translates for Dart.

- **Platform Interface pattern** — `LocusInterface` + `MethodChannelLocus` let host apps swap in
  `MockLocus` via `Locus.setMockInstance(...)` for their own tests.
- **Event-sourced state** — native is the source of truth. `Locus.isTracking()` calls the
  platform; Dart never caches tracking state.
- **Headless execution** — callbacks registered via `Locus.registerHeadlessTask` run in a second
  engine after the UI is killed, and every headless entry point needs `@pragma('vm:entry-point')`.
  See `doc/guides/headless-execution.md`.
- **Barrel exports per feature** — each feature exposes its surface through `<feature>.dart`.

Non-negotiables:

- A feature must **never** import another feature's `models/` or `services/` — route through
  `shared/` or an event stream.
- `lib/src/` must **never** use `dart:io` for platform detection — go through `LocusInterface`.
- `bin/` programs are pure Dart and must not import `package:flutter/*`.
- Native code must survive `onDetachedFromEngine`: the engine detaches whenever the UI is swiped
  away, and the background service has to keep running.
- `stopOnTerminate: false` + `enableHeadless: true` + `foregroundService: true` is the canonical
  always-on tracking configuration. Validate any lifecycle change against it (see issue #34).

## Gotchas

- **Minimal dependency surface is deliberate.** No Riverpod, no freezed, no code generation — all
  models are hand-written immutable data classes, which keeps install size and compile times down
  and keeps SDK opinions out of host apps. Do not add a runtime Dart dependency without explicit
  approval; each one becomes transitive for every consuming app.
- **`args` must stay in `dependencies:`,** not `dev_dependencies:`. Pub's `executables:` contract
  requires it so `dart run locus:setup` works for consumers.
- **`pubspec.yaml` is the single source of the version.** After bumping, run
  `dart run tool/sync_version.dart` to propagate into the Dart constants; Gradle and the podspec
  read the line directly at build time.
- **HTTP sync, queue/UUID generation, and OEM detection live in native code,** not Dart — reach
  them through `LocusChannels.methods` (`sync`, `getDiagnosticsMetadata`, …).
- **History queries filter and page natively.** The private `queryLocations` channel uses UTC
  epoch microseconds, applies every predicate before LIMIT/OFFSET, and leaves legacy
  `getLocations` unchanged. Do not add a fetch-all Dart fallback. See `doc/guides/querying-history.md`.
- **iOS ships under two module names** (`locus` and `Locus`); native tests run against both.
- `dart format` run directly may print package-resolution warnings; they are expected and the
  lints resolve correctly under `flutter analyze`.
