/// Trip service interface for v2.0 API.
///
/// Provides a clean, organized API for trip tracking operations.
/// Access via `Locus.trips`.
library;

import 'dart:async';

import 'package:locus/src/models.dart';

/// Service interface for trip tracking operations.
///
/// Trips represent distinct journeys with start/end points, routes,
/// and associated metadata. Use this for delivery tracking, commute
/// logging, or any journey-based feature.
///
/// Example:
/// ```dart
/// // Start a trip
/// await Locus.trips.start(TripConfig(
///   identifier: 'delivery-123',
///   metadata: {'orderId': 'ABC123'},
/// ));
///
/// // Listen to trip events
/// Locus.trips.events.listen((event) {
///   switch (event.type) {
///     case TripEventType.started:
///       print('Trip started');
///       break;
///     case TripEventType.updated:
///       print('Trip updated: ${event.distance}m');
///       break;
///     case TripEventType.completed:
///       print('Trip completed: ${event.summary}');
///       break;
///   }
/// });
///
/// // Stop the trip
/// final summary = await Locus.trips.stop();
/// print('Total distance: ${summary?.totalDistance}m');
/// ```
abstract class TripService {
  /// Stream of trip events.
  Stream<TripEvent> get events;

  /// Starts a new trip with the given configuration.
  Future<void> start(TripConfig config);

  /// Stops the current trip and returns a summary.
  ///
  /// Returns null if no trip is active.
  Future<TripSummary?>? stop();

  /// Gets the current trip state.
  ///
  /// Returns null if no trip is active.
  TripState? getState();

  /// Subscribes to trip events.
  StreamSubscription<TripEvent> onEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  });
}
