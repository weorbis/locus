/// Mock implementation of TripService for testing.
library;

import 'dart:async';

import 'package:locus/locus.dart';

/// Mock trip service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockTripService();
/// 
/// // Start a trip
/// await mock.start(TripConfig(identifier: 'delivery-123'));
/// 
/// // Simulate trip progress
/// mock.simulateTripUpdate(distance: 1000, duration: Duration(minutes: 5));
/// 
/// // Stop trip
/// final summary = await mock.stop();
/// expect(summary?.totalDistance, 1000);
/// ```
class MockTripService implements TripService {
  TripState? _currentTrip;
  TripSummary? _lastSummary;
  
  final _eventsController = StreamController<TripEvent>.broadcast();
  final List<TripEvent> _eventHistory = [];

  @override
  Stream<TripEvent> get events => _eventsController.stream;

  @override
  Future<void> start(TripConfig config) async {
    if (_currentTrip != null) {
      throw StateError('A trip is already active');
    }
    
    _currentTrip = TripState(
      tripId: config.tripId ?? 'mock-trip-${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      startedAt: DateTime.now(),
      startLocation: null,
      lastLocation: null,
      distanceMeters: 0,
      idleSeconds: 0,
      maxSpeedKph: 0,
      started: true,
      ended: false,
    );
    
    final event = TripEvent(
      type: TripEventType.tripStart,
      tripId: _currentTrip!.tripId,
      timestamp: DateTime.now(),
    );
    
    _eventsController.add(event);
    _eventHistory.add(event);
  }

  @override
  Future<TripSummary?>? stop() async {
    if (_currentTrip == null) return null;
    
    final endTime = DateTime.now();
    final durationSeconds = _currentTrip!.startedAt != null
        ? endTime.difference(_currentTrip!.startedAt!).inSeconds
        : 0;
    
    final summary = TripSummary(
      tripId: _currentTrip!.tripId,
      startedAt: _currentTrip!.startedAt ?? _currentTrip!.createdAt,
      endedAt: endTime,
      distanceMeters: _currentTrip!.distanceMeters,
      durationSeconds: durationSeconds,
      idleSeconds: _currentTrip!.idleSeconds,
      maxSpeedKph: _currentTrip!.maxSpeedKph,
      averageSpeedKph: _calculateAverageSpeed(),
    );
    
    _lastSummary = summary;
    
    final event = TripEvent(
      type: TripEventType.tripEnd,
      tripId: _currentTrip!.tripId,
      timestamp: DateTime.now(),
      summary: summary,
    );
    
    _eventsController.add(event);
    _eventHistory.add(event);
    
    _currentTrip = null;
    return summary;
  }

  @override
  TripState? getState() {
    return _currentTrip;
  }

  @override
  StreamSubscription<TripEvent> onEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return _eventsController.stream.listen(
      callback,
      onError: onError,
    );
  }

  // ============================================================
  // Test Helpers
  // ============================================================

  /// Simulates a trip update with new data.
  void simulateTripUpdate({
    Location? location,
    double? distance,
    Duration? duration,
    double? speed,
  }) {
    if (_currentTrip == null) {
      throw StateError('No active trip to update');
    }
    
    _currentTrip = TripState(
      tripId: _currentTrip!.tripId,
      createdAt: _currentTrip!.createdAt,
      startedAt: _currentTrip!.startedAt,
      startLocation: _currentTrip!.startLocation ?? location,
      lastLocation: location ?? _currentTrip!.lastLocation,
      distanceMeters: distance ?? _currentTrip!.distanceMeters,
      idleSeconds: _currentTrip!.idleSeconds,
      maxSpeedKph: speed != null
          ? (speed > _currentTrip!.maxSpeedKph ? speed : _currentTrip!.maxSpeedKph)
          : _currentTrip!.maxSpeedKph,
      started: true,
      ended: false,
    );
    
    final event = TripEvent(
      type: TripEventType.tripUpdate,
      tripId: _currentTrip!.tripId,
      timestamp: DateTime.now(),
      location: location,
    );
    
    _eventsController.add(event);
    _eventHistory.add(event);
  }

  /// Simulates location updates along a route.
  Future<void> simulateRoute(
    List<Location> locations, {
    Duration interval = const Duration(seconds: 5),
  }) async {
    if (_currentTrip == null) {
      throw StateError('No active trip to update');
    }
    
    for (var i = 0; i < locations.length; i++) {
      final location = locations[i];
      
      // Calculate distance from previous location
      double distanceIncrement = 0;
      if (i > 0) {
        final prev = locations[i - 1];
        distanceIncrement = _calculateDistance(
          prev.coords.latitude,
          prev.coords.longitude,
          location.coords.latitude,
          location.coords.longitude,
        );
      }
      
      simulateTripUpdate(
        location: location,
        distance: _currentTrip!.distanceMeters + distanceIncrement,
        speed: location.coords.speed,
      );
      
      if (i < locations.length - 1) {
        await Future.delayed(interval);
      }
    }
  }

  /// Pauses the current trip.
  void pause() {
    if (_currentTrip == null) return;
    
    _currentTrip = TripState(
      tripId: _currentTrip!.tripId,
      createdAt: _currentTrip!.createdAt,
      startedAt: _currentTrip!.startedAt,
      startLocation: _currentTrip!.startLocation,
      lastLocation: _currentTrip!.lastLocation,
      distanceMeters: _currentTrip!.distanceMeters,
      idleSeconds: _currentTrip!.idleSeconds,
      maxSpeedKph: _currentTrip!.maxSpeedKph,
      started: false,
      ended: false,
    );
    
    final event = TripEvent(
      type: TripEventType.dwell,
      tripId: _currentTrip!.tripId,
      timestamp: DateTime.now(),
    );
    
    _eventsController.add(event);
    _eventHistory.add(event);
  }

  /// Resumes a paused trip.
  void resume() {
    if (_currentTrip == null) return;
    
    _currentTrip = TripState(
      tripId: _currentTrip!.tripId,
      createdAt: _currentTrip!.createdAt,
      startedAt: _currentTrip!.startedAt,
      startLocation: _currentTrip!.startLocation,
      lastLocation: _currentTrip!.lastLocation,
      distanceMeters: _currentTrip!.distanceMeters,
      idleSeconds: _currentTrip!.idleSeconds,
      maxSpeedKph: _currentTrip!.maxSpeedKph,
      started: true,
      ended: false,
    );
    
    final event = TripEvent(
      type: TripEventType.tripUpdate,
      tripId: _currentTrip!.tripId,
      timestamp: DateTime.now(),
    );
    
    _eventsController.add(event);
    _eventHistory.add(event);
  }

  /// Gets the last completed trip summary.
  TripSummary? get lastSummary => _lastSummary;

  /// Gets the event history.
  List<TripEvent> get eventHistory => List.unmodifiable(_eventHistory);

  /// Clears event history.
  void clearHistory() {
    _eventHistory.clear();
  }

  double _calculateAverageSpeed() {
    if (_currentTrip == null) return 0;
    
    final durationSeconds = _currentTrip!.startedAt != null
        ? DateTime.now().difference(_currentTrip!.startedAt!).inSeconds
        : 0;
    
    if (durationSeconds == 0) return 0;
    
    final movingSeconds = (durationSeconds - _currentTrip!.idleSeconds).clamp(0, durationSeconds);
    if (movingSeconds == 0) return 0;
    
    return (_currentTrip!.distanceMeters / movingSeconds) * 3.6;
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = (lat2 - lat1) * 0.017453292519943295;
    final dLon = (lon2 - lon1) * 0.017453292519943295;
    
    final a = (dLat / 2) * (dLat / 2) +
        (lat1 * 0.017453292519943295).cos() *
            (lat2 * 0.017453292519943295).cos() *
            (dLon / 2) *
            (dLon / 2);
    
    final c = 2 * a.sqrt().atan2((1 - a).sqrt());
    return earthRadius * c;
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _eventsController.close();
  }
}

extension on double {
  double cos() => this;
  double sqrt() => this;
  double atan2(double x) => this;
}
