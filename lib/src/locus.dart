library;

import 'dart:async';

import 'package:locus/src/config/config.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/core/method_channel_locus.dart';

// Export types needed for sync body builder
export 'package:locus/src/core/locus_interface.dart'
    show SyncBodyBuilder, SyncBodyContext, HeadlessEventCallback;

// Export location history types
export 'package:locus/src/features/location/models/location_history.dart'
    show LocationQuery, LocationSummary, FrequentLocation;

/// Main class for interacting with background geolocation services.
///
/// This class serves as a facade for the core Locus modules.
///
/// ## v2.0 Service API
///
/// Access organized services via static getters:
/// ```dart
/// // Location operations
/// await Locus.location.getCurrentPosition();
/// Locus.location.stream.listen((loc) => print(loc));
///
/// // Geofencing
/// await Locus.geofencing.add(geofence);
///
/// // Privacy zones
/// await Locus.privacy.add(zone);
///
/// // Trip tracking
/// await Locus.trips.start(config);
///
/// // Data sync
/// await Locus.sync.now();
///
/// // Battery optimization
/// await Locus.battery.estimateRunway();
/// ```
class Locus {
  static LocusInterface _instance = MethodChannelLocus();

  /// Current Locus implementation (method-channel or mock).
  static LocusInterface get instance => _instance;

  /// Overrides the Locus implementation (useful for tests).
  static void setMockInstance(LocusInterface mock) {
    _instance = mock;
  }

  // ============================================================
  // v2.0 Service API
  // ============================================================

  /// Location service for getting positions, tracking, and history.
  ///
  /// Example:
  /// ```dart
  /// final position = await Locus.location.getCurrentPosition();
  /// Locus.location.stream.listen((loc) => print(loc));
  /// ```
  static final LocationService location = LocationServiceImpl(() => _instance);

  /// Geofencing service for circular, polygon geofences and workflows.
  ///
  /// Example:
  /// ```dart
  /// await Locus.geofencing.add(Geofence(...));
  /// Locus.geofencing.events.listen((event) => print(event));
  /// ```
  static final GeofenceService geofencing =
      GeofenceServiceImpl(() => _instance);

  /// Privacy service for managing privacy zones.
  ///
  /// Example:
  /// ```dart
  /// await Locus.privacy.add(PrivacyZone.create(...));
  /// ```
  static final PrivacyService privacy = PrivacyServiceImpl(() => _instance);

  /// Trip service for tracking journeys.
  ///
  /// Example:
  /// ```dart
  /// await Locus.trips.start(TripConfig(...));
  /// final summary = await Locus.trips.stop();
  /// ```
  static final TripService trips = TripServiceImpl(() => _instance);

  /// Sync service for data synchronization and queue management.
  ///
  /// Example:
  /// ```dart
  /// await Locus.dataSync.now();
  /// await Locus.dataSync.enqueue({'type': 'check-in'});
  /// ```
  static final SyncService dataSync = SyncServiceImpl(() => _instance);

  /// Battery service for power management and adaptive tracking.
  ///
  /// Example:
  /// ```dart
  /// final runway = await Locus.battery.estimateRunway();
  /// await Locus.battery.setAdaptiveTracking(config);
  /// ```
  static final BatteryService battery = BatteryServiceImpl(() => _instance);

  // ============================================================
  // Event Stream
  // ============================================================

  /// Stream of all geolocation events.
  static Stream<GeolocationEvent<dynamic>> get events => _instance.events;

  // ============================================================
  // Lifecycle Methods
  // ============================================================

  /// Initializes the plugin with the given configuration.
  static Future<GeolocationState> ready(
    Config config, {
    bool skipValidation = false,
  }) {
    return _instance.ready(config, skipValidation: skipValidation);
  }

  /// Starts the background geolocation service.
  static Future<GeolocationState> start() => _instance.start();

  /// Stops the background geolocation service.
  static Future<GeolocationState> stop() => _instance.stop();

  /// Gets the current state of the service.
  static Future<GeolocationState> getState() => _instance.getState();

  // ============================================================
  // Configuration Methods
  // ============================================================

  /// Updates the configuration.
  static Future<void> setConfig(Config config) {
    return _instance.setConfig(config);
  }

  /// Destroys the SDK instance, cleaning up all resources and static state.
  static Future<void> destroy() {
    return _instance.destroy();
  }

  /// Resets configuration to defaults, then applies the given config.
  static Future<void> reset(Config config) {
    return _instance.reset(config);
  }

  // ============================================================
  // Data Management
  // ============================================================

  /// Clears stored tracking data without stopping the service.
  ///
  /// This is a lightweight cleanup helper:
  /// - [clearLocations] removes stored locations (history + pending sync).
  /// - [clearSyncQueue] clears the custom payload queue managed by `dataSync`.
  ///
  /// This does not stop tracking or remove geofences/trip state.
  static Future<void> clearTrackingData({
    bool clearLocations = true,
    bool clearSyncQueue = false,
  }) async {
    final futures = <Future<dynamic>>[];
    if (clearLocations) {
      futures.add(location.destroyLocations());
    }
    if (clearSyncQueue) {
      futures.add(dataSync.clearQueue());
    }
    if (futures.isEmpty) return;
    await Future.wait(futures);
  }

  // ============================================================
  // Scheduling Methods
  // ============================================================

  /// Starts the schedule.
  static Future<bool> startSchedule() {
    return _instance.startSchedule();
  }

  /// Stops the schedule.
  static Future<bool> stopSchedule() {
    return _instance.stopSchedule();
  }

  // ============================================================
  // Sync Body Builder
  // ============================================================

  /// Sets a callback to build custom HTTP sync body.
  ///
  /// When set, this callback is invoked before each sync request.
  /// The returned Map is used as the HTTP request body instead of
  /// the default location array format.
  ///
  /// This is useful for backends that require a specific JSON structure.
  ///
  /// Example (WeOrbis-style envelope):
  /// ```dart
  /// Locus.setSyncBodyBuilder((locations, extras) async {
  ///   return {
  ///     'ownerId': extras['ownerId'],
  ///     'taskId': extras['taskId'],
  ///     'polygons': locations.map((l) => {
  ///       'lat': l.coords.latitude,
  ///       'lng': l.coords.longitude,
  ///       'timestamp': l.timestamp.toIso8601String(),
  ///     }).toList(),
  ///   };
  /// });
  /// ```
  static Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder) {
    return _instance.setSyncBodyBuilder(builder);
  }

  /// Clears the sync body builder callback.
  static void clearSyncBodyBuilder() {
    _instance.clearSyncBodyBuilder();
  }

  /// Registers a headless-compatible sync body builder.
  ///
  /// The callback must be a top-level or static function (not a closure)
  /// to work in headless/terminated mode. The callback is invoked by the
  /// native side when performing background sync.
  ///
  /// Example:
  /// ```dart
  /// // Must be a top-level function
  /// @pragma('vm:entry-point')
  /// Future<JsonMap> buildSyncBody(SyncBodyContext context) async {
  ///   // Read static config from storage if needed
  ///   final prefs = await SharedPreferences.getInstance();
  ///   final ownerId = prefs.getString('ownerId') ?? '';
  ///
  ///   return {
  ///     'ownerId': ownerId,
  ///     'locations': context.locations.map((l) => l.toJson()).toList(),
  ///   };
  /// }
  ///
  /// // Register in main()
  /// await Locus.registerHeadlessSyncBodyBuilder(buildSyncBody);
  /// ```
  static Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) {
    return _instance.registerHeadlessSyncBodyBuilder(builder);
  }

  // ============================================================
  // Headless/Background Task Methods
  // ============================================================

  /// Registers a headless task callback.
  static Future<bool> registerHeadlessTask(HeadlessEventCallback callback) {
    return _instance.registerHeadlessTask(callback);
  }

  /// Starts a background task and returns its ID.
  static Future<int> startBackgroundTask() {
    return _instance.startBackgroundTask();
  }

  /// Stops a background task by ID.
  static Future<void> stopBackgroundTask(int taskId) {
    return _instance.stopBackgroundTask(taskId);
  }

  // ============================================================
  // Logging Methods
  // ============================================================

  /// Gets structured log entries.
  static Future<List<LogEntry>> getLog() {
    return _instance.getLog();
  }

  // ============================================================
  // Permissions
  // ============================================================

  /// Requests all required permissions.
  static Future<bool> requestPermission() {
    return _instance.requestPermission();
  }

  // ============================================================
  // Dynamic Headers
  // ============================================================

  /// Sets a callback to provide dynamic HTTP headers.
  static void setHeadersCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _instance.setHeadersCallback(callback);
  }

  /// Clears the dynamic headers callback.
  static void clearHeadersCallback() {
    _instance.clearHeadersCallback();
  }

  /// Manually triggers a header update.
  static Future<void> refreshHeaders() async {
    await _instance.refreshHeaders();
  }

  // ============================================================
  // Adaptive Tracking Profiles
  // ============================================================

  static TrackingProfile? get currentTrackingProfile =>
      _instance.currentTrackingProfile;

  static Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  }) =>
      _instance.setTrackingProfiles(
        profiles,
        initialProfile: initialProfile,
        rules: rules,
        enableAutomation: enableAutomation,
      );

  static Future<void> setTrackingProfile(TrackingProfile profile) =>
      _instance.setTrackingProfile(profile);

  static void startTrackingAutomation() => _instance.startTrackingAutomation();

  static void stopTrackingAutomation() => _instance.stopTrackingAutomation();

  static void clearTrackingProfiles() => _instance.clearTrackingProfiles();

  // ============================================================
  // Advanced Features
  // ============================================================

  static Future<void> setSpoofDetection(SpoofDetectionConfig config) =>
      _instance.setSpoofDetection(config);

  static SpoofDetectionConfig? get spoofDetectionConfig =>
      _instance.spoofDetectionConfig;

  static SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) =>
      _instance.analyzeForSpoofing(location, isMockProvider: isMockProvider);

  static Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]) =>
      _instance.startSignificantChangeMonitoring(config);

  static Future<void> stopSignificantChangeMonitoring() =>
      _instance.stopSignificantChangeMonitoring();

  static bool get isSignificantChangeMonitoringActive =>
      _instance.isSignificantChangeMonitoringActive;

  static Stream<SignificantChangeEvent>? get significantChangeStream =>
      _instance.significantChangeStream;

  static void setErrorHandler(ErrorRecoveryConfig config) =>
      _instance.setErrorHandler(config);

  static ErrorRecoveryManager? get errorRecoveryManager =>
      _instance.errorRecoveryManager;

  static Stream<LocusError>? get errorStream => _instance.errorStream;

  static Future<RecoveryAction> handleError(LocusError error) =>
      _instance.handleError(error);

  static Future<bool> isTracking() => _instance.isTracking();

  static bool get isForeground => _instance.isForeground;

  static void startLifecycleObserving() => _instance.startLifecycleObserving();

  static void stopLifecycleObserving() => _instance.stopLifecycleObserving();

  static Future<bool> isInActiveGeofence() => _instance.isInActiveGeofence();

  // ============================================================
  // Diagnostics
  // ============================================================

  static Future<DiagnosticsSnapshot> getDiagnostics() =>
      _instance.getDiagnostics();

  static Future<bool> applyRemoteCommand(RemoteCommand command) =>
      _instance.applyRemoteCommand(command);

  /// Stream of detected location anomalies.
  static Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  }) {
    return _instance.locationAnomalies(config: config);
  }

  static StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
    Function? onError,
  }) {
    return _instance.onLocationAnomaly(callback,
        config: config, onError: onError);
  }

  /// Stream of location quality assessments.
  static Stream<LocationQuality> locationQuality({
    LocationQualityConfig config = const LocationQualityConfig(),
  }) {
    return _instance.locationQuality(config: config);
  }

  static StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  }) {
    return _instance.onLocationQuality(callback,
        config: config, onError: onError);
  }

  // ============================================================
  // Benchmark
  // ============================================================

  static Future<void> startBatteryBenchmark() async {
    await _instance.startBatteryBenchmark();
  }

  static Future<BenchmarkResult?> stopBatteryBenchmark() async {
    return _instance.stopBatteryBenchmark();
  }

  static void recordBenchmarkLocationUpdate({double? accuracy}) {
    _instance.recordBenchmarkLocationUpdate(accuracy: accuracy);
  }

  static void recordBenchmarkSync() {
    _instance.recordBenchmarkSync();
  }

  // ============================================================
  // Sync Policy
  // ============================================================

  static Future<SyncDecision> evaluateSyncPolicy({
    required SyncPolicy policy,
  }) async {
    return _instance.evaluateSyncPolicy(policy: policy);
  }
}
