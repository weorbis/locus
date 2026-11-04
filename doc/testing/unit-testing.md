# Testing Locus

Host-app tests can use `MockLocus` from the public
`package:locus/locus.dart` import. No separate testing package is needed.
Mocks exercise application behavior without native platform calls; they do
not establish that SQLite, permissions, or background delivery work on a device.

## Test a host app with MockLocus

Install the mock before using the Locus services, restore the previous provider
after each case, and dispose the mock's streams:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockLocus mock;
  late LocusInterface previous;

  setUp(() {
    previous = Locus.instance;
    mock = MockLocus();
    Locus.setMockInstance(mock);
  });

  tearDown(() async {
    Locus.setMockInstance(previous);
    await mock.dispose();
  });

  test('selects the matching history page', () async {
    mock.emitLocation(Location(
      uuid: 'stationary',
      timestamp: DateTime.utc(2026, 11, 3, 10),
      coords: const Coords(latitude: 52, longitude: 4, accuracy: 5),
      isMoving: false,
    ));
    mock.emitLocation(Location(
      uuid: 'moving',
      timestamp: DateTime.utc(2026, 11, 3, 11),
      coords: const Coords(latitude: 52, longitude: 4, accuracy: 5),
      isMoving: true,
    ));

    final page = await Locus.location.query(const LocationQuery(
      isMoving: true,
      sortOrder: LocationSortOrder.newestFirst,
      limit: 1,
    ));

    expect(page.map((location) => location.uuid), ['moving']);
  });
}
```

Use `mock.emitLocation`, `mock.emitGeofenceEvent`, `mock.emitActivityChange`,
and `mock.emitPowerStateChange` to supply events to application listeners.
Use concrete public model constructors, including required coordinates and UUIDs.
The mock does not reproduce native permission dialogs, SQL failures, or OS
process recovery.

## Run the SDK's Dart and example suites

From the repository root:

```bash
flutter test
flutter analyze --fatal-infos --fatal-warnings
```

From `example/`:

```bash
flutter test
flutter analyze --fatal-infos --fatal-warnings
```

The history regressions exercise different boundaries:

| Suite | What it checks |
| --- | --- |
| `test/unit/core/native_history_query_test.dart` | The public facade uses the native query channel; exact UTC microsecond arguments; bounded replies are not paged again; malformed replies, native errors, and unsupported hosts remain visible; summaries use the same path. |
| `test/unit/core/permission_assistant_test.dart` | The captured permission request result controls permanent-denial settings fallback without a later status query; ordinary denial and delegate errors remain visible. |
| `example/test/history_query_card_test.dart` | Fixed-window paging, filter resets, numeric/bounds validation, loading and retry states, disposal, clear-all scope, and a populated 320-pixel layout at twice the text scale. |

Dart channel tests simulate platform messages. They do not run the production
native plugin. The example card tests inject a query function so they can check
UI states without a device.

## Run native history checks

Android JVM argument checks reuse the existing JUnit dependency. From
`example/android/`:

```bash
./gradlew :locus:testDebugUnitTest :locus:assembleDebugAndroidTest
```

For real SQLite checks, use a dedicated emulator. Install
`example/build/locus/outputs/apk/androidTest/debug/locus-debug-androidTest.apk`
with `adb install -r`, then run:

```bash
adb shell am instrument -w dev.locus.test/dev.locus.core.ConfigSnapshotInstrumentation
```

The existing runner includes `NativeHistoryQueryChecks`: filters before paging,
sorting, inclusive edges, timestamp rounding, and normalized coordinates. It
requires the dedicated `dev.locus.test` package and uses temporary databases,
not the example app's history.

The iOS helper package runs actual SQLite queries against temporary fixture
files with isolated preferences:

```bash
swift test --package-path ios
LOCUS_NATIVE_TEST_MODULE=locus swift test --package-path ios --scratch-path ios/.build-lowercase
```

`NativeHistoryQueryTests` covers filtering and pagination, submillisecond and
historical dates, local DST gaps/overlaps, malformed stored data, and release
of the last storage reference on its database queue. The helper package does
not compile Flutter-dependent plugin files; use normal CocoaPods and SwiftPM
example builds to check those integrations.

CI runs Dart tests, Android JVM tests and instrumentation compilation, both
Swift helper module names, and CocoaPods/SwiftPM builds. It currently does not
execute Android instrumentation or the example widget suite. No CI workflow
was changed for this follow-up.

## Check the running example

Build and run the example on an emulator or simulator, then open
**Demos → Storage → Stored Locations**. On synthetic history, inspect first,
next, and previous pages; change a filter; check invalid inputs, empty results,
and a retry. Keep the captured window fixed while paging. Use a dedicated
installation before exercising **Clear all stored locations**, which removes
records outside the query too.

See [Querying stored history](../guides/querying-history.md) for the query
contract and [Contributing](../../CONTRIBUTING.md) for repository setup.
