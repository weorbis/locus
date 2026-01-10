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

import 'package:locus/src/config/config.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';

// Testing module exports the full LocusInterface for mock implementations.
// The main library only exports: SyncBodyBuilder, SyncBodyContext, HeadlessEventCallback
// Tests need the full interface to create custom mock implementations.
export 'package:locus/src/core/locus_interface.dart';

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
  MockLocus({GeolocationState? initialState, Config? initialConfig})
      : _state = initialState ?? const GeolocationState(enabled: false),
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
  final _powerSaveController = StreamController<bool>.broadcast();
  final _powerStateController =
      StreamController<PowerStateChangeEvent>.broadcast();
  final _tripEventController = StreamController<TripEvent>.broadcast();
  final _workflowController =
      StreamController<GeofenceWorkflowEvent>.broadcast();
  final _eventsController =
      StreamController<GeolocationEvent<dynamic>>.broadcast();
  final _errorController = StreamController<LocusError>.broadcast();

  // Call tracking for verification
  final List<String> _methodCalls = [];

  AdaptiveTrackingConfig? _adaptiveTrackingConfig;
  SpoofDetectionConfig? _spoofDetectionConfig;
  ErrorRecoveryConfig? _errorRecoveryConfig;
  TrackingProfile? _currentTrackingProfile;
  final Map<TrackingProfile, Config> _trackingProfiles = {};
  bool _trackingAutomationEnabled = false;
  bool _significantChangeMonitoring = false;
  bool _isForeground = true;
  PowerState _powerState = PowerState.unknown;
  BatteryStats _batteryStats = const BatteryStats.empty();
  BatteryBenchmark? _activeBenchmark;
  final List<LogEntry> _logEntries = [];
  final List<GeofenceWorkflow> _workflows = [];
  final Map<String, GeofenceWorkflowState> _workflowStates = {};
  Future<Map<String, String>> Function()? _headersCallback;
  SyncPolicy? _syncPolicy;
  int _backgroundTaskId = 0;
  TripState? _tripState;
  TripSummary? _tripSummary;
  ErrorRecoveryManager? _errorRecoveryManager;

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

  void _emitEvent(EventType type, dynamic data) {
    _eventsController.add(GeolocationEvent(type: type, data: data));
  }

  /// Emits a mock location to all location listeners.
  void emitLocation(Location location) {
    _storedLocations.add(location);
    _locationController.add(location);
    _emitEvent(EventType.location, location);
  }

  /// Emits a mock motion change event.
  void emitMotionChange(Location location) {
    _motionChangeController.add(location);
    _emitEvent(EventType.motionChange, location);
  }

  /// Emits a mock activity change.
  void emitActivityChange(Activity activity) {
    _activityChangeController.add(activity);
    _emitEvent(EventType.activityChange, activity);
  }

  /// Emits a mock provider change.
  void emitProviderChange(ProviderChangeEvent event) {
    _providerChangeController.add(event);
    _emitEvent(EventType.providerChange, event);
  }

  /// Emits a mock geofence event.
  void emitGeofenceEvent(GeofenceEvent event) {
    _geofenceController.add(event);
    _emitEvent(EventType.geofence, event);
  }

  /// Emits a mock connectivity change.
  void emitConnectivityChange(ConnectivityChangeEvent event) {
    _connectivityController.add(event);
    _emitEvent(EventType.connectivityChange, event);
  }

  /// Emits a mock HTTP event.
  void emitHttpEvent(HttpEvent event) {
    _httpController.add(event);
    _emitEvent(EventType.http, event);
  }

  /// Emits a mock heartbeat.
  void emitHeartbeat(Location location) {
    _heartbeatController.add(location);
    _emitEvent(EventType.heartbeat, location);
  }

  /// Emits an enabled change event.
  void emitEnabledChange(bool enabled) {
    _enabledChangeController.add(enabled);
    _emitEvent(EventType.enabledChange, enabled);
  }

  /// Emits a trip event.
  void emitTripEvent(TripEvent event) {
    _tripEventController.add(event);
  }

  /// Emits a power save mode change event.
  void emitPowerSaveChange(bool isPowerSaveMode) {
    _powerSaveController.add(isPowerSaveMode);
    _emitEvent(EventType.powerSaveChange, isPowerSaveMode);
  }

  /// Emits a power state change event.
  void emitPowerStateChange(PowerStateChangeEvent event) {
    _powerState = event.current;
    _powerStateController.add(event);
    // Note: No generic event type for power state changes
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
  Future<GeolocationState> ready(
    Config config, {
    bool skipValidation = false,
  }) async {
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
  Future<bool> changePace(bool isMoving) async {
    _methodCalls.add('changePace');
    _methodCalls.add('changePace:$isMoving');
    _state = _state.copyWith(isMoving: isMoving);
    return true;
  }

  @override
  Future<double> setOdometer(double value) async {
    _methodCalls.add('setOdometer');
    _methodCalls.add('setOdometer:$value');
    _state = _state.copyWith(odometer: value);
    return value;
  }

  @override
  Future<bool> addGeofence(Geofence geofence) async {
    _methodCalls.add('addGeofence');
    _methodCalls.add('addGeofence:${geofence.identifier}');
    _geofences.removeWhere((g) => g.identifier == geofence.identifier);
    _geofences.add(geofence);
    return true;
  }

  @override
  Future<bool> removeGeofence(String identifier) async {
    _methodCalls.add('removeGeofence');
    _methodCalls.add('removeGeofence:$identifier');
    final before = _geofences.length;
    _geofences.removeWhere((g) => g.identifier == identifier);
    return _geofences.length != before;
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
  Future<List<Location>> queryLocations(LocationQuery query) async {
    _methodCalls.add('getLocations');
    _methodCalls.add('queryLocations');
    return query.apply(_storedLocations);
  }

  @override
  Future<LocationSummary> getLocationSummary({
    DateTime? date,
    LocationQuery? query,
  }) async {
    _methodCalls.add('getLocationSummary');
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

    final locations = await queryLocations(effectiveQuery);
    return LocationHistoryCalculator.calculateSummary(locations);
  }

  @override
  Future<bool> destroyLocations() async {
    _methodCalls.add('destroyLocations');
    _storedLocations.clear();
    return true;
  }

  /// Adds multiple geofences.
  @override
  Future<bool> addGeofences(List<Geofence> geofences) async {
    _methodCalls.add('addGeofences');
    for (final geofence in geofences) {
      await addGeofence(geofence);
    }
    return true;
  }

  /// Removes all geofences.
  @override
  Future<bool> removeGeofences() async {
    _methodCalls.add('removeGeofences');
    _geofences.clear();
    return true;
  }

  /// Enqueues a custom payload.
  @override
  Future<String> enqueue(
    Map<String, dynamic> payload, {
    String? type,
    String? idempotencyKey,
  }) async {
    _methodCalls.add('enqueue');
    final id = 'mock-queue-${_queue.length}';
    _queue.add(
      QueueItem(
        id: id,
        payload: payload,
        createdAt: DateTime.now(),
        retryCount: 0,
      ),
    );
    return id;
  }

  /// Gets the queue.
  @override
  Future<List<QueueItem>> getQueue({int? limit}) async {
    _methodCalls.add('getQueue');
    if (limit != null && limit < _queue.length) {
      return List.unmodifiable(_queue.sublist(_queue.length - limit));
    }
    return List.unmodifiable(_queue);
  }

  /// Clears the queue.
  @override
  Future<void> clearQueue() async {
    _methodCalls.add('clearQueue');
    _queue.clear();
  }

  @override
  Future<Geofence?> getGeofence(String identifier) async {
    _methodCalls.add('getGeofence:$identifier');
    for (final geofence in _geofences) {
      if (geofence.identifier == identifier) {
        return geofence;
      }
    }
    return null;
  }

  @override
  Future<bool> startGeofences() async {
    _methodCalls.add('startGeofences');
    return true;
  }

  // ============================================================
  // Polygon Geofencing Methods
  // ============================================================
  final PolygonGeofenceService _polygonGeofenceService =
      PolygonGeofenceService();

  @override
  Future<bool> addPolygonGeofence(PolygonGeofence polygon) async {
    _methodCalls.add('addPolygonGeofence');
    _methodCalls.add('addPolygonGeofence:${polygon.identifier}');
    return _polygonGeofenceService.addPolygonGeofence(polygon);
  }

  @override
  Future<int> addPolygonGeofences(List<PolygonGeofence> polygons) async {
    _methodCalls.add('addPolygonGeofences');
    _methodCalls.add('addPolygonGeofences:${polygons.length}');
    return _polygonGeofenceService.addPolygonGeofences(polygons);
  }

  @override
  Future<bool> removePolygonGeofence(String identifier) async {
    _methodCalls.add('removePolygonGeofence:$identifier');
    return _polygonGeofenceService.removePolygonGeofence(identifier);
  }

  @override
  Future<void> removeAllPolygonGeofences() async {
    _methodCalls.add('removeAllPolygonGeofences');
    await _polygonGeofenceService.removeAllPolygonGeofences();
  }

  @override
  Future<List<PolygonGeofence>> getPolygonGeofences() async {
    _methodCalls.add('getPolygonGeofences');
    return _polygonGeofenceService.polygons;
  }

  @override
  Future<PolygonGeofence?> getPolygonGeofence(String identifier) async {
    _methodCalls.add('getPolygonGeofence:$identifier');
    return _polygonGeofenceService.getPolygonGeofence(identifier);
  }

  @override
  Future<bool> polygonGeofenceExists(String identifier) async {
    _methodCalls.add('polygonGeofenceExists:$identifier');
    return _polygonGeofenceService.polygonExists(identifier);
  }

  @override
  Stream<PolygonGeofenceEvent> get polygonGeofenceEvents =>
      _polygonGeofenceService.events;

  /// Emits a mock polygon geofence event.
  void emitPolygonGeofenceEvent(PolygonGeofenceEvent event) {
    _polygonGeofenceService.processLocationUpdate(
      event.triggerLocation?.latitude ?? 0,
      event.triggerLocation?.longitude ?? 0,
    );
  }

  // ============================================================
  // Privacy Zone Methods
  // ============================================================
  final PrivacyZoneService _privacyZoneService = PrivacyZoneService();

  @override
  Future<void> addPrivacyZone(PrivacyZone zone) async {
    _methodCalls.add('addPrivacyZone:${zone.identifier}');
    _methodCalls.add('addPrivacyZone');
    await _privacyZoneService.addZone(zone);
  }

  @override
  Future<void> addPrivacyZones(List<PrivacyZone> zones) async {
    _methodCalls.add('addPrivacyZones:${zones.length}');
    _methodCalls.add('addPrivacyZones');
    await _privacyZoneService.addZones(zones);
  }

  @override
  Future<bool> removePrivacyZone(String identifier) async {
    _methodCalls.add('removePrivacyZone:$identifier');
    return _privacyZoneService.removeZone(identifier);
  }

  @override
  Future<void> removeAllPrivacyZones() async {
    _methodCalls.add('removeAllPrivacyZones');
    await _privacyZoneService.removeAllZones();
  }

  @override
  Future<PrivacyZone?> getPrivacyZone(String identifier) async {
    _methodCalls.add('getPrivacyZone:$identifier');
    return _privacyZoneService.getZone(identifier);
  }

  @override
  Future<List<PrivacyZone>> getPrivacyZones() async {
    _methodCalls.add('getPrivacyZones');
    return _privacyZoneService.zones;
  }

  @override
  Future<bool> setPrivacyZoneEnabled(String identifier, bool enabled) async {
    _methodCalls.add('setPrivacyZoneEnabled:$identifier:$enabled');
    return _privacyZoneService.setZoneEnabled(identifier, enabled);
  }

  @override
  Stream<PrivacyZoneEvent> get privacyZoneEvents =>
      _privacyZoneService.zoneChanges;

  /// Helper to process a location through privacy zones.
  PrivacyZoneResult processLocationThroughPrivacyZones(Location location) {
    return _privacyZoneService.processLocation(location);
  }

  @override
  Future<void> setConfig(Config config) async {
    _methodCalls.add('setConfig');
    _config = config;
  }

  @override
  Future<void> destroy() async {
    _methodCalls.add('destroy');
    _isReady = false;
    _state = const GeolocationState(enabled: false);
    _storedLocations.clear();
    _queue.clear();
    _geofences.clear();
  }

  @override
  Future<void> reset(Config config) async {
    _methodCalls.add('reset');
    await destroy();
    _config = config;
    _isReady = true;
  }

  @override
  Future<bool> startSchedule() async {
    _methodCalls.add('startSchedule');
    return true;
  }

  @override
  Future<bool> stopSchedule() async {
    _methodCalls.add('stopSchedule');
    return true;
  }

  @override
  Future<bool> sync() async {
    _methodCalls.add('sync');
    return true;
  }

  @override
  Future<bool> resume() async {
    _methodCalls.add('resumeSync');
    return true;
  }

  // ============================================================
  // Sync Pause/Validation (Mock)
  // ============================================================
  bool _isSyncPaused = false;
  PreSyncValidator? _preSyncValidator;

  @override
  bool get isSyncPaused => _isSyncPaused;

  @override
  Future<void> pauseSync() async {
    _methodCalls.add('pauseSync');
    _isSyncPaused = true;
  }

  @override
  void setPreSyncValidator(PreSyncValidator? validator) {
    _methodCalls.add('setPreSyncValidator');
    _preSyncValidator = validator;
  }

  @override
  void clearPreSyncValidator() {
    _methodCalls.add('clearPreSyncValidator');
    _preSyncValidator = null;
  }

  /// The current pre-sync validator (for test verification).
  PreSyncValidator? get preSyncValidator => _preSyncValidator;

  // ============================================================
  // Sync Body Builder (Mock)
  // ============================================================
  SyncBodyBuilder? _syncBodyBuilder;

  @override
  Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder) async {
    _methodCalls.add('setSyncBodyBuilder');
    _syncBodyBuilder = builder;
  }

  @override
  void clearSyncBodyBuilder() {
    _methodCalls.add('clearSyncBodyBuilder');
    _syncBodyBuilder = null;
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) async {
    _methodCalls.add('registerHeadlessSyncBodyBuilder');
    return true;
  }

  /// The current sync body builder (for test verification).
  SyncBodyBuilder? get syncBodyBuilder => _syncBodyBuilder;

  /// Invokes the sync body builder if set (for testing).
  Future<JsonMap?> invokeSyncBodyBuilder(
    List<Location> locations,
    JsonMap extras,
  ) async {
    if (_syncBodyBuilder == null) return null;
    return _syncBodyBuilder!(locations, extras);
  }

  @override
  Future<bool> registerHeadlessTask(HeadlessEventCallback callback) async {
    _methodCalls.add('registerHeadlessTask');
    return true;
  }

  @override
  Future<int> startBackgroundTask() async {
    _methodCalls.add('startBackgroundTask');
    _backgroundTaskId += 1;
    return _backgroundTaskId;
  }

  @override
  Future<void> stopBackgroundTask(int taskId) async {
    _methodCalls.add('stopBackgroundTask:$taskId');
  }

  @override
  Future<List<LogEntry>> getLog() async {
    _methodCalls.add('getLog');
    return List.unmodifiable(_logEntries);
  }

  @override
  Future<int> syncQueue({int? limit}) async {
    _methodCalls.add('syncQueue');
    return _queue.length;
  }

  @override
  Future<bool> requestPermission() async {
    _methodCalls.add('requestPermission');
    return true;
  }

  @override
  void setHeadersCallback(Future<Map<String, String>> Function()? callback) {
    _methodCalls.add('setHeadersCallback');
    _headersCallback = callback;
  }

  @override
  void clearHeadersCallback() {
    _methodCalls.add('clearHeadersCallback');
    _headersCallback = null;
  }

  @override
  Future<void> refreshHeaders() async {
    _methodCalls.add('refreshHeaders');
    if (_headersCallback == null) return;
    await _headersCallback!();
  }

  @override
  StreamSubscription<Location> onLocation(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return locationStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<Location> onMotionChange(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return motionChangeStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<Activity> onActivityChange(
    void Function(Activity) callback, {
    Function? onError,
  }) {
    return activityStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback, {
    Function? onError,
  }) {
    return providerStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback, {
    Function? onError,
  }) {
    return geofenceStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<dynamic> onGeofencesChange(
    void Function(dynamic) callback, {
    Function? onError,
  }) {
    return events
        .where((event) => event.type == EventType.geofencesChange)
        .map((event) => event.data)
        .listen(callback, onError: onError);
  }

  @override
  StreamSubscription<Location> onHeartbeat(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return heartbeatStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<Location> onSchedule(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return events
        .where((event) => event.type == EventType.schedule)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>()
        .listen(callback, onError: onError);
  }

  @override
  StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  }) {
    return connectivityStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return powerSaveStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return enabledStream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<String> onNotificationAction(
    void Function(String) callback, {
    Function? onError,
  }) {
    return events
        .where((event) => event.type == EventType.notificationAction)
        .map((event) => event.data?.toString() ?? '')
        .listen(callback, onError: onError);
  }

  @override
  StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  }) {
    return httpStream.listen(callback, onError: onError);
  }

  @override
  Future<void> startTrip(TripConfig config) async {
    _methodCalls.add('startTrip');
    final now = DateTime.now();
    _tripState = TripState(
      tripId: config.tripId ?? 'mock-trip',
      createdAt: now,
      startedAt: now,
      startLocation: null,
      lastLocation: null,
      distanceMeters: 0,
      idleSeconds: 0,
      maxSpeedKph: 0,
      started: true,
      ended: false,
    );
  }

  @override
  Future<TripSummary?>? stopTrip() async {
    if (_tripState == null) {
      _methodCalls.add('stopTrip');
      return null;
    }
    _methodCalls.add('stopTrip');
    _tripSummary ??= TripSummary(
      tripId: _tripState?.tripId ?? 'mock-trip',
      distanceMeters: 0,
      durationSeconds: 0,
      averageSpeedKph: 0,
      maxSpeedKph: 0,
      idleSeconds: 0,
      startedAt: _tripState?.startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
    );
    return _tripSummary;
  }

  @override
  TripState? getTripState() {
    _methodCalls.add('getTripState');
    return _tripState;
  }

  @override
  StreamSubscription<TripEvent> onTripEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return tripEvents.listen(callback, onError: onError);
  }

  @override
  TrackingProfile? get currentTrackingProfile => _currentTrackingProfile;

  /// Whether tracking automation is enabled.
  bool get trackingAutomationEnabled => _trackingAutomationEnabled;

  @override
  Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  }) async {
    _methodCalls.add('setTrackingProfiles');
    _trackingProfiles
      ..clear()
      ..addAll(profiles);
    _currentTrackingProfile =
        initialProfile ?? (profiles.isNotEmpty ? profiles.keys.first : null);
    _trackingAutomationEnabled = enableAutomation;
  }

  @override
  Future<void> setTrackingProfile(TrackingProfile profile) async {
    _methodCalls.add('setTrackingProfile:$profile');
    _currentTrackingProfile = profile;
  }

  @override
  void startTrackingAutomation() {
    _methodCalls.add('startTrackingAutomation');
    _trackingAutomationEnabled = true;
  }

  @override
  void stopTrackingAutomation() {
    _methodCalls.add('stopTrackingAutomation');
    _trackingAutomationEnabled = false;
  }

  @override
  void clearTrackingProfiles() {
    _methodCalls.add('clearTrackingProfiles');
    _trackingProfiles.clear();
    _currentTrackingProfile = null;
  }

  @override
  StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent event) callback, {
    Function? onError,
  }) {
    return workflowEvents.listen(callback, onError: onError);
  }

  @override
  void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) {
    _methodCalls.add('registerGeofenceWorkflows');
    _workflows
      ..clear()
      ..addAll(workflows);
  }

  @override
  GeofenceWorkflowState? getWorkflowState(String workflowId) {
    return _workflowStates[workflowId];
  }

  @override
  void clearGeofenceWorkflows() {
    _methodCalls.add('clearGeofenceWorkflows');
    _workflows.clear();
    _workflowStates.clear();
  }

  @override
  void stopGeofenceWorkflows() {
    _methodCalls.add('stopGeofenceWorkflows');
  }

  @override
  Future<BatteryStats> getBatteryStats() async {
    _methodCalls.add('getBatteryStats');
    return _batteryStats;
  }

  /// Sets mock battery stats.
  void setBatteryStats(BatteryStats stats) {
    _batteryStats = stats;
  }

  @override
  Future<PowerState> getPowerState() async {
    _methodCalls.add('getPowerState');
    return _powerState;
  }

  @override
  Future<BatteryRunway> estimateBatteryRunway() async {
    _methodCalls.add('estimateBatteryRunway');
    final currentLevel =
        _batteryStats.currentBatteryLevel ?? _powerState.batteryLevel;
    final trackingMinutes = _batteryStats.trackingDurationMinutes;

    if (!_powerState.isCharging && trackingMinutes < 5) {
      return BatteryRunway(
        duration: Duration.zero,
        lowPowerDuration: Duration.zero,
        recommendation: 'Insufficient data to estimate runway yet.',
        currentLevel: currentLevel,
        isCharging: false,
        confidence: 0,
      );
    }

    return BatteryRunwayCalculator.calculate(
      currentLevel: currentLevel,
      isCharging: _batteryStats.isCharging ?? _powerState.isCharging,
      drainPercent: _batteryStats.estimatedDrainPercent,
      trackingMinutes: trackingMinutes,
    );
  }

  /// Sets mock power state and emits a change event.
  void setPowerState(
    PowerState state, {
    PowerStateChangeType changeType = PowerStateChangeType.batteryLevel,
  }) {
    final previous = _powerState;
    _powerState = state;
    _powerStateController.add(
      PowerStateChangeEvent(
        previous: previous,
        current: state,
        changeType: changeType,
      ),
    );
  }

  @override
  StreamSubscription<PowerStateChangeEvent> onPowerStateChangeWithObj(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  }) {
    return powerStateStream.listen(callback, onError: onError);
  }

  @override
  Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) async {
    _methodCalls.add('setAdaptiveTracking');
    _adaptiveTrackingConfig = config;
  }

  @override
  AdaptiveTrackingConfig? get adaptiveTrackingConfig => _adaptiveTrackingConfig;

  @override
  Future<AdaptiveSettings> calculateAdaptiveSettings() async {
    final level = _powerState.batteryLevel;
    final isCritical = level <= 5 || _powerState.isPowerSaveMode;
    final isLow = level <= 15;

    if (isCritical) {
      return const AdaptiveSettings(
        distanceFilter: 200,
        desiredAccuracy: DesiredAccuracy.low,
        heartbeatInterval: 900,
        gpsEnabled: false,
        reason: 'critical battery',
      );
    }

    if (isLow) {
      return const AdaptiveSettings(
        distanceFilter: 100,
        desiredAccuracy: DesiredAccuracy.medium,
        heartbeatInterval: 120,
        gpsEnabled: true,
        reason: 'low battery',
      );
    }

    return const AdaptiveSettings(
      distanceFilter: 25,
      desiredAccuracy: DesiredAccuracy.high,
      heartbeatInterval: 60,
      gpsEnabled: true,
      reason: 'normal battery',
    );
  }

  @override
  Future<void> setSpoofDetection(SpoofDetectionConfig config) async {
    _methodCalls.add('setSpoofDetection');
    _spoofDetectionConfig = config;
  }

  @override
  SpoofDetectionConfig? get spoofDetectionConfig => _spoofDetectionConfig;

  @override
  SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) {
    return null;
  }

  @override
  Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]) async {
    _methodCalls.add('startSignificantChangeMonitoring');
    _significantChangeMonitoring = true;
  }

  @override
  Future<void> stopSignificantChangeMonitoring() async {
    _methodCalls.add('stopSignificantChangeMonitoring');
    _significantChangeMonitoring = false;
  }

  @override
  bool get isSignificantChangeMonitoringActive => _significantChangeMonitoring;

  @override
  void setErrorHandler(ErrorRecoveryConfig config) {
    _methodCalls.add('setErrorHandler');
    _errorRecoveryConfig = config;
    _errorRecoveryManager ??= ErrorRecoveryManager(config);
    _errorRecoveryManager!.configure(config);
  }

  @override
  ErrorRecoveryManager? get errorRecoveryManager => _errorRecoveryManager;

  /// Last configured error recovery settings.
  ErrorRecoveryConfig? get errorRecoveryConfig => _errorRecoveryConfig;

  @override
  Future<RecoveryAction> handleError(LocusError error) async {
    if (_errorRecoveryManager != null) {
      return _errorRecoveryManager!.handleError(error);
    }
    _errorController.add(error);
    return RecoveryAction.ignore;
  }

  @override
  Future<bool> isTracking() async {
    return _state.enabled;
  }

  @override
  bool get isForeground => _isForeground;

  /// Sets whether the app is foregrounded.
  void setIsForeground(bool isForeground) {
    _isForeground = isForeground;
  }

  @override
  void startLifecycleObserving() {
    _methodCalls.add('startLifecycleObserving');
  }

  @override
  void stopLifecycleObserving() {
    _methodCalls.add('stopLifecycleObserving');
  }

  @override
  Future<bool> isInActiveGeofence() async {
    return false;
  }

  @override
  Future<DiagnosticsSnapshot> getDiagnostics() async {
    return DiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      state: _state,
      config: _config.toMap(),
      queue: List.unmodifiable(_queue),
      metadata: const {},
    );
  }

  @override
  Future<bool> applyRemoteCommand(RemoteCommand command) async {
    _methodCalls.add('applyRemoteCommand:${command.type}');
    return true;
  }

  @override
  Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  }) {
    return const Stream.empty();
  }

  @override
  StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
    Function? onError,
  }) {
    return locationAnomalies(config: config).listen(callback, onError: onError);
  }

  @override
  Stream<LocationQuality> locationQuality({
    LocationQualityConfig config = const LocationQualityConfig(),
  }) {
    return const Stream.empty();
  }

  @override
  StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  }) {
    return locationQuality(config: config).listen(callback, onError: onError);
  }

  @override
  Future<void> startBatteryBenchmark() async {
    _methodCalls.add('startBatteryBenchmark');
    _activeBenchmark = BatteryBenchmark();
    _activeBenchmark!.start(initialBattery: _powerState.batteryLevel);
  }

  @override
  Future<BenchmarkResult?> stopBatteryBenchmark() async {
    _methodCalls.add('stopBatteryBenchmark');
    if (_activeBenchmark == null || !_activeBenchmark!.isRunning) {
      return null;
    }
    final result = _activeBenchmark!.finish(
      currentBattery: _powerState.batteryLevel,
    );
    _activeBenchmark = null;
    return result;
  }

  @override
  void recordBenchmarkLocationUpdate({double? accuracy}) {
    _methodCalls.add('recordBenchmarkLocationUpdate');
    _activeBenchmark?.recordLocationUpdate(accuracy: accuracy);
  }

  @override
  void recordBenchmarkSync() {
    _methodCalls.add('recordBenchmarkSync');
    _activeBenchmark?.recordSync();
  }

  @override
  Future<void> setSyncPolicy(SyncPolicy policy) async {
    _methodCalls.add('setSyncPolicy');
    _syncPolicy = policy;
  }

  /// Returns the last sync policy configured on the mock.
  SyncPolicy? get syncPolicy => _syncPolicy;

  @override
  Future<SyncDecision> evaluateSyncPolicy({required SyncPolicy policy}) async {
    final power = _powerState;
    final behavior = policy.getBehavior(
      networkType: NetworkType.wifi,
      batteryPercent: power.batteryLevel,
      isCharging: power.isCharging,
      isMetered: false,
      isForeground: _isForeground,
    );

    switch (behavior) {
      case SyncBehavior.immediate:
        return SyncDecision.proceed;
      case SyncBehavior.batch:
        return SyncDecision.batch(
          policy.batchSize,
          delay: policy.batchInterval,
        );
      case SyncBehavior.queue:
        return SyncDecision.defer('Queued for later');
      case SyncBehavior.manual:
        return SyncDecision.defer('Manual sync required');
    }
  }

  @override
  Stream<GeolocationEvent<dynamic>> get events => _eventsController.stream;

  @override
  Stream<Location> get locationStream => _locationController.stream;

  @override
  Stream<Location> get motionChangeStream => _motionChangeController.stream;

  @override
  Stream<Activity> get activityStream => _activityChangeController.stream;

  @override
  Stream<ProviderChangeEvent> get providerStream =>
      _providerChangeController.stream;

  @override
  Stream<GeofenceEvent> get geofenceStream => _geofenceController.stream;

  @override
  Stream<ConnectivityChangeEvent> get connectivityStream =>
      _connectivityController.stream;

  @override
  Stream<HttpEvent> get httpStream => _httpController.stream;

  @override
  Stream<Location> get heartbeatStream => _heartbeatController.stream;

  @override
  Stream<bool> get enabledStream => _enabledChangeController.stream;

  @override
  Stream<bool> get powerSaveStream => _powerSaveController.stream;

  @override
  Stream<TripEvent> get tripEvents => _tripEventController.stream;

  @override
  Stream<GeofenceWorkflowEvent> get workflowEvents =>
      _workflowController.stream;

  @override
  Stream<PowerStateChangeEvent> get powerStateStream =>
      _powerStateController.stream;

  @override
  Stream<SignificantChangeEvent>? get significantChangeStream => null;

  @override
  Stream<LocusError>? get errorStream =>
      _errorRecoveryManager?.errors ?? _errorController.stream;

  /// Disposes all stream controllers.
  Future<void> dispose() async {
    await _locationController.close();
    await _motionChangeController.close();
    await _activityChangeController.close();
    await _providerChangeController.close();
    await _geofenceController.close();
    await _connectivityController.close();
    await _httpController.close();
    await _heartbeatController.close();
    await _enabledChangeController.close();
    await _powerSaveController.close();
    await _powerStateController.close();
    await _tripEventController.close();
    await _workflowController.close();
    await _eventsController.close();
    await _errorController.close();
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
