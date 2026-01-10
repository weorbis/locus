/// Mock implementation of GeofenceService for testing.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:locus/locus.dart';

/// Mock geofence service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockGeofenceService();
///
/// // Add geofences
/// await mock.add(Geofence(
///   identifier: 'home',
///   latitude: 37.4219,
///   longitude: -122.084,
///   radius: 100,
/// ));
///
/// // Simulate entering a geofence
/// mock.triggerEntry('home');
///
/// // Listen to events
/// mock.events.listen((event) {
///   print('Geofence ${event.identifier}: ${event.action}');
/// });
/// ```
class MockGeofenceService implements GeofenceService {
  final List<Geofence> _geofences = [];
  final List<PolygonGeofence> _polygonGeofences = [];
  final List<GeofenceWorkflow> _workflows = [];
  final Map<String, GeofenceWorkflowState> _workflowStates = {};

  final _eventsController = StreamController<GeofenceEvent>.broadcast();
  final _polygonEventsController =
      StreamController<PolygonGeofenceEvent>.broadcast();
  final _workflowEventsController =
      StreamController<GeofenceWorkflowEvent>.broadcast();

  bool _monitoring = false;

  @override
  Stream<GeofenceEvent> get events => _eventsController.stream;

  @override
  Stream<PolygonGeofenceEvent> get polygonEvents =>
      _polygonEventsController.stream;

  @override
  Stream<GeofenceWorkflowEvent> get workflowEvents =>
      _workflowEventsController.stream;

  // ============================================================
  // Circular Geofences
  // ============================================================

  @override
  Future<bool> add(Geofence geofence) async {
    _geofences.removeWhere((g) => g.identifier == geofence.identifier);
    _geofences.add(geofence);
    return true;
  }

  @override
  Future<bool> addAll(List<Geofence> geofences) async {
    for (final geofence in geofences) {
      await add(geofence);
    }
    return true;
  }

  @override
  Future<bool> remove(String identifier) async {
    final initialLength = _geofences.length;
    _geofences.removeWhere((g) => g.identifier == identifier);
    return _geofences.length < initialLength;
  }

  @override
  Future<bool> removeAll() async {
    _geofences.clear();
    return true;
  }

  @override
  Future<List<Geofence>> getAll() async {
    return List.unmodifiable(_geofences);
  }

  @override
  Future<Geofence?> get(String identifier) async {
    try {
      return _geofences.firstWhere((g) => g.identifier == identifier);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(String identifier) async {
    return _geofences.any((g) => g.identifier == identifier);
  }

  @override
  Future<bool> startMonitoring() async {
    _monitoring = true;
    return true;
  }

  /// Whether geofence monitoring is active.
  bool get isMonitoring => _monitoring;

  // ============================================================
  // Polygon Geofences
  // ============================================================

  @override
  Future<bool> addPolygon(PolygonGeofence polygon) async {
    _polygonGeofences.removeWhere((p) => p.identifier == polygon.identifier);
    _polygonGeofences.add(polygon);
    return true;
  }

  @override
  Future<int> addPolygons(List<PolygonGeofence> polygons) async {
    var count = 0;
    for (final polygon in polygons) {
      if (await addPolygon(polygon)) count++;
    }
    return count;
  }

  @override
  Future<bool> removePolygon(String identifier) async {
    final initialLength = _polygonGeofences.length;
    _polygonGeofences.removeWhere((p) => p.identifier == identifier);
    return _polygonGeofences.length < initialLength;
  }

  @override
  Future<void> removeAllPolygons() async {
    _polygonGeofences.clear();
  }

  @override
  Future<List<PolygonGeofence>> getAllPolygons() async {
    return List.unmodifiable(_polygonGeofences);
  }

  @override
  Future<PolygonGeofence?> getPolygon(String identifier) async {
    try {
      return _polygonGeofences.firstWhere((p) => p.identifier == identifier);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> polygonExists(String identifier) async {
    return _polygonGeofences.any((p) => p.identifier == identifier);
  }

  // ============================================================
  // Workflows
  // ============================================================

  @override
  void registerWorkflows(List<GeofenceWorkflow> workflows) {
    for (final workflow in workflows) {
      _workflows.removeWhere((w) => w.id == workflow.id);
      _workflows.add(workflow);
      _workflowStates[workflow.id] = GeofenceWorkflowState(
        workflowId: workflow.id,
        currentIndex: 0,
        completedStepIds: [],
        completed: false,
      );
    }
  }

  @override
  GeofenceWorkflowState? getWorkflowState(String workflowId) {
    return _workflowStates[workflowId];
  }

  @override
  void clearWorkflows() {
    _workflows.clear();
    _workflowStates.clear();
  }

  @override
  void stopWorkflows() {
    // In a real implementation, this would stop active workflow processing
    // For the mock, we just clear the states
    _workflowStates.clear();
  }

  // ============================================================
  // Subscriptions
  // ============================================================

  @override
  StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback, {
    Function? onError,
  }) {
    return _eventsController.stream.listen(
      callback,
      onError: onError,
    );
  }

  @override
  StreamSubscription<dynamic> onGeofencesChange(
    void Function(dynamic) callback, {
    Function? onError,
  }) {
    // Mock implementation - in real implementation would listen to geofence changes
    return const Stream.empty().listen(
      callback,
      onError: onError,
    );
  }

  @override
  StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent) callback, {
    Function? onError,
  }) {
    return _workflowEventsController.stream.listen(
      callback,
      onError: onError,
    );
  }

  @override
  Future<bool> isInActiveGeofence() async {
    // Mock implementation - returns false
    return false;
  }

  // ============================================================
  // Test Helpers
  // ============================================================

  /// Adds a workflow (test helper).
  Future<void> addWorkflow(GeofenceWorkflow workflow) async {
    _workflows.removeWhere((w) => w.id == workflow.id);
    _workflows.add(workflow);
    _workflowStates[workflow.id] = GeofenceWorkflowState(
      workflowId: workflow.id,
      currentIndex: 0,
      completedStepIds: [],
      completed: false,
    );
  }

  /// Gets all workflows (test helper).
  Future<List<GeofenceWorkflow>> getWorkflows() async {
    return List.unmodifiable(_workflows);
  }

  /// Gets a specific workflow (test helper).
  Future<GeofenceWorkflow?> getWorkflow(String identifier) async {
    try {
      return _workflows.firstWhere((w) => w.id == identifier);
    } catch (_) {
      return null;
    }
  }

  /// Resets a workflow (test helper).
  Future<void> resetWorkflow(String identifier) async {
    final workflow = await getWorkflow(identifier);
    if (workflow != null) {
      _workflowStates[identifier] = GeofenceWorkflowState(
        workflowId: identifier,
        currentIndex: 0,
        completedStepIds: [],
        completed: false,
      );
    }
  }

  // ============================================================
  // Test Event Triggers
  // ============================================================

  /// Triggers a geofence entry event.
  void triggerEntry(String identifier, {Location? location}) {
    final geofence = _geofences.cast<Geofence?>().firstWhere(
          (g) => g?.identifier == identifier,
          orElse: () => null,
        );

    if (geofence != null && geofence.notifyOnEntry) {
      _eventsController.add(GeofenceEvent(
        geofence: geofence,
        action: GeofenceAction.enter,
        location: location ?? _createDefaultLocation(geofence),
      ));
    }
  }

  /// Triggers a geofence exit event.
  void triggerExit(String identifier, {Location? location}) {
    final geofence = _geofences.cast<Geofence?>().firstWhere(
          (g) => g?.identifier == identifier,
          orElse: () => null,
        );

    if (geofence != null && geofence.notifyOnExit) {
      _eventsController.add(GeofenceEvent(
        geofence: geofence,
        action: GeofenceAction.exit,
        location: location ?? _createDefaultLocation(geofence),
      ));
    }
  }

  /// Triggers a geofence dwell event.
  void triggerDwell(String identifier, {Location? location}) {
    final geofence = _geofences.cast<Geofence?>().firstWhere(
          (g) => g?.identifier == identifier,
          orElse: () => null,
        );

    if (geofence != null && geofence.notifyOnDwell) {
      _eventsController.add(GeofenceEvent(
        geofence: geofence,
        action: GeofenceAction.dwell,
        location: location ?? _createDefaultLocation(geofence),
      ));
    }
  }

  /// Triggers a polygon geofence event.
  void triggerPolygonEvent(
    String identifier,
    GeofenceAction action, {
    Location? location,
  }) {
    final polygon = _polygonGeofences.cast<PolygonGeofence?>().firstWhere(
          (p) => p?.identifier == identifier,
          orElse: () => null,
        );

    if (polygon != null) {
      // Convert GeofenceAction to PolygonGeofenceEventType
      final eventType = action == GeofenceAction.enter
          ? PolygonGeofenceEventType.enter
          : action == GeofenceAction.exit
              ? PolygonGeofenceEventType.exit
              : PolygonGeofenceEventType.dwell;

      final loc = location ?? _createDefaultLocationForPolygon(polygon);
      _polygonEventsController.add(PolygonGeofenceEvent(
        geofence: polygon,
        type: eventType,
        timestamp: DateTime.now(),
        triggerLocation: GeoPoint(
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
        ),
      ));
    }
  }

  /// Checks if a location is within a geofence.
  bool isLocationInGeofence(String identifier, Location location) {
    final geofence = _geofences.cast<Geofence?>().firstWhere(
          (g) => g?.identifier == identifier,
          orElse: () => null,
        );

    if (geofence == null) return false;

    final distance = _calculateDistance(
      geofence.latitude,
      geofence.longitude,
      location.coords.latitude,
      location.coords.longitude,
    );

    return distance <= geofence.radius;
  }

  Location _createDefaultLocation(Geofence geofence) {
    return Location(
      uuid: 'mock-${geofence.identifier}',
      timestamp: DateTime.now(),
      coords: Coords(
        latitude: geofence.latitude,
        longitude: geofence.longitude,
        accuracy: 10,
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      isMoving: false,
    );
  }

  Location _createDefaultLocationForPolygon(PolygonGeofence polygon) {
    // Use the first vertex as the default location
    final firstVertex = polygon.vertices.first;
    return Location(
      uuid: 'mock-${polygon.identifier}',
      timestamp: DateTime.now(),
      coords: Coords(
        latitude: firstVertex.latitude,
        longitude: firstVertex.longitude,
        accuracy: 10,
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      isMoving: false,
    );
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Disposes of resources.
  Future<void> dispose() async {
    await _eventsController.close();
    await _polygonEventsController.close();
    await _workflowEventsController.close();
  }
}
