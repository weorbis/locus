library;

import 'dart:async';

// import 'package:flutter/services.dart'; // Unused
import 'package:locus/src/battery/battery.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/events/events.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_lifecycle.dart';
import 'package:locus/src/core/locus_streams.dart';
import 'package:locus/src/core/locus_location.dart';
import 'package:locus/src/core/locus_geofencing.dart';
import 'package:locus/src/core/locus_config.dart';
import 'package:locus/src/core/locus_scheduler.dart';
import 'package:locus/src/core/locus_sync.dart';
import 'package:locus/src/core/locus_headless.dart';
import 'package:locus/src/core/locus_battery.dart';
import 'package:locus/src/core/locus_features.dart';
import 'package:locus/src/core/locus_adaptive.dart';
import 'package:locus/src/core/locus_trip.dart';
import 'package:locus/src/core/locus_profiles.dart';
import 'package:locus/src/core/locus_workflows.dart';
import 'package:locus/src/core/locus_diagnostics.dart';
// import 'package:locus/src/utils/location_utils.dart'; // Unused

/// Callback type for headless background events.
typedef HeadlessEventCallback = Future<void> Function(HeadlessEvent event);

/// Main class for interacting with background geolocation services.
///
/// This class serves as a facade for the core Locus modules.
class Locus {
  // ============================================================
  // Event Stream
  // ============================================================

  /// Stream of all geolocation events.
  static Stream<GeolocationEvent<dynamic>> get events => LocusStreams.events;

  // ============================================================
  // Lifecycle Methods
  // ============================================================

  /// Initializes the plugin with the given configuration.
  static Future<GeolocationState> ready(
    Config config, {
    bool skipValidation = false,
  }) {
    return LocusLifecycle.ready(config, skipValidation: skipValidation);
  }

  /// Starts the background geolocation service.
  static Future<GeolocationState> start() => LocusLifecycle.start();

  /// Stops the background geolocation service.
  static Future<GeolocationState> stop() => LocusLifecycle.stop();

  /// Gets the current state of the service.
  static Future<GeolocationState> getState() => LocusLifecycle.getState();

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
    return LocusLocation.getCurrentPosition(
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
    return LocusLocation.getLocations(limit: limit);
  }

  /// Changes the motion state (moving/stationary).
  static Future<bool> changePace(bool isMoving) {
    return LocusLocation.changePace(isMoving);
  }

  /// Sets the odometer value.
  static Future<double> setOdometer(double value) {
    return LocusLocation.setOdometer(value);
  }

  // ============================================================
  // Geofencing Methods
  // ============================================================

  /// Adds a single geofence.
  static Future<bool> addGeofence(Geofence geofence) {
    return LocusGeofencing.addGeofence(geofence);
  }

  /// Adds multiple geofences.
  static Future<bool> addGeofences(List<Geofence> geofences) {
    return LocusGeofencing.addGeofences(geofences);
  }

  /// Removes a geofence by identifier.
  static Future<bool> removeGeofence(String identifier) {
    return LocusGeofencing.removeGeofence(identifier);
  }

  /// Removes all geofences.
  static Future<bool> removeGeofences() {
    return LocusGeofencing.removeGeofences();
  }

  /// Gets all registered geofences.
  static Future<List<Geofence>> getGeofences() {
    return LocusGeofencing.getGeofences();
  }

  /// Gets a geofence by identifier.
  static Future<Geofence?> getGeofence(String identifier) {
    return LocusGeofencing.getGeofence(identifier);
  }

  /// Checks if a geofence exists.
  static Future<bool> geofenceExists(String identifier) {
    return LocusGeofencing.geofenceExists(identifier);
  }

  /// Starts geofence-only mode.
  static Future<bool> startGeofences() {
    return LocusGeofencing.startGeofences();
  }

  // ============================================================
  // Configuration Methods
  // ============================================================

  /// Updates the configuration.
  static Future<void> setConfig(Config config) {
    return LocusConfig.setConfig(config);
  }

  /// Destroys the SDK instance, cleaning up all resources and static state.
  static Future<void> destroy() {
    return LocusLifecycle.destroy();
  }

  /// Resets configuration to defaults, then applies the given config.
  static Future<void> reset(Config config) {
    return LocusConfig.reset(config);
  }

  // ============================================================
  // Scheduling Methods
  // ============================================================

  /// Starts the schedule.
  static Future<bool> startSchedule() {
    return LocusScheduler.startSchedule();
  }

  /// Stops the schedule.
  static Future<bool> stopSchedule() {
    return LocusScheduler.stopSchedule();
  }

  // ============================================================
  // Sync Methods
  // ============================================================

  /// Triggers an immediate sync of pending locations.
  static Future<bool> sync() {
    return LocusSync.sync();
  }

  /// Destroys all stored locations.
  static Future<bool> destroyLocations() {
    return LocusSync.destroyLocations();
  }

  // ============================================================
  // Headless/Background Task Methods
  // ============================================================

  /// Registers a headless task callback.
  static Future<bool> registerHeadlessTask(HeadlessEventCallback callback) {
    return LocusHeadless.registerHeadlessTask(callback);
  }

  /// Starts a background task and returns its ID.
  static Future<int> startBackgroundTask() {
    return LocusHeadless.startBackgroundTask();
  }

  /// Stops a background task by ID.
  static Future<void> stopBackgroundTask(int taskId) {
    return LocusHeadless.stopBackgroundTask(taskId);
  }

  // ============================================================
  // Logging Methods
  // ============================================================

  /// Gets the log contents.
  static Future<String> getLog() async {
    final result = await LocusChannels.methods.invokeMethod('getLog');
    return result as String? ?? '';
  }

  /// Emails the log to the given address.
  static Future<void> emailLog(String email) async {
    await LocusChannels.methods.invokeMethod('emailLog', email);
  }

  /// Plays a system sound.
  static Future<void> playSound(String name) async {
    await LocusChannels.methods.invokeMethod('playSound', name);
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
    return LocusSync.enqueue(payload,
        type: type, idempotencyKey: idempotencyKey);
  }

  /// Returns queued payloads.
  static Future<List<QueueItem>> getQueue({int? limit}) {
    return LocusSync.getQueue(limit: limit);
  }

  /// Clears all queued payloads.
  static Future<void> clearQueue() {
    return LocusSync.clearQueue();
  }

  /// Attempts to sync queued payloads immediately.
  static Future<int> syncQueue({int? limit}) {
    return LocusSync.syncQueue(limit: limit);
  }

  // ============================================================
  // Permissions
  // ============================================================

  /// Requests all required permissions.
  static Future<bool> requestPermission() {
    return LocusLocation.requestPermission();
  }

  // ============================================================
  // State-Agnostic Streams
  // ============================================================

  /// Stream of location updates.
  static Stream<Location> get locationStream {
    return events
        .where((event) => event.type == EventType.location)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  /// Stream of motion change events (moving/stationary transitions).
  static Stream<Location> get motionChangeStream {
    return events
        .where((event) => event.type == EventType.motionChange)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  /// Stream of activity recognition updates.
  static Stream<Activity> get activityStream {
    return events
        .where((event) => event.type == EventType.activityChange)
        .map((event) {
      final data = event.data;
      if (data is Activity) return data;
      if (data is Location && data.activity != null) return data.activity!;
      if (data is Map) {
        return Activity.fromMap(Map<String, dynamic>.from(data));
      }
      return const Activity(type: ActivityType.unknown, confidence: 0);
    });
  }

  /// Stream of geofence crossing events.
  static Stream<GeofenceEvent> get geofenceStream {
    return events
        .where((event) => event.type == EventType.geofence)
        .map((event) => event.data)
        .where((data) => data is GeofenceEvent)
        .cast<GeofenceEvent>();
  }

  /// Stream of provider state changes.
  static Stream<ProviderChangeEvent> get providerStream {
    return events
        .where((event) => event.type == EventType.providerChange)
        .map((event) => event.data)
        .where((data) => data is ProviderChangeEvent)
        .cast<ProviderChangeEvent>();
  }

  /// Stream of connectivity changes.
  static Stream<ConnectivityChangeEvent> get connectivityStream {
    return events
        .where((event) => event.type == EventType.connectivityChange)
        .map((event) => event.data)
        .where((data) => data is ConnectivityChangeEvent)
        .cast<ConnectivityChangeEvent>();
  }

  /// Stream of heartbeat events.
  static Stream<Location> get heartbeatStream {
    return events
        .where((event) => event.type == EventType.heartbeat)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  /// Stream of HTTP sync events.
  static Stream<HttpEvent> get httpStream {
    return events
        .where((event) => event.type == EventType.http)
        .cast<GeolocationEvent<HttpEvent>>()
        .map((event) => event.data);
  }

  /// Stream of enabled state changes.
  static Stream<bool> get enabledStream {
    return events
        .where((event) => event.type == EventType.enabledChange)
        .map((event) => event.data == true);
  }

  /// Stream of power save mode changes.
  static Stream<bool> get powerSaveStream {
    return events
        .where((event) => event.type == EventType.powerSaveChange)
        .map((event) => event.data)
        .where((data) => data is bool)
        .cast<bool>();
  }

  // ============================================================
  // Dynamic Headers
  // ============================================================

  /// Sets a callback to provide dynamic HTTP headers.
  static void setHeadersCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _headersCallback = callback;
    _updateDynamicHeaders();
  }

  static Future<Map<String, String>> Function()? _headersCallback;

  /// Clears the dynamic headers callback.
  static void clearHeadersCallback() {
    _headersCallback = null;
  }

  static Future<void> _updateDynamicHeaders() async {
    if (_headersCallback == null) return;
    try {
      final headers = await _headersCallback!();
      await LocusChannels.methods.invokeMethod('setDynamicHeaders', headers);
    } catch (e) {
      // debugPrint('Failed to update dynamic headers: $e');
    }
  }

  /// Manually triggers a header update.
  static Future<void> refreshHeaders() async {
    await _updateDynamicHeaders();
  }

  // ============================================================
  // Typed Event Subscriptions
  // ============================================================

  static StreamSubscription<Location> onLocation(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return locationStream.listen(callback, onError: onError);
  }

  static StreamSubscription<Location> onMotionChange(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return motionChangeStream.listen(callback, onError: onError);
  }

  static StreamSubscription<Activity> onActivityChange(
    void Function(Activity) callback, {
    Function? onError,
  }) {
    return activityStream.listen(callback, onError: onError);
  }

  static StreamSubscription<ProviderChangeEvent> onProviderChange(
    void Function(ProviderChangeEvent) callback, {
    Function? onError,
  }) {
    return providerStream.listen(callback, onError: onError);
  }

  static StreamSubscription<GeofenceEvent> onGeofence(
    void Function(GeofenceEvent) callback, {
    Function? onError,
  }) {
    return geofenceStream.listen(callback, onError: onError);
  }

  static StreamSubscription<dynamic> onGeofencesChange(
    void Function(dynamic) callback, {
    Function? onError,
  }) {
    return events
        .where((event) => event.type == EventType.geofencesChange)
        .map((event) => event.data)
        .listen(callback, onError: onError);
  }

  static StreamSubscription<Location> onHeartbeat(
    void Function(Location) callback, {
    Function? onError,
  }) {
    return heartbeatStream.listen(callback, onError: onError);
  }

  static StreamSubscription<Location> onSchedule(
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

  static StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  }) {
    return connectivityStream.listen(callback, onError: onError);
  }

  static StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return powerSaveStream.listen(callback, onError: onError);
  }

  static StreamSubscription<bool> onEnabledChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return enabledStream.listen(callback, onError: onError);
  }

  static StreamSubscription<String> onNotificationAction(
    void Function(String) callback, {
    Function? onError,
  }) {
    return events
        .where((event) => event.type == EventType.notificationAction)
        .map((event) => event.data?.toString() ?? '')
        .listen(callback, onError: onError);
  }

  static StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  }) {
    return httpStream.listen(callback, onError: onError);
  }

  // ============================================================
  // Trip Lifecycle
  // ============================================================

  static Future<void> startTrip(TripConfig config) =>
      LocusTrip.startTrip(config);

  static TripSummary? stopTrip() => LocusTrip.stopTrip();

  static TripState? getTripState() => LocusTrip.getTripState();

  static Stream<TripEvent> get tripEvents => LocusTrip.tripEvents;

  static StreamSubscription<TripEvent> onTripEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return tripEvents.listen(callback, onError: onError);
  }

  // ============================================================
  // Adaptive Tracking Profiles
  // ============================================================

  static TrackingProfile? get currentTrackingProfile =>
      LocusProfiles.currentTrackingProfile;

  static Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  }) =>
      LocusProfiles.setTrackingProfiles(
        profiles,
        initialProfile: initialProfile,
        rules: rules,
        enableAutomation: enableAutomation,
      );

  static Future<void> setTrackingProfile(TrackingProfile profile) =>
      LocusProfiles.setTrackingProfile(profile);

  static void startTrackingAutomation() =>
      LocusProfiles.startTrackingAutomation();

  static void stopTrackingAutomation() =>
      LocusProfiles.stopTrackingAutomation();

  static void clearTrackingProfiles() => LocusProfiles.clearTrackingProfiles();

  // ============================================================
  // Geofence Workflows
  // ============================================================

  static Stream<GeofenceWorkflowEvent> get workflowEvents =>
      LocusWorkflows.workflowEvents;

  static StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent event) callback, {
    Function? onError,
  }) {
    return workflowEvents.listen(callback, onError: onError);
  }

  static void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) =>
      LocusWorkflows.registerGeofenceWorkflows(workflows);

  static GeofenceWorkflowState? getWorkflowState(String workflowId) =>
      LocusWorkflows.getWorkflowState(workflowId);

  static void clearGeofenceWorkflows() =>
      LocusWorkflows.clearGeofenceWorkflows();

  static void stopGeofenceWorkflows() => LocusWorkflows.stopGeofenceWorkflows();

  // ============================================================
  // Battery Optimization
  // ============================================================

  static Future<BatteryStats> getBatteryStats() =>
      LocusBattery.getBatteryStats();

  static Future<PowerState> getPowerState() => LocusBattery.getPowerState();

  static Stream<PowerStateChangeEvent> get powerStateStream =>
      LocusBattery.powerStateStream;

  static StreamSubscription<PowerStateChangeEvent> onPowerStateChangeWithObj(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  }) {
    return LocusBattery.powerStateStream.listen(callback, onError: onError);
  }

  static Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) =>
      LocusAdaptive.setAdaptiveTracking(config);

  static AdaptiveTrackingConfig? get adaptiveTrackingConfig =>
      LocusAdaptive.adaptiveTrackingConfig;

  /// Calculates optimal settings based on current conditions.
  static Future<AdaptiveSettings> calculateAdaptiveSettings() =>
      LocusAdaptive.calculateAdaptiveSettings();

  // ============================================================
  // Advanced Features
  // ============================================================

  static Future<void> setSpoofDetection(SpoofDetectionConfig config) =>
      LocusFeatures.setSpoofDetection(config);

  static SpoofDetectionConfig? get spoofDetectionConfig =>
      LocusFeatures.spoofDetectionConfig;

  static SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) =>
      LocusFeatures.analyzeForSpoofing(location,
          isMockProvider: isMockProvider);

  static Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]) =>
      LocusFeatures.startSignificantChangeMonitoring(config);

  static Future<void> stopSignificantChangeMonitoring() =>
      LocusFeatures.stopSignificantChangeMonitoring();

  static bool get isSignificantChangeMonitoringActive =>
      LocusFeatures.isSignificantChangeMonitoringActive;

  static Stream<SignificantChangeEvent>? get significantChangeStream =>
      LocusFeatures.significantChangeStream;

  static void setErrorHandler(ErrorRecoveryConfig config) =>
      LocusFeatures.setErrorHandler(config);

  static ErrorRecoveryManager? get errorRecoveryManager =>
      LocusFeatures.errorRecoveryManager;

  static Stream<LocusError>? get errorStream => LocusFeatures.errorStream;

  static Future<RecoveryAction> handleError(LocusError error) =>
      LocusFeatures.handleError(error);

  static Future<bool> isTracking() => LocusLifecycle.isTracking();

  static bool get isForeground => LocusLifecycle.isForeground;

  static void startLifecycleObserving() =>
      LocusLifecycle.startLifecycleObserving();

  static void stopLifecycleObserving() =>
      LocusLifecycle.stopLifecycleObserving();

  static Future<bool> isInActiveGeofence() =>
      LocusLifecycle.isInActiveGeofence();

  // ============================================================
  // Diagnostics
  // ============================================================

  static Future<DiagnosticsSnapshot> getDiagnostics() =>
      LocusDiagnostics.getDiagnostics();

  static Future<bool> applyRemoteCommand(RemoteCommand command) =>
      LocusDiagnostics.applyRemoteCommand(command);

  /// Stream of detected location anomalies.
  static Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  }) {
    final source = events
        .where((event) =>
            event.type == EventType.location ||
            event.type == EventType.motionChange ||
            event.type == EventType.heartbeat ||
            event.type == EventType.schedule)
        .map((event) => event.data as Location);
    return LocationAnomalyDetector.watch(source, config: config);
  }

  static StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
    Function? onError,
  }) {
    return locationAnomalies(config: config).listen(callback, onError: onError);
  }

  /// Stream of location quality assessments.
  static Stream<LocationQuality> locationQuality({
    LocationQualityConfig config = const LocationQualityConfig(),
  }) {
    final source = events
        .where((event) =>
            event.type == EventType.location ||
            event.type == EventType.motionChange ||
            event.type == EventType.heartbeat ||
            event.type == EventType.schedule)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
    return LocationQualityAnalyzer.analyze(source, config: config);
  }

  static StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  }) {
    return locationQuality(config: config).listen(callback, onError: onError);
  }

  // ============================================================
  // Benchmark
  // ============================================================

  static BatteryBenchmark? _activeBenchmark;

  static Future<void> startBatteryBenchmark() async {
    final power = await getPowerState();
    _activeBenchmark = BatteryBenchmark();
    _activeBenchmark!.start(initialBattery: power.batteryLevel);
  }

  static Future<BenchmarkResult?> stopBatteryBenchmark() async {
    if (_activeBenchmark == null || !_activeBenchmark!.isRunning) {
      return null;
    }
    final power = await getPowerState();
    final result = _activeBenchmark!.finish(
      currentBattery: power.batteryLevel,
    );
    _activeBenchmark = null;
    return result;
  }

  static void recordBenchmarkLocationUpdate({double? accuracy}) {
    _activeBenchmark?.recordLocationUpdate(accuracy: accuracy);
  }

  static void recordBenchmarkSync() {
    _activeBenchmark?.recordSync();
  }

  // ============================================================
  // Sync Policy
  // ============================================================

  static Future<void> setSyncPolicy(SyncPolicy policy) async {
    await LocusChannels.methods.invokeMethod('setSyncPolicy', policy.toMap());
  }

  static Future<SyncDecision> evaluateSyncPolicy({
    required SyncPolicy policy,
  }) async {
    final power = await getPowerState();
    final behavior = policy.getBehavior(
      networkType: await _getNetworkType(),
      batteryPercent: power.batteryLevel,
      isCharging: power.isCharging,
      isMetered: await _isMeteredConnection(),
      isForeground: isForeground,
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

  static Future<NetworkType> _getNetworkType() async {
    final result = await LocusChannels.methods.invokeMethod('getNetworkType');
    if (result is String) {
      return NetworkType.values.firstWhere(
        (e) => e.name == result,
        orElse: () => NetworkType.none,
      );
    }
    return NetworkType.none;
  }

  static Future<bool> _isMeteredConnection() async {
    final result =
        await LocusChannels.methods.invokeMethod('isMeteredConnection');
    return result == true;
  }
}
