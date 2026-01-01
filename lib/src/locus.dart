library;

import 'dart:async';

import 'package:locus/src/battery/battery.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/events/events.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/core/method_channel_locus.dart';

// Export types needed for sync body builder
export 'package:locus/src/core/locus_interface.dart'
    show SyncBodyBuilder, SyncBodyContext, HeadlessEventCallback;

/// Main class for interacting with background geolocation services.
///
/// This class serves as a facade for the core Locus modules.
class Locus {
  static LocusInterface _instance = MethodChannelLocus();

  /// Current Locus implementation (method-channel or mock).
  static LocusInterface get instance => _instance;

  /// Overrides the Locus implementation (useful for tests).
  static void setMockInstance(LocusInterface mock) {
    _instance = mock;
  }
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
  // Location Methods
  // ============================================================

  /// Gets the current position.
  static Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    JsonMap? extras,
  }) {
    return _instance.getCurrentPosition(
      samples: samples,
      timeout: timeout,
      maximumAge: maximumAge,
      persist: persist,
      desiredAccuracy: desiredAccuracy,
      extras: extras,
    );
  }

  /// Gets stored locations.
  static Future<List<Location>> getLocations({int? limit}) {
    return _instance.getLocations(limit: limit);
  }

  /// Changes the motion state (moving/stationary).
  static Future<bool> changePace(bool isMoving) {
    return _instance.changePace(isMoving);
  }

  /// Sets the odometer value.
  static Future<double> setOdometer(double value) {
    return _instance.setOdometer(value);
  }

  // ============================================================
  // Geofencing Methods
  // ============================================================

  /// Adds a single geofence.
  static Future<bool> addGeofence(Geofence geofence) {
    return _instance.addGeofence(geofence);
  }

  /// Adds multiple geofences.
  static Future<bool> addGeofences(List<Geofence> geofences) {
    return _instance.addGeofences(geofences);
  }

  /// Removes a geofence by identifier.
  static Future<bool> removeGeofence(String identifier) {
    return _instance.removeGeofence(identifier);
  }

  /// Removes all geofences.
  static Future<bool> removeGeofences() {
    return _instance.removeGeofences();
  }

  /// Gets all registered geofences.
  static Future<List<Geofence>> getGeofences() {
    return _instance.getGeofences();
  }

  /// Gets a geofence by identifier.
  static Future<Geofence?> getGeofence(String identifier) {
    return _instance.getGeofence(identifier);
  }

  /// Checks if a geofence exists.
  static Future<bool> geofenceExists(String identifier) {
    return _instance.geofenceExists(identifier);
  }

  /// Starts geofence-only mode.
  static Future<bool> startGeofences() {
    return _instance.startGeofences();
  }

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
  // Sync Methods
  // ============================================================

  /// Triggers an immediate sync of pending locations.
  static Future<bool> sync() {
    return _instance.sync();
  }

  /// Resumes sync after a pause (e.g., 401 token refresh).
  static Future<bool> resumeSync() {
    return _instance.resumeSync();
  }

  /// Destroys all stored locations.
  static Future<bool> destroyLocations() {
    return _instance.destroyLocations();
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
  static void setSyncBodyBuilder(SyncBodyBuilder? builder) {
    _instance.setSyncBodyBuilder(builder);
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

  /// Emails the log to the given address.
  static Future<void> emailLog(String email) async {
    await _instance.emailLog(email);
  }

  /// Plays a system sound.
  static Future<void> playSound(String name) async {
    await _instance.playSound(name);
  }

  // ============================================================
  // Queue Methods
  // ============================================================

  /// Enqueues a custom payload for offline-first delivery.
  static Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) {
    return _instance.enqueue(payload,
        type: type, idempotencyKey: idempotencyKey);
  }

  /// Returns queued payloads.
  static Future<List<QueueItem>> getQueue({int? limit}) {
    return _instance.getQueue(limit: limit);
  }

  /// Clears all queued payloads.
  static Future<void> clearQueue() {
    return _instance.clearQueue();
  }

  /// Attempts to sync queued payloads immediately.
  static Future<int> syncQueue({int? limit}) {
    return _instance.syncQueue(limit: limit);
  }

  // ============================================================
  // Permissions
  // ============================================================

  /// Requests all required permissions.
  static Future<bool> requestPermission() {
    return _instance.requestPermission();
  }

  // ============================================================
  // State-Agnostic Streams
  // ============================================================

  /// Stream of location updates.
  static Stream<Location> get locationStream {
    return _instance.locationStream;
  }

  /// Stream of motion change events (moving/stationary transitions).
  static Stream<Location> get motionChangeStream {
    return _instance.motionChangeStream;
  }

  /// Stream of activity recognition updates.
  static Stream<Activity> get activityStream {
    return _instance.activityStream;
  }

  /// Stream of geofence crossing events.
  static Stream<GeofenceEvent> get geofenceStream {
    return _instance.geofenceStream;
  }

  /// Stream of provider state changes.
  static Stream<ProviderChangeEvent> get providerStream {
    return _instance.providerStream;
  }

  /// Stream of connectivity changes.
  static Stream<ConnectivityChangeEvent> get connectivityStream {
    return _instance.connectivityStream;
  }

  /// Stream of heartbeat events.
  static Stream<Location> get heartbeatStream {
    return _instance.heartbeatStream;
  }

  /// Stream of HTTP sync events.
  static Stream<HttpEvent> get httpStream {
    return _instance.httpStream;
  }

  /// Stream of enabled state changes.
  static Stream<bool> get enabledStream {
    return _instance.enabledStream;
  }

  /// Stream of power save mode changes.
  static Stream<bool> get powerSaveStream {
    return _instance.powerSaveStream;
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
  // Typed Event Subscriptions
  // ============================================================

  static StreamSubscription<Location> onLocation(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _instance.onLocation(callback, onError: onError);
  }

  static StreamSubscription<Location> onMotionChange(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _instance.onMotionChange(callback, onError: onError);
  }

  static StreamSubscription<Activity> onActivityChange(
    void Function(Activity) callback, {
    Function? onError,
  }) {
    return _instance.onActivityChange(callback, onError: onError);
  }

  static StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback, {
    Function? onError,
  }) {
    return _instance.onProviderChange(callback, onError: onError);
  }

  static StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback, {
    Function? onError,
  }) {
    return _instance.onGeofence(callback, onError: onError);
  }

  static StreamSubscription<dynamic> onGeofencesChange(
    void Function(dynamic) callback, {
    Function? onError,
  }) {
    return _instance.onGeofencesChange(callback, onError: onError);
  }

  static StreamSubscription<Location> onHeartbeat(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _instance.onHeartbeat(callback, onError: onError);
  }

  static StreamSubscription<Location> onSchedule(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return _instance.onSchedule(callback, onError: onError);
  }

  static StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  }) {
    return _instance.onConnectivityChange(callback, onError: onError);
  }

  static StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return _instance.onPowerSaveChange(callback, onError: onError);
  }

  static StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return _instance.onEnabledChange(callback, onError: onError);
  }

  static StreamSubscription<String> onNotificationAction(
    void Function(String) callback, {
    Function? onError,
  }) {
    return _instance.onNotificationAction(callback, onError: onError);
  }

  static StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  }) {
    return _instance.onHttp(callback, onError: onError);
  }

  // ============================================================
  // Trip Lifecycle
  // ============================================================

  static Future<void> startTrip(TripConfig config) =>
      _instance.startTrip(config);

  static TripSummary? stopTrip() => _instance.stopTrip();

  static TripState? getTripState() => _instance.getTripState();

  static Stream<TripEvent> get tripEvents => _instance.tripEvents;

  static StreamSubscription<TripEvent> onTripEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return _instance.onTripEvent(callback, onError: onError);
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
  // Geofence Workflows
  // ============================================================

  static Stream<GeofenceWorkflowEvent> get workflowEvents =>
      _instance.workflowEvents;

  static StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent event) callback, {
    Function? onError,
  }) {
    return _instance.onWorkflowEvent(callback, onError: onError);
  }

  static void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) =>
      _instance.registerGeofenceWorkflows(workflows);

  static GeofenceWorkflowState? getWorkflowState(String workflowId) =>
      _instance.getWorkflowState(workflowId);

  static void clearGeofenceWorkflows() => _instance.clearGeofenceWorkflows();

  static void stopGeofenceWorkflows() => _instance.stopGeofenceWorkflows();

  // ============================================================
  // Battery Optimization
  // ============================================================

  static Future<BatteryStats> getBatteryStats() => _instance.getBatteryStats();

  static Future<PowerState> getPowerState() => _instance.getPowerState();

  static Stream<PowerStateChangeEvent> get powerStateStream =>
      _instance.powerStateStream;

  static StreamSubscription<PowerStateChangeEvent> onPowerStateChangeWithObj(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  }) {
    return _instance.onPowerStateChangeWithObj(callback, onError: onError);
  }

  static Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) =>
      _instance.setAdaptiveTracking(config);

  static AdaptiveTrackingConfig? get adaptiveTrackingConfig =>
      _instance.adaptiveTrackingConfig;

  /// Calculates optimal settings based on current conditions.
  static Future<AdaptiveSettings> calculateAdaptiveSettings() =>
      _instance.calculateAdaptiveSettings();

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

  static Future<void> setSyncPolicy(SyncPolicy policy) async {
    await _instance.setSyncPolicy(policy);
  }

  static Future<SyncDecision> evaluateSyncPolicy({
    required SyncPolicy policy,
  }) async {
    return _instance.evaluateSyncPolicy(policy: policy);
  }
}
