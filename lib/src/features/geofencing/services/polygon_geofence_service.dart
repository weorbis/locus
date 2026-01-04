import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:locus/src/features/geofencing/models/polygon_geofence.dart';

/// Callback for polygon geofence persistence.
typedef PolygonGeofencePersistCallback = Future<void> Function(
    List<PolygonGeofence> geofences);

/// Service for managing polygon geofences.
///
/// This service handles:
/// - Adding, removing, and updating polygon geofences
/// - Checking if a location is inside any registered polygon
/// - Emitting events when polygon boundaries are crossed
///
/// Example:
/// ```dart
/// final service = PolygonGeofenceService();
///
/// // Define a polygon (e.g., a parking lot)
/// final parkingLot = PolygonGeofence(
///   identifier: 'parking-lot-1',
///   vertices: [
///     GeoPoint(latitude: 37.4219, longitude: -122.0840),
///     GeoPoint(latitude: 37.4220, longitude: -122.0830),
///     GeoPoint(latitude: 37.4215, longitude: -122.0828),
///     GeoPoint(latitude: 37.4214, longitude: -122.0838),
///   ],
/// );
///
/// await service.addPolygonGeofence(parkingLot);
///
/// // Check if a point is inside
/// final isInside = service.isLocationInAnyPolygon(37.4217, -122.0834);
/// ```
class PolygonGeofenceService {
  final Map<String, PolygonGeofence> _polygons = {};
  final Map<String, bool> _insideState = {};

  final StreamController<PolygonGeofenceEvent> _eventController =
      StreamController<PolygonGeofenceEvent>.broadcast();

  PolygonGeofencePersistCallback? _onPersist;

  /// Stream of polygon geofence events (enter, exit, dwell).
  Stream<PolygonGeofenceEvent> get events => _eventController.stream;

  /// Returns all registered polygon geofences.
  List<PolygonGeofence> get polygons => List.unmodifiable(_polygons.values);

  /// Returns the number of registered polygon geofences.
  int get count => _polygons.length;

  /// Sets a callback to persist polygon geofences.
  void setOnPersist(PolygonGeofencePersistCallback? callback) {
    _onPersist = callback;
  }

  /// Adds a polygon geofence.
  ///
  /// Throws [ArgumentError] if the polygon is invalid.
  /// Returns true if added successfully, false if identifier already exists.
  Future<bool> addPolygonGeofence(PolygonGeofence polygon) async {
    if (!polygon.isValid) {
      throw ArgumentError(
          'Invalid polygon geofence: ${polygon.identifier}. '
          'Must have non-empty identifier and at least 3 valid vertices.');
    }

    if (_polygons.containsKey(polygon.identifier)) {
      debugPrint(
          '[PolygonGeofenceService] Polygon already exists: ${polygon.identifier}');
      return false;
    }

    _polygons[polygon.identifier] = polygon;
    _insideState[polygon.identifier] = false;
    await _persist();

    debugPrint(
        '[PolygonGeofenceService] Added polygon: ${polygon.identifier} '
        '(${polygon.vertices.length} vertices)');
    return true;
  }

  /// Adds multiple polygon geofences.
  ///
  /// Returns the number of polygons successfully added.
  Future<int> addPolygonGeofences(List<PolygonGeofence> polygons) async {
    int added = 0;

    for (final polygon in polygons) {
      if (polygon.isValid && !_polygons.containsKey(polygon.identifier)) {
        _polygons[polygon.identifier] = polygon;
        _insideState[polygon.identifier] = false;
        added++;
      }
    }

    if (added > 0) {
      await _persist();
      debugPrint('[PolygonGeofenceService] Added $added polygon geofences');
    }

    return added;
  }

  /// Removes a polygon geofence by identifier.
  ///
  /// Returns true if removed, false if not found.
  Future<bool> removePolygonGeofence(String identifier) async {
    final removed = _polygons.remove(identifier);
    _insideState.remove(identifier);

    if (removed != null) {
      await _persist();
      debugPrint('[PolygonGeofenceService] Removed polygon: $identifier');
      return true;
    }

    return false;
  }

  /// Removes all polygon geofences.
  Future<void> removeAllPolygonGeofences() async {
    _polygons.clear();
    _insideState.clear();
    await _persist();
    debugPrint('[PolygonGeofenceService] Removed all polygon geofences');
  }

  /// Gets a polygon geofence by identifier.
  PolygonGeofence? getPolygonGeofence(String identifier) {
    return _polygons[identifier];
  }

  /// Returns true if a polygon with the given identifier exists.
  bool polygonExists(String identifier) {
    return _polygons.containsKey(identifier);
  }

  /// Updates an existing polygon geofence.
  ///
  /// Returns true if updated, false if not found.
  Future<bool> updatePolygonGeofence(PolygonGeofence polygon) async {
    if (!_polygons.containsKey(polygon.identifier)) {
      return false;
    }

    if (!polygon.isValid) {
      throw ArgumentError('Invalid polygon geofence: ${polygon.identifier}');
    }

    _polygons[polygon.identifier] = polygon;
    await _persist();

    debugPrint('[PolygonGeofenceService] Updated polygon: ${polygon.identifier}');
    return true;
  }

  /// Checks if a location is inside any registered polygon.
  ///
  /// Returns the list of polygon identifiers containing the point.
  List<String> getContainingPolygons(double latitude, double longitude) {
    final containing = <String>[];

    for (final polygon in _polygons.values) {
      if (polygon.containsPoint(latitude, longitude)) {
        containing.add(polygon.identifier);
      }
    }

    return containing;
  }

  /// Returns true if the location is inside any registered polygon.
  bool isLocationInAnyPolygon(double latitude, double longitude) {
    for (final polygon in _polygons.values) {
      if (polygon.containsPoint(latitude, longitude)) {
        return true;
      }
    }
    return false;
  }

  /// Processes a location update and emits events for polygon boundary crossings.
  ///
  /// Call this method with each location update to trigger enter/exit events.
  void processLocationUpdate(double latitude, double longitude) {
    final now = DateTime.now();
    final triggerPoint = GeoPoint(latitude: latitude, longitude: longitude);

    for (final polygon in _polygons.values) {
      final wasInside = _insideState[polygon.identifier] ?? false;
      final isNowInside = polygon.containsPoint(latitude, longitude);

      if (!wasInside && isNowInside) {
        // Entered polygon
        _insideState[polygon.identifier] = true;

        if (polygon.notifyOnEntry) {
          _eventController.add(PolygonGeofenceEvent(
            geofence: polygon,
            type: PolygonGeofenceEventType.enter,
            timestamp: now,
            triggerLocation: triggerPoint,
          ));
          debugPrint(
              '[PolygonGeofenceService] ENTER: ${polygon.identifier}');
        }
      } else if (wasInside && !isNowInside) {
        // Exited polygon
        _insideState[polygon.identifier] = false;

        if (polygon.notifyOnExit) {
          _eventController.add(PolygonGeofenceEvent(
            geofence: polygon,
            type: PolygonGeofenceEventType.exit,
            timestamp: now,
            triggerLocation: triggerPoint,
          ));
          debugPrint(
              '[PolygonGeofenceService] EXIT: ${polygon.identifier}');
        }
      }
    }
  }

  /// Returns true if currently inside the specified polygon.
  bool isInsidePolygon(String identifier) {
    return _insideState[identifier] ?? false;
  }

  /// Resets the inside state for all polygons.
  ///
  /// Use this when restarting tracking or after significant location jumps.
  void resetState() {
    for (final key in _insideState.keys) {
      _insideState[key] = false;
    }
    debugPrint('[PolygonGeofenceService] Reset inside state');
  }

  /// Initializes the service with persisted polygons.
  void restore(List<PolygonGeofence> polygons) {
    _polygons.clear();
    _insideState.clear();

    for (final polygon in polygons) {
      if (polygon.isValid) {
        _polygons[polygon.identifier] = polygon;
        _insideState[polygon.identifier] = false;
      }
    }

    debugPrint(
        '[PolygonGeofenceService] Restored ${_polygons.length} polygon geofences');
  }

  Future<void> _persist() async {
    if (_onPersist != null) {
      await _onPersist!(_polygons.values.toList());
    }
  }

  /// Disposes resources.
  void dispose() {
    _eventController.close();
  }
}
