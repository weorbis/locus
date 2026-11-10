# Replay a route through the real engine

`dart run locus:replay` feeds a GPX or JSON route into an Android emulator or
an iOS simulator using the operating system's developer tools. The host app
continues to use the real Locus plugin. No replay channel, configuration flag,
or location injection is added to the shipped SDK.

## Run a replay

Start an emulator or boot an iOS simulator, install and open your host app (or
`example/`), grant location permissions, and start Locus tracking. Android needs
`adb` on PATH; iOS needs macOS, Xcode and `xcrun simctl`.

```bash
dart run locus:replay --help
dart run locus:replay --platform android route.gpx
dart run locus:replay --platform android --device emulator-5554 --speed-multiplier 5 route.gpx
dart run locus:replay --platform ios --device SIMULATOR-UDID --interval 2 route.json
dart run locus replay --platform android --dry-run route.gpx
```

Select `--platform android` or `--platform ios`. Within that platform, the CLI
selects the only ready emulator or booted iOS simulator. If there are several,
pass `--device` with an Android emulator serial (`adb devices`) or iOS simulator
UDID (`xcrun simctl list devices booted`). Physical Android devices are excluded;
physical iOS devices use Xcode as described below.

`--dry-run` reads and validates the whole file, then prints commands and waits
without invoking external tools, waiting, or changing a device. Without
`--device`, it prints a `<device>` placeholder. With `--loop`, the preview shows
one pass only.

## Files and timing

GPX accepts `trkpt`, `rtept`, and `wpt` points, including namespace-prefixed tags,
with required `lat` and `lon` attributes and optional `ele` and `time` children.
Points from all tracks, segments, routes and waypoints play in document order;
they are not sorted or joined geographically. Select one route before replaying
if a file contains unrelated routes. DTDs and custom XML entities are rejected.

Save this as `route.gpx` to preview a short route:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Locus replay" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="37.4220" lon="-122.0840">
      <ele>10</ele><time>2026-11-10T12:00:00Z</time>
    </trkpt>
    <trkpt lat="37.4221" lon="-122.0841">
      <ele>12</ele><time>2026-11-10T12:00:02Z</time>
    </trkpt>
  </trkseg></trk>
</gpx>
```

The simple JSON format is an array of objects. Coordinates and elevations are
finite numbers in degrees and meters. Latitude must be between -90 and 90;
longitude between -180 and 180. Timestamps are ISO 8601 strings with an explicit
timezone, not numeric epoch values.

```json
[
  {"lat": 37.4220, "lng": -122.0840, "ele": 10, "ts": "2026-11-10T12:00:00Z"},
  {"lat": 37.4221, "lng": -122.0841, "ele": 12, "ts": "2026-11-10T12:00:02Z"}
]
```

`lon` is also accepted for `lng`. SDK-shaped objects may use
`coords.latitude`, `coords.longitude`, `coords.altitude`, and `timestamp`;
flat `latitude`/`longitude`/`altitude` fields are also accepted.

The example harness's exported JSON envelope (`exportedAt`, `count`, `events`)
is accepted directly. Only events with `category: "location"` and
`type: "location_update"` are replayed. Locations come from `payload.coords`
or the recorder's flat payload fallback. The location's `timestamp` takes
precedence over the event observation time `at`. Other events are ignored;
a file without location events is an error. Malformed location entries fail
before any device receives a command. Recordings may contain sensitive routes;
keep customer traces local and out of source control.

The first point is immediate. By default, subsequent points preserve adjacent
recorded time gaps, divided by `--speed-multiplier` (default `1`). A gap missing
either timestamp uses one second divided by the multiplier, with a notice.
Equal timestamps are immediate; decreasing timestamps are rejected.
`--interval SECONDS` instead uses a fixed positive gap, ignores timestamps for
scheduling, and cannot be combined with `--speed-multiplier`. Scheduled positive gaps must
be at least one microsecond and fit in a Dart duration. Command startup
and OS delivery add latency, so replay is approximate rather than a precise clock.

`--loop` repeats until Ctrl+C, jumping back to the first point after one fixed
interval (or the one-second fallback divided by the multiplier). Ctrl+C cancels
pending waits and exits with status 130. On iOS, completion, interruption and
command failure all attempt `simctl location <device> clear`. If the simulator
becomes unavailable, cleanup reports an error; clear it manually once it returns.
A forced kill cannot run cleanup. Android retains the last simulated fix.

## Platform behavior

Android sends one `adb -s <serial> emu geo fix <longitude> <latitude> [altitude]`
per point, matching `tool/android_process_recovery_smoke.sh`. There is no
interpolation between points.

iOS uses `xcrun simctl location <device> start --speed=<m/s> --interval=<s>` for
each moving segment, calculating speed from the segment distance and desired
duration. The simulator interpolates between its endpoints. Its `--interval`
controls location update frequency, not segment duration; the CLI uses at most
one second between updates. Stationary and instantaneous segments use `set`
and waits. Endpoints are explicitly set after each segment. A single-point
route uses `set`. The final location is held for one fixed/fallback interval
before clearing it, giving the simulator time to deliver the endpoint. `simctl` routes accept latitude and longitude only, so altitude
is ignored with a notice. Check your installed flags with
`xcrun simctl help location`.

These fixes enter the OS location pipeline, allowing your configured host app
to exercise native location handling, OS geofence registration and delivery,
location persistence, the sync queue and HTTP requests, and location-driven
trip behavior. Register geofences along the route, configure a development sync
endpoint, and inspect events and stored history in the example harness. Give
geofences enough distance and dwell time; a rapid route can skip transitions.
Simulation alone does not guarantee every OS geofence or background callback.
It does not reproduce activity sensors, GPS reception, battery conditions,
process termination or background relaunch policy. Trip detection can also
depend on motion activity and configuration. Use separate lifecycle checks and
real-device runs for those behaviors. Mock-location filtering may reject OS
simulation if enabled in the host's configuration.

## OS-level alternatives

- **Android Emulator:** open Extended controls → Location → Routes and use
  **Import GPX/KML**, then play the route with the desired speed and repeat
  setting. The CLI accepts GPX and JSON; KML import belongs to the emulator UI.
  See [Android's extended controls guide](https://developer.android.com/studio/run/emulator-extended-controls#location).
- **Xcode, including a connected physical iOS device:** add a GPX file to the
  host app's Xcode project, choose Product → Scheme → Edit Scheme → Run →
  Options, enable **Allow Location Simulation**, and select the GPX file as
  **Default Location**. Run the development-signed app with the device selected.
  You can also choose the GPX file under Debug → Simulate Location during a
  debug session. Stop simulation there when finished. This requires Xcode's
  debugging connection; `simctl` cannot target a physical iPhone.
  See [Apple's scheme location guide](https://help.apple.com/xcode/mac/current/en.lproj/dev8dbd2f820.html).

Keep OS simulation distinct from `MockLocus`: a swapped-in mock bypasses the
native engine, while this CLI leaves the host's real plugin instance in place.
