# Locus Example Application

This is a demonstration application for the Locus Background Geolocation SDK. It showcases production-focused features and real-world tracking workflows.

## Features Demonstrated

- **Permission Handling**: requesting background location and motion activity permissions.
- **Service Lifecycle**: starting and stopping the background tracking service.
- **Event Monitoring**: real-time display of location updates, motion state changes, and provider authorization status.
- **Profiles & Automation**: profile presets, automation rules, and manual pace overrides.
- **Geofencing**: circular, polygon geofences, and delivery workflows.
- **Privacy Zones**: obfuscation zones and privacy events.
- **Sync & Queues**: sync policies, queue management, and dynamic headers.
- **Battery Optimization**: adaptive tracking presets and runway estimation.
- **Diagnostics & History**: diagnostics snapshot, native history filters, bounded pages, and summary stats.

## Getting Started

### 1. Configure Native Settings

Before running the example, ensure your environment is configured for background location. You can use the Locus CLI from the root of this example project (or the parent project):

```bash
dart run locus:setup
```

### 2. Run the Application

Navigate to the `example` directory and run the application:

```bash
flutter run
```

## Implementation Notes

`lib/main.dart` launches the app in `lib/app.dart`. The demo screens live in
`lib/demos/demos_screen.dart`; the history controls live in
`lib/demos/history_query_card.dart`.

### Explore stored history

Open **Demos → Storage → Stored Locations**. Choose a time window, timestamp
order, motion state, page size, optional accuracy limit, and optional geographic
bounds, then select **Apply query**. Accuracy is an upper bound in meters;
bounds include their edges and require south ≤ north and west ≤ east.

Each apply captures a fixed end time so moving between pages does not move the
time window. Changing a filter clears the old result and returns to the first
page on the next apply. The card requests the page size plus one record to
decide whether **Next page** is available; it does not fetch the whole history.
New or deleted records can still shift offset-based pages.

Loading disables actions; invalid inputs, native failures, empty results, and
retry actions are visible. **Clear all stored locations** removes every stored
record, including records outside the selected filters. Use a dedicated example
installation with synthetic data when checking this action.

Rebuild the native host after updating the plugin. Hot reload alone cannot add
the native query method. See [Querying stored history](../doc/guides/querying-history.md)
for the SDK contract and [Testing](../doc/testing/unit-testing.md) for the
widget, channel, and native storage checks.
