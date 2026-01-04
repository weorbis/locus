# Trip Tracking

Locus includes a trip detection and tracking system that automatically identifies and records trips based on movement patterns.

## Enabling Trip Detection

```dart
await Locus.ready(Config.balanced(
  url: 'https://api.example.com/locations',
  enableTripDetection: true,
));
```

## Trip Configuration

Customize trip detection parameters:

```dart
final tripConfig = TripConfig(
  minTripDistance: 500,      // Minimum trip distance in meters
  minTripDuration: Duration(minutes: 5),
  stopDetectionRadius: 50,   // Radius to detect stops
  stopDetectionTimeout: Duration(minutes: 3),
);

await Locus.configureTripDetection(tripConfig);
```

## Listening to Trip Events

```dart
Locus.onTripEvent.listen((event) {
  switch (event.type) {
    case TripEventType.started:
      print('Trip started at ${event.location}');
      break;
    case TripEventType.updated:
      print('Trip updated: ${event.state?.distance}m traveled');
      break;
    case TripEventType.ended:
      print('Trip ended: ${event.summary?.totalDistance}m');
      break;
  }
});
```

## Trip Summary

When a trip ends, you receive a comprehensive summary:

```dart
Locus.onTripEvent.listen((event) {
  if (event.type == TripEventType.ended) {
    final summary = event.summary!;
    print('Distance: ${summary.totalDistance}m');
    print('Duration: ${summary.duration}');
    print('Start: ${summary.startLocation}');
    print('End: ${summary.endLocation}');
    print('Route points: ${summary.routePoints.length}');
  }
});
```

## Manual Trip Control

You can also manually start and stop trips:

```dart
// Start a trip manually
await Locus.startTrip(metadata: {'purpose': 'delivery'});

// End the current trip
final summary = await Locus.endTrip();

// Check if a trip is active
final isActive = Locus.isTripActive;
```

## Trip Storage

Trips are automatically persisted and can be retrieved later:

```dart
final store = TripStore();

// Get all stored trips
final trips = await store.getAllTrips();

// Get trips in a date range
final recentTrips = await store.getTripsBetween(
  DateTime.now().subtract(Duration(days: 7)),
  DateTime.now(),
);
```

---

**Next:** [Battery Optimization](battery-optimization.md)
