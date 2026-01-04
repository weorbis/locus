# Privacy Zones

Privacy zones allow users to define areas where location tracking behavior is modified to protect their privacy. This is useful for home locations, workplaces, or other sensitive areas.

## Creating a Privacy Zone

```dart
final homeZone = PrivacyZone(
  identifier: 'home',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 150, // meters
  action: PrivacyZoneAction.exclude,
);

await Locus.addPrivacyZone(homeZone);
```

## Privacy Actions

Privacy zones support three actions:

| Action | Description |
|--------|-------------|
| `exclude` | Completely exclude locations from this zone |
| `obfuscate` | Randomize location within the zone |
| `reduce` | Reduce accuracy of locations in this zone |

### Exclude Action

No location updates are recorded or transmitted while in the zone:

```dart
PrivacyZone(
  identifier: 'home',
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 150,
  action: PrivacyZoneAction.exclude,
)
```

### Obfuscate Action

Locations are randomized within the zone to hide the exact position:

```dart
PrivacyZone(
  identifier: 'work',
  latitude: 37.7849,
  longitude: -122.4094,
  radius: 200,
  action: PrivacyZoneAction.obfuscate,
  obfuscationRadius: 100, // Random offset up to 100m
)
```

### Reduce Action

Location accuracy is reduced (coordinates are rounded):

```dart
PrivacyZone(
  identifier: 'neighborhood',
  latitude: 37.7649,
  longitude: -122.4294,
  radius: 500,
  action: PrivacyZoneAction.reduce,
)
```

## Managing Privacy Zones

```dart
// Get all privacy zones
final zones = await Locus.getPrivacyZones();

// Check if a zone exists
final exists = await Locus.privacyZoneExists('home');

// Remove a zone
await Locus.removePrivacyZone('home');

// Remove all zones
await Locus.removeAllPrivacyZones();
```

## Privacy Zone Events

Listen for when the user enters or exits privacy zones:

```dart
Locus.onPrivacyZone.listen((event) {
  if (event.type == PrivacyZoneEventType.enter) {
    print('Entered privacy zone: ${event.zone.identifier}');
  } else {
    print('Exited privacy zone: ${event.zone.identifier}');
  }
});
```

## Using the Privacy Zone Service

For more control, use the `PrivacyZoneService` directly:

```dart
final service = PrivacyZoneService();

// Add zones
await service.addZone(homeZone);

// Process a location through privacy filtering
final result = service.processLocation(location);

if (result.wasModified) {
  print('Location was modified by zone: ${result.zone?.identifier}');
}

// Use the filtered location
final safeLocation = result.location;
```

---

**Next:** [Trip Tracking](trips.md)
