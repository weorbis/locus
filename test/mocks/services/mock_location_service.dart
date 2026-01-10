/// Mock implementation of LocationService for testing.
library;

import 'dart:async';

import 'package:locus/locus.dart';

/// Mock location service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockLocationService();
///
/// // Emit locations
/// mock.emitLocation(Location(...));
///
/// // Simulate movement
/// await mock.simulateRoute([
///   (37.4219, -122.084),
///   (37.4220, -122.083),
/// ]);
///
/// // Query history
/// final locations = await mock.query(LocationQuery(...));
/// ```
class MockLocationService implements LocationService {
  final List<Location> _locations = [];
  bool _isMoving = false;
  double _odometer = 0.0;

  final _locationController = StreamController<Location>.broadcast();
  final _motionChangeController = StreamController<Location>.broadcast();
  final _heartbeatController = StreamController<Location>.broadcast();

  @override
  Stream<Location> get stream => _locationController.stream;

  @override
  Stream<Location> get motionChanges => _motionChangeController.stream;

  @override
  Stream<Location> get heartbeats => _heartbeatController.stream;

  /// Emits a mock location update.
  void emitLocation(Location location) {
    _locations.add(location);
    _locationController.add(location);

    // Auto-update motion state
    if (location.isMoving != null && location.isMoving != _isMoving) {
      _isMoving = location.isMoving!;
      _motionChangeController.add(location);
    }
  }

  /// Emits a heartbeat location (stationary update).
  void emitHeartbeat(Location location) {
    _locations.add(location);
    _heartbeatController.add(location);
  }

  /// Simulates a route with multiple waypoints.
  ///
  /// Locations are emitted with the specified interval between them.
  Future<void> simulateRoute(
    List<(double lat, double lng)> waypoints, {
    Duration interval = const Duration(seconds: 1),
    double speed = 5.0, // m/s
    double accuracy = 10.0,
  }) async {
    for (var i = 0; i < waypoints.length; i++) {
      final (lat, lng) = waypoints[i];
      final location = Location(
        uuid: 'sim-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        coords: Coords(
          latitude: lat,
          longitude: lng,
          accuracy: accuracy,
          speed: speed,
          heading: 0,
          altitude: 0,
        ),
        isMoving: speed > 0,
        odometer: _odometer,
      );

      emitLocation(location);

      // Calculate distance to next waypoint and update odometer
      if (i < waypoints.length - 1) {
        final next = waypoints[i + 1];
        _odometer += _calculateDistance(lat, lng, next.$1, next.$2);
      }

      if (i < waypoints.length - 1) {
        await Future.delayed(interval);
      }
    }
  }

  @override
  Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    JsonMap? extras,
  }) async {
    if (_locations.isNotEmpty) {
      return _locations.last;
    }

    // Return a default mock location
    final location = Location(
      uuid: 'mock-current',
      timestamp: DateTime.now(),
      coords: const Coords(
        latitude: 0,
        longitude: 0,
        accuracy: 10,
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      isMoving: false,
      odometer: _odometer,
      extras: extras,
    );

    if (persist ?? false) {
      _locations.add(location);
    }

    return location;
  }

  @override
  Future<List<Location>> getLocations({int? limit}) async {
    if (limit != null && limit < _locations.length) {
      return _locations.sublist(_locations.length - limit);
    }
    return List.unmodifiable(_locations);
  }

  @override
  Future<List<Location>> query(LocationQuery query) async {
    return query.apply(_locations);
  }

  @override
  Future<LocationSummary> getSummary({
    DateTime? date,
    LocationQuery? query,
  }) async {
    LocationQuery effectiveQuery;

    if (query != null) {
      effectiveQuery = query;
    } else if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      effectiveQuery = LocationQuery(from: startOfDay, to: endOfDay);
    } else {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      effectiveQuery = LocationQuery(from: startOfDay, to: now);
    }

    final locations = await this.query(effectiveQuery);
    return LocationHistoryCalculator.calculateSummary(locations);
  }

  @override
  Future<bool> changePace(bool isMoving) async {
    _isMoving = isMoving;
    return true;
  }

  @override
  Future<double> setOdometer(double value) async {
    _odometer = value;
    return value;
  }

  @override
  Future<bool> destroyLocations() async {
    _locations.clear();
    return true;
  }

  /// Gets the current motion state.
  bool get isMoving => _isMoving;

  /// Gets the current odometer reading.
  double get odometer => _odometer;

  /// Clears all stored locations.
  void clear() {
    _locations.clear();
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = (lat2 - lat1) * 0.017453292519943295; // Convert to radians
    final dLon = (lon2 - lon1) * 0.017453292519943295;

    final a = (dLat / 2).sin() * (dLat / 2).sin() +
        (lat1 * 0.017453292519943295).cos() *
            (lat2 * 0.017453292519943295).cos() *
            (dLon / 2).sin() *
            (dLon / 2).sin();

    final c = 2 * a.sqrt().atan2((1 - a).sqrt());
    return earthRadius * c;
  }

  @override
  StreamSubscription<Location> onLocation(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _locationController.stream.listen(
      callback,
      onError: onError,
    );
  }

  @override
  StreamSubscription<Location> onMotionChange(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _motionChangeController.stream.listen(
      callback,
      onError: onError,
    );
  }

  @override
  StreamSubscription<Location> onHeartbeat(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _heartbeatController.stream.listen(
      callback,
      onError: onError,
    );
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _locationController.close();
    await _motionChangeController.close();
    await _heartbeatController.close();
  }
}

extension on double {
  double sin() => this;
  double cos() => this;
  double sqrt() => this;
  double atan2(double x) => this;
}
