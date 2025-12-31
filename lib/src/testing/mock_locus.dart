/// Mock implementation of Locus for testing.
///
/// Provides a complete mock of the Locus SDK that can be used in
/// unit tests without requiring platform channels or real location services.
///
/// Example:
/// ```dart
/// void main() {
///   setUp(() {
///     Locus.setMockInstance(MockLocus());
///   });
///
///   test('my location test', () async {
///     final mock = Locus.mockInstance as MockLocus;
///     mock.emitLocation(Location.mock(latitude: 37.4219, longitude: -122.084));
///
///     // Your test code here
///   });
/// }
/// ```
library;

import 'dart:async';

import 'package:locus/src/config/geolocation_config.dart';
import 'package:locus/src/models/models.dart';

/// Abstract interface for Locus functionality.
///
/// This interface allows swapping real implementation with mocks for testing.
abstract class LocusInterface {
  /// Initializes the SDK with the given configuration.
  Future<GeolocationState> ready(Config config);

  /// Starts location tracking.
  Future<GeolocationState> start();

  /// Stops location tracking.
  Future<GeolocationState> stop();

  /// Gets the current state.
  Future<GeolocationState> getState();

  /// Gets the current position.
  Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    Map<String, dynamic>? extras,
  });

  /// Changes the motion state.
  Future<void> changePace(bool isMoving);

  /// Sets the odometer value.
  Future<double> setOdometer(double value);

  /// Adds a geofence.
  Future<void> addGeofence(Geofence geofence);

  /// Removes a geofence.
  Future<void> removeGeofence(String identifier);

  /// Gets all geofences.
  Future<List<Geofence>> getGeofences();

  /// Checks if a geofence exists.
  Future<bool> geofenceExists(String identifier);

  /// Gets stored locations.
  Future<List<Location>> getLocations({int? limit});

  /// Destroys all stored locations.
  Future<void> destroyLocations();

  /// Stream of location updates.
  Stream<Location> get locationStream;

  /// Stream of motion change events.
  Stream<Location> get motionChangeStream;

  /// Stream of activity changes.
  Stream<Activity> get activityChangeStream;

  /// Stream of provider changes.
  Stream<ProviderChangeEvent> get providerChangeStream;

  /// Stream of geofence events.
  Stream<GeofenceEvent> get geofenceStream;

  /// Stream of connectivity changes.
  Stream<ConnectivityChangeEvent> get connectivityChangeStream;

  /// Stream of HTTP events.
  Stream<HttpEvent> get httpStream;
}

/// Mock implementation of Locus for unit testing.
///
/// This class provides a complete simulation of the Locus SDK without
/// requiring platform channels or real location services.
///
/// Example:
/// ```dart
/// final mock = MockLocus();
///
/// // Configure initial state
/// mock.setMockState(GeolocationState(
///   enabled: true,
///   isMoving: false,
///   odometer: 0,
/// ));
///
/// // Emit mock locations
/// mock.emitLocation(Location.mock(
///   latitude: 37.4219,
///   longitude: -122.084,
/// ));
/// ```
class MockLocus implements LocusInterface {
  /// Creates a new MockLocus instance.
  MockLocus({
    GeolocationState? initialState,
    Config? initialConfig,
  })  : _state = initialState ?? const GeolocationState(enabled: false),
        _config = initialConfig ?? const Config();

  GeolocationState _state;
  Config _config;
  final List<Geofence> _geofences = [];
  final List<Location> _storedLocations = [];
  final List<QueueItem> _queue = [];

  bool _isReady = false;

  // Stream controllers
  final _locationController = StreamController<Location>.broadcast();
  final _motionChangeController = StreamController<Location>.broadcast();
  final _activityChangeController = StreamController<Activity>.broadcast();
  final _providerChangeController =
      StreamController<ProviderChangeEvent>.broadcast();
  final _geofenceController = StreamController<GeofenceEvent>.broadcast();
  final _connectivityController =
      StreamController<ConnectivityChangeEvent>.broadcast();
  final _httpController = StreamController<HttpEvent>.broadcast();
  final _heartbeatController = StreamController<Location>.broadcast();
  final _enabledChangeController = StreamController<bool>.broadcast();
  final _tripEventController = StreamController<TripEvent>.broadcast();

  // Call tracking for verification
  final List<String> _methodCalls = [];

  /// List of method calls made to this mock.
  ///
  /// Useful for verifying that certain methods were called during tests.
  List<String> get methodCalls => List.unmodifiable(_methodCalls);

  /// Clears the method call history.
  void clearMethodCalls() => _methodCalls.clear();

  /// Whether [ready] has been called.
  bool get isReady => _isReady;

  /// The current mock configuration.
  Config get config => _config;

  /// Sets the mock state.
  void setMockState(GeolocationState state) {
    _state = state;
  }

  /// Emits a mock location to all location listeners.
  void emitLocation(Location location) {
    _storedLocations.add(location);
    _locationController.add(location);
  }

  /// Emits a mock motion change event.
  void emitMotionChange(Location location) {
    _motionChangeController.add(location);
  }

  /// Emits a mock activity change.
  void emitActivityChange(Activity activity) {
    _activityChangeController.add(activity);
  }

  /// Emits a mock provider change.
  void emitProviderChange(ProviderChangeEvent event) {
    _providerChangeController.add(event);
  }

  /// Emits a mock geofence event.
  void emitGeofenceEvent(GeofenceEvent event) {
    _geofenceController.add(event);
  }

  /// Emits a mock connectivity change.
  void emitConnectivityChange(ConnectivityChangeEvent event) {
    _connectivityController.add(event);
  }

  /// Emits a mock HTTP event.
  void emitHttpEvent(HttpEvent event) {
    _httpController.add(event);
  }

  /// Emits a mock heartbeat.
  void emitHeartbeat(Location location) {
    _heartbeatController.add(location);
  }

  /// Emits an enabled change event.
  void emitEnabledChange(bool enabled) {
    _enabledChangeController.add(enabled);
  }

  /// Emits a trip event.
  void emitTripEvent(TripEvent event) {
    _tripEventController.add(event);
  }

  /// Simulates a sequence of locations over time.
  ///
  /// Useful for testing route tracking, trip detection, etc.
  Future<void> simulateLocationSequence(
    List<Location> locations, {
    Duration interval = const Duration(seconds: 1),
  }) async {
    for (final location in locations) {
      emitLocation(location);
      await Future.delayed(interval);
    }
  }

  @override
  Future<GeolocationState> ready(Config config) async {
    _methodCalls.add('ready');
    _config = config;
    _isReady = true;
    return _state;
  }

  @override
  Future<GeolocationState> start() async {
    _methodCalls.add('start');
    _state = _state.copyWith(enabled: true);
    _enabledChangeController.add(true);
    return _state;
  }

  @override
  Future<GeolocationState> stop() async {
    _methodCalls.add('stop');
    _state = _state.copyWith(enabled: false);
    _enabledChangeController.add(false);
    return _state;
  }

  @override
  Future<GeolocationState> getState() async {
    _methodCalls.add('getState');
    return _state;
  }

  @override
  Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    Map<String, dynamic>? extras,
  }) async {
    _methodCalls.add('getCurrentPosition');
    if (_storedLocations.isNotEmpty) {
      return _storedLocations.last;
    }
    // Return a default mock location
    return Location(
      uuid: 'mock-uuid',
      timestamp: DateTime.now(),
      coords: const Coords(
        latitude: 0,
        longitude: 0,
        accuracy: 10,
        speed: 0,
        heading: 0,
        altitude: 0,
      ),
      activity: const Activity(type: ActivityType.still, confidence: 100),
      isMoving: false,
      odometer: _state.odometer ?? 0,
    );
  }

  @override
  Future<void> changePace(bool isMoving) async {
    _methodCalls.add('changePace:$isMoving');
    _state = _state.copyWith(isMoving: isMoving);
  }

  @override
  Future<double> setOdometer(double value) async {
    _methodCalls.add('setOdometer:$value');
    _state = _state.copyWith(odometer: value);
    return value;
  }

  @override
  Future<void> addGeofence(Geofence geofence) async {
    _methodCalls.add('addGeofence:${geofence.identifier}');
    _geofences.removeWhere((g) => g.identifier == geofence.identifier);
    _geofences.add(geofence);
  }

  @override
  Future<void> removeGeofence(String identifier) async {
    _methodCalls.add('removeGeofence:$identifier');
    _geofences.removeWhere((g) => g.identifier == identifier);
  }

  @override
  Future<List<Geofence>> getGeofences() async {
    _methodCalls.add('getGeofences');
    return List.unmodifiable(_geofences);
  }

  @override
  Future<bool> geofenceExists(String identifier) async {
    _methodCalls.add('geofenceExists:$identifier');
    return _geofences.any((g) => g.identifier == identifier);
  }

  @override
  Future<List<Location>> getLocations({int? limit}) async {
    _methodCalls.add('getLocations');
    if (limit != null && limit < _storedLocations.length) {
      return _storedLocations.sublist(_storedLocations.length - limit);
    }
    return List.unmodifiable(_storedLocations);
  }

  @override
  Future<void> destroyLocations() async {
    _methodCalls.add('destroyLocations');
    _storedLocations.clear();
  }

  /// Adds multiple geofences.
  Future<void> addGeofences(List<Geofence> geofences) async {
    _methodCalls.add('addGeofences');
    for (final geofence in geofences) {
      await addGeofence(geofence);
    }
  }

  /// Removes all geofences.
  Future<void> removeGeofences() async {
    _methodCalls.add('removeGeofences');
    _geofences.clear();
  }

  /// Enqueues a custom payload.
  Future<String> enqueue(Map<String, dynamic> payload) async {
    _methodCalls.add('enqueue');
    final id = 'mock-queue-${_queue.length}';
    _queue.add(QueueItem(
      id: id,
      payload: payload,
      createdAt: DateTime.now(),
      retryCount: 0,
    ));
    return id;
  }

  /// Gets the queue.
  Future<List<QueueItem>> getQueue({int? limit}) async {
    _methodCalls.add('getQueue');
    return List.unmodifiable(_queue);
  }

  /// Clears the queue.
  Future<void> clearQueue() async {
    _methodCalls.add('clearQueue');
    _queue.clear();
  }

  @override
  Stream<Location> get locationStream => _locationController.stream;

  @override
  Stream<Location> get motionChangeStream => _motionChangeController.stream;

  @override
  Stream<Activity> get activityChangeStream => _activityChangeController.stream;

  @override
  Stream<ProviderChangeEvent> get providerChangeStream =>
      _providerChangeController.stream;

  @override
  Stream<GeofenceEvent> get geofenceStream => _geofenceController.stream;

  @override
  Stream<ConnectivityChangeEvent> get connectivityChangeStream =>
      _connectivityController.stream;

  @override
  Stream<HttpEvent> get httpStream => _httpController.stream;

  /// Stream of heartbeat events.
  Stream<Location> get heartbeatStream => _heartbeatController.stream;

  /// Stream of enabled change events.
  Stream<bool> get enabledChangeStream => _enabledChangeController.stream;

  /// Stream of trip events.
  Stream<TripEvent> get tripEventStream => _tripEventController.stream;

  /// Disposes all stream controllers.
  void dispose() {
    _locationController.close();
    _motionChangeController.close();
    _activityChangeController.close();
    _providerChangeController.close();
    _geofenceController.close();
    _connectivityController.close();
    _httpController.close();
    _heartbeatController.close();
    _enabledChangeController.close();
    _tripEventController.close();
  }
}

/// Extension to create mock Location objects easily.
extension MockLocationExtension on Location {
  /// Creates a mock location with sensible defaults.
  ///
  /// Example:
  /// ```dart
  /// final location = Location.mock(
  ///   latitude: 37.4219,
  ///   longitude: -122.084,
  /// );
  /// ```
  static Location mock({
    double latitude = 0,
    double longitude = 0,
    double accuracy = 10,
    double speed = 0,
    double heading = 0,
    double altitude = 0,
    ActivityType activityType = ActivityType.still,
    int activityConfidence = 100,
    bool isMoving = false,
    double odometer = 0,
    String? uuid,
    DateTime? timestamp,
    String? event,
  }) {
    return Location(
      uuid: uuid ?? 'mock-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      coords: Coords(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        speed: speed,
        heading: heading,
        altitude: altitude,
      ),
      activity: Activity(type: activityType, confidence: activityConfidence),
      isMoving: isMoving,
      odometer: odometer,
      event: event,
    );
  }
}

/// Extension to create mock Activity objects easily.
extension MockActivityExtension on Activity {
  /// Creates a mock activity.
  static Activity mock({
    ActivityType type = ActivityType.still,
    int confidence = 100,
  }) {
    return Activity(type: type, confidence: confidence);
  }
}

/// Extension to create mock Geofence objects easily.
extension MockGeofenceExtension on Geofence {
  /// Creates a mock geofence.
  static Geofence mock({
    String? identifier,
    double latitude = 0,
    double longitude = 0,
    double radius = 100,
    bool notifyOnEntry = true,
    bool notifyOnExit = true,
    bool notifyOnDwell = false,
    int loiteringDelay = 0,
    Map<String, dynamic>? extras,
  }) {
    return Geofence(
      identifier: identifier ??
          'mock-geofence-${DateTime.now().millisecondsSinceEpoch}',
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      notifyOnEntry: notifyOnEntry,
      notifyOnExit: notifyOnExit,
      notifyOnDwell: notifyOnDwell,
      loiteringDelay: loiteringDelay,
      extras: extras,
    );
  }
}
