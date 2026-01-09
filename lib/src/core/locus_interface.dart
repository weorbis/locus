import 'dart:async';

import 'package:locus/src/config/config.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';

/// Callback type for headless background events.
typedef HeadlessEventCallback = Future<void> Function(HeadlessEvent event);

/// Callback type for building custom HTTP sync body.
///
/// Called before each sync request to construct the HTTP body.
/// [locations] contains the pending locations to sync.
/// [extras] contains the extras from Config.
///
/// Must return a JSON-serializable Map that will be sent as the request body.
typedef SyncBodyBuilder = Future<JsonMap> Function(
    List<Location> locations, JsonMap extras);

/// Context passed to headless sync body builder.
class SyncBodyContext {
  /// Creates from a map (for headless deserialization).
  factory SyncBodyContext.fromMap(Map<String, dynamic> map) {
    final locationsRaw = map['locations'] as List? ?? [];
    final locations = locationsRaw
        .map((l) => Location.fromMap(Map<String, dynamic>.from(l as Map)))
        .toList();
    final extras = Map<String, dynamic>.from(map['extras'] as Map? ?? {});
    return SyncBodyContext(locations: locations, extras: extras);
  }
  const SyncBodyContext({required this.locations, required this.extras});

  /// Pending locations to sync.
  final List<Location> locations;

  /// Extras from Config.
  final JsonMap extras;
}

/// Contract for Locus implementations (method-channel or mock).
abstract class LocusInterface {
  // ============================================================
  // Event Stream
  // ============================================================
  Stream<GeolocationEvent<dynamic>> get events;

  // ============================================================
  // Lifecycle Methods
  // ============================================================
  Future<GeolocationState> ready(Config config, {bool skipValidation = false});

  Future<GeolocationState> start();
  Future<GeolocationState> stop();
  Future<GeolocationState> getState();

  // ============================================================
  // Location Methods
  // ============================================================
  Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    JsonMap? extras,
  });

  Future<List<Location>> getLocations({int? limit});
  Future<List<Location>> queryLocations(LocationQuery query);
  Future<LocationSummary> getLocationSummary({
    DateTime? date,
    LocationQuery? query,
  });
  Future<bool> changePace(bool isMoving);
  Future<double> setOdometer(double value);

  // ============================================================
  // Geofencing Methods
  // ============================================================
  Future<bool> addGeofence(Geofence geofence);
  Future<bool> addGeofences(List<Geofence> geofences);
  Future<bool> removeGeofence(String identifier);
  Future<bool> removeGeofences();
  Future<List<Geofence>> getGeofences();
  Future<Geofence?> getGeofence(String identifier);
  Future<bool> geofenceExists(String identifier);
  Future<bool> startGeofences();

  // ============================================================
  // Polygon Geofencing Methods
  // ============================================================
  Future<bool> addPolygonGeofence(PolygonGeofence polygon);
  Future<int> addPolygonGeofences(List<PolygonGeofence> polygons);
  Future<bool> removePolygonGeofence(String identifier);
  Future<void> removeAllPolygonGeofences();
  Future<List<PolygonGeofence>> getPolygonGeofences();
  Future<PolygonGeofence?> getPolygonGeofence(String identifier);
  Future<bool> polygonGeofenceExists(String identifier);
  Stream<PolygonGeofenceEvent> get polygonGeofenceEvents;

  // ============================================================
  // Privacy Zone Methods
  // ============================================================

  /// Adds a privacy zone where location data will be obfuscated or excluded.
  Future<void> addPrivacyZone(PrivacyZone zone);

  /// Adds multiple privacy zones.
  Future<void> addPrivacyZones(List<PrivacyZone> zones);

  /// Removes a privacy zone by identifier.
  Future<bool> removePrivacyZone(String identifier);

  /// Removes all privacy zones.
  Future<void> removeAllPrivacyZones();

  /// Gets a privacy zone by identifier.
  Future<PrivacyZone?> getPrivacyZone(String identifier);

  /// Gets all registered privacy zones.
  Future<List<PrivacyZone>> getPrivacyZones();

  /// Enables or disables a privacy zone.
  Future<bool> setPrivacyZoneEnabled(String identifier, bool enabled);

  /// Stream of privacy zone change events.
  Stream<PrivacyZoneEvent> get privacyZoneEvents;

  // ============================================================
  // Configuration Methods
  // ============================================================
  Future<void> setConfig(Config config);
  Future<void> destroy();
  Future<void> reset(Config config);

  // ============================================================
  // Scheduling Methods
  // ============================================================
  Future<bool> startSchedule();
  Future<bool> stopSchedule();

  // ============================================================
  // Sync Methods
  // ============================================================

  /// Whether sync is currently paused.
  bool get isSyncPaused;

  /// Pauses all sync operations.
  ///
  /// When paused, locations will continue to be collected and stored,
  /// but no HTTP sync requests will be sent until [resume] is called.
  Future<void> pauseSync();

  /// Triggers an immediate sync of pending locations.
  Future<bool> sync();

  /// Resumes sync after a pause or app startup.
  ///
  /// Sync is paused by default on app startup to prevent race conditions.
  /// Call this after your app has completed initialization.
  Future<bool> resume();

  /// Destroys all stored locations.
  Future<bool> destroyLocations();

  // ============================================================
  // Pre-Sync Validation
  // ============================================================

  /// Sets a callback for pre-sync validation.
  ///
  /// The callback is invoked before each sync attempt. Return `true` to
  /// proceed with the sync, `false` to skip and keep locations queued.
  void setPreSyncValidator(PreSyncValidator? validator);

  /// Clears the pre-sync validator callback.
  void clearPreSyncValidator();

  // ============================================================
  // Sync Body Builder
  // ============================================================

  /// Sets a callback to build custom HTTP sync body.
  ///
  /// When set, this callback is invoked before each sync request.
  /// The returned Map is used as the HTTP request body instead of
  /// the default location array format.
  ///
  /// Example:
  /// ```dart
  /// Locus.setSyncBodyBuilder((locations, extras) async {
  ///   return {
  ///     'ownerId': extras['ownerId'],
  ///     'polygons': locations.map((l) => l.coords.toJson()).toList(),
  ///   };
  /// });
  /// ```
  Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder);

  /// Clears the sync body builder callback.
  void clearSyncBodyBuilder();

  /// Registers a headless-compatible sync body builder.
  ///
  /// The callback must be a top-level or static function (not a closure)
  /// to work in headless/terminated mode.
  ///
  /// Example:
  /// ```dart
  /// @pragma('vm:entry-point')
  /// Future<JsonMap> buildSyncBody(SyncBodyContext context) async {
  ///   return {
  ///     'locations': context.locations.map((l) => l.toJson()).toList(),
  ///   };
  /// }
  ///
  /// Locus.registerHeadlessSyncBodyBuilder(buildSyncBody);
  /// ```
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  );

  // ============================================================
  // Headless/Background Task Methods
  // ============================================================
  Future<bool> registerHeadlessTask(HeadlessEventCallback callback);
  Future<int> startBackgroundTask();
  Future<void> stopBackgroundTask(int taskId);

  // ============================================================
  // Logging Methods
  // ============================================================
  Future<List<LogEntry>> getLog();

  // ============================================================
  // Queue Methods
  // ============================================================
  Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  });

  Future<List<QueueItem>> getQueue({int? limit});
  Future<void> clearQueue();
  Future<int> syncQueue({int? limit});

  // ============================================================
  // Permissions
  // ============================================================
  Future<bool> requestPermission();

  // ============================================================
  // State-Agnostic Streams
  // ============================================================
  Stream<Location> get locationStream;
  Stream<Location> get motionChangeStream;
  Stream<Activity> get activityStream;
  Stream<GeofenceEvent> get geofenceStream;
  Stream<ProviderChangeEvent> get providerStream;
  Stream<ConnectivityChangeEvent> get connectivityStream;
  Stream<Location> get heartbeatStream;
  Stream<HttpEvent> get httpStream;
  Stream<bool> get enabledStream;
  Stream<bool> get powerSaveStream;

  // ============================================================
  // Dynamic Headers
  // ============================================================
  void setHeadersCallback(Future<Map<String, String>> Function()? callback);
  void clearHeadersCallback();
  Future<void> refreshHeaders();

  // ============================================================
  // Typed Event Subscriptions
  // ============================================================
  StreamSubscription<Location> onLocation(
    void Function(Location) callback, {
    Function? onError,
  });

  StreamSubscription<Location> onMotionChange(
    void Function(Location) callback, {
    Function? onError,
  });

  StreamSubscription<Activity> onActivityChange(
    void Function(Activity) callback, {
    Function? onError,
  });

  StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback, {
    Function? onError,
  });

  StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback, {
    Function? onError,
  });

  StreamSubscription<dynamic> onGeofencesChange(
    void Function(dynamic) callback, {
    Function? onError,
  });

  StreamSubscription<Location> onHeartbeat(
    void Function(Location) callback, {
    Function? onError,
  });

  StreamSubscription<Location> onSchedule(
    void Function(Location) callback, {
    Function? onError,
  });

  StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  });

  StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback, {
    Function? onError,
  });

  StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback, {
    Function? onError,
  });

  StreamSubscription<String> onNotificationAction(
    void Function(String) callback, {
    Function? onError,
  });

  StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  });

  // ============================================================
  // Trip Lifecycle
  // ============================================================
  Future<void> startTrip(TripConfig config);
  Future<TripSummary?>? stopTrip();
  TripState? getTripState();
  Stream<TripEvent> get tripEvents;
  StreamSubscription<TripEvent> onTripEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  });

  // ============================================================
  // Tracking Profiles
  // ============================================================
  TrackingProfile? get currentTrackingProfile;
  Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  });
  Future<void> setTrackingProfile(TrackingProfile profile);
  void startTrackingAutomation();
  void stopTrackingAutomation();
  void clearTrackingProfiles();

  // ============================================================
  // Geofence Workflows
  // ============================================================
  Stream<GeofenceWorkflowEvent> get workflowEvents;
  StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent event) callback, {
    Function? onError,
  });
  void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows);
  GeofenceWorkflowState? getWorkflowState(String workflowId);
  void clearGeofenceWorkflows();
  void stopGeofenceWorkflows();

  // ============================================================
  // Battery Optimization
  // ============================================================
  Future<BatteryStats> getBatteryStats();
  Future<PowerState> getPowerState();
  Future<BatteryRunway> estimateBatteryRunway();
  Stream<PowerStateChangeEvent> get powerStateStream;
  StreamSubscription<PowerStateChangeEvent> onPowerStateChangeWithObj(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  });
  Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config);
  AdaptiveTrackingConfig? get adaptiveTrackingConfig;
  Future<AdaptiveSettings> calculateAdaptiveSettings();

  // ============================================================
  // Advanced Features
  // ============================================================
  Future<void> setSpoofDetection(SpoofDetectionConfig config);
  SpoofDetectionConfig? get spoofDetectionConfig;
  SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  });

  Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]);
  Future<void> stopSignificantChangeMonitoring();
  bool get isSignificantChangeMonitoringActive;
  Stream<SignificantChangeEvent>? get significantChangeStream;
  void setErrorHandler(ErrorRecoveryConfig config);
  ErrorRecoveryManager? get errorRecoveryManager;
  Stream<LocusError>? get errorStream;
  Future<RecoveryAction> handleError(LocusError error);
  Future<bool> isTracking();
  bool get isForeground;
  void startLifecycleObserving();
  void stopLifecycleObserving();
  Future<bool> isInActiveGeofence();

  // ============================================================
  // Diagnostics
  // ============================================================
  Future<DiagnosticsSnapshot> getDiagnostics();
  Future<bool> applyRemoteCommand(RemoteCommand command);

  Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  });
  StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
    Function? onError,
  });

  Stream<LocationQuality> locationQuality({
    LocationQualityConfig config = const LocationQualityConfig(),
  });
  StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  });

  // ============================================================
  // Benchmark
  // ============================================================
  Future<void> startBatteryBenchmark();
  Future<BenchmarkResult?> stopBatteryBenchmark();
  void recordBenchmarkLocationUpdate({double? accuracy});
  void recordBenchmarkSync();

  // ============================================================
  // Sync Policy
  // ============================================================
  Future<void> setSyncPolicy(SyncPolicy policy);
  Future<SyncDecision> evaluateSyncPolicy({required SyncPolicy policy});
}
