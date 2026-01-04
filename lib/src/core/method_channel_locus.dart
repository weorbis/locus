import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:locus/src/config/config.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_config.dart';
import 'package:locus/src/core/locus_features.dart';
import 'package:locus/src/core/locus_headless.dart' show LocusHeadless;
import 'package:locus/src/core/locus_lifecycle.dart';
import 'package:locus/src/core/locus_scheduler.dart';
import 'package:locus/src/core/locus_streams.dart';
import 'package:locus/src/core/locus_interface.dart';

/// Method-channel backed implementation of [LocusInterface].
class MethodChannelLocus implements LocusInterface {
  /// Creates a new MethodChannelLocus instance.
  /// 
  /// Automatically registers polygon geofence and privacy zone services
  /// with the event stream for location processing.
  MethodChannelLocus() {
    // Register services with LocusStreams for event processing
    LocusStreams.setPolygonGeofenceService(_polygonGeofenceService);
    LocusStreams.setPrivacyZoneService(_privacyZoneService);
  }

  // ============================================================
  // Event Stream
  // ============================================================
  @override
  Stream<GeolocationEvent<dynamic>> get events => LocusStreams.events;

  // ============================================================
  // Lifecycle Methods
  // ============================================================
  @override
  Future<GeolocationState> ready(
    Config config, {
    bool skipValidation = false,
  }) {
    return LocusLifecycle.ready(config, skipValidation: skipValidation);
  }

  @override
  Future<GeolocationState> start() => LocusLifecycle.start();

  @override
  Future<GeolocationState> stop() => LocusLifecycle.stop();

  @override
  Future<GeolocationState> getState() => LocusLifecycle.getState();

  // ============================================================
  // Location Methods
  // ============================================================
  @override
  Future<Location> getCurrentPosition({
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

  @override
  Future<List<Location>> getLocations({int? limit}) {
    return LocusLocation.getLocations(limit: limit);
  }

  @override
  Future<List<Location>> queryLocations(LocationQuery query) {
    return LocusLocation.queryLocations(query);
  }

  @override
  Future<LocationSummary> getLocationSummary({
    DateTime? date,
    LocationQuery? query,
  }) {
    return LocusLocation.getLocationSummary(date: date, query: query);
  }

  @override
  Future<bool> changePace(bool isMoving) {
    return LocusLocation.changePace(isMoving);
  }

  @override
  Future<double> setOdometer(double value) {
    return LocusLocation.setOdometer(value);
  }

  // ============================================================
  // Geofencing Methods
  // ============================================================
  @override
  Future<bool> addGeofence(Geofence geofence) {
    return LocusGeofencing.addGeofence(geofence);
  }

  @override
  Future<bool> addGeofences(List<Geofence> geofences) {
    return LocusGeofencing.addGeofences(geofences);
  }

  @override
  Future<bool> removeGeofence(String identifier) {
    return LocusGeofencing.removeGeofence(identifier);
  }

  @override
  Future<bool> removeGeofences() {
    return LocusGeofencing.removeGeofences();
  }

  @override
  Future<List<Geofence>> getGeofences() {
    return LocusGeofencing.getGeofences();
  }

  @override
  Future<Geofence?> getGeofence(String identifier) {
    return LocusGeofencing.getGeofence(identifier);
  }

  @override
  Future<bool> geofenceExists(String identifier) {
    return LocusGeofencing.geofenceExists(identifier);
  }

  @override
  Future<bool> startGeofences() {
    return LocusGeofencing.startGeofences();
  }

  // ============================================================
  // Polygon Geofencing Methods
  // ============================================================
  /// Polygon geofence service instance.
  final PolygonGeofenceService _polygonGeofenceService =
      PolygonGeofenceService();

  @override
  Future<bool> addPolygonGeofence(PolygonGeofence polygon) {
    return _polygonGeofenceService.addPolygonGeofence(polygon);
  }

  @override
  Future<int> addPolygonGeofences(List<PolygonGeofence> polygons) {
    return _polygonGeofenceService.addPolygonGeofences(polygons);
  }

  @override
  Future<bool> removePolygonGeofence(String identifier) {
    return _polygonGeofenceService.removePolygonGeofence(identifier);
  }

  @override
  Future<void> removeAllPolygonGeofences() {
    return _polygonGeofenceService.removeAllPolygonGeofences();
  }

  @override
  Future<List<PolygonGeofence>> getPolygonGeofences() async {
    return _polygonGeofenceService.polygons;
  }

  @override
  Future<PolygonGeofence?> getPolygonGeofence(String identifier) async {
    return _polygonGeofenceService.getPolygonGeofence(identifier);
  }

  @override
  Future<bool> polygonGeofenceExists(String identifier) async {
    return _polygonGeofenceService.polygonExists(identifier);
  }

  @override
  Stream<PolygonGeofenceEvent> get polygonGeofenceEvents =>
      _polygonGeofenceService.events;

  // ============================================================
  // Privacy Zone Methods
  // ============================================================
  /// Privacy zone service instance.
  final PrivacyZoneService _privacyZoneService = PrivacyZoneService();

  @override
  Future<void> addPrivacyZone(PrivacyZone zone) {
    return _privacyZoneService.addZone(zone);
  }

  @override
  Future<void> addPrivacyZones(List<PrivacyZone> zones) {
    return _privacyZoneService.addZones(zones);
  }

  @override
  Future<bool> removePrivacyZone(String identifier) {
    return _privacyZoneService.removeZone(identifier);
  }

  @override
  Future<void> removeAllPrivacyZones() {
    return _privacyZoneService.removeAllZones();
  }

  @override
  Future<PrivacyZone?> getPrivacyZone(String identifier) async {
    return _privacyZoneService.getZone(identifier);
  }

  @override
  Future<List<PrivacyZone>> getPrivacyZones() async {
    return _privacyZoneService.zones;
  }

  @override
  Future<bool> setPrivacyZoneEnabled(String identifier, bool enabled) {
    return _privacyZoneService.setZoneEnabled(identifier, enabled);
  }

  @override
  Stream<PrivacyZoneEvent> get privacyZoneEvents =>
      _privacyZoneService.zoneChanges;

  // ============================================================
  // Configuration Methods
  // ============================================================
  @override
  Future<void> setConfig(Config config) {
    return LocusConfig.setConfig(config);
  }

  @override
  Future<void> destroy() {
    return LocusLifecycle.destroy();
  }

  @override
  Future<void> reset(Config config) {
    return LocusConfig.reset(config);
  }

  // ============================================================
  // Scheduling Methods
  // ============================================================
  @override
  Future<bool> startSchedule() {
    return LocusScheduler.startSchedule();
  }

  @override
  Future<bool> stopSchedule() {
    return LocusScheduler.stopSchedule();
  }

  // ============================================================
  // Sync Methods
  // ============================================================
  @override
  Future<bool> sync() {
    return LocusSync.sync();
  }

  @override
  Future<bool> resumeSync() async {
    return LocusSync.resumeSync();
  }

  @override
  Future<bool> destroyLocations() {
    return LocusSync.destroyLocations();
  }

  // ============================================================
  // Sync Body Builder
  // ============================================================
  @override
  void setSyncBodyBuilder(SyncBodyBuilder? builder) {
    LocusSync.setSyncBodyBuilder(builder);
  }

  @override
  void clearSyncBodyBuilder() {
    LocusSync.clearSyncBodyBuilder();
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) {
    return LocusSync.registerHeadlessSyncBodyBuilder(builder);
  }

  // ============================================================
  // Headless/Background Task Methods
  // ============================================================
  @override
  Future<bool> registerHeadlessTask(HeadlessEventCallback callback) {
    return LocusHeadless.registerHeadlessTask(callback);
  }

  @override
  Future<int> startBackgroundTask() {
    return LocusHeadless.startBackgroundTask();
  }

  @override
  Future<void> stopBackgroundTask(int taskId) {
    return LocusHeadless.stopBackgroundTask(taskId);
  }

  // ============================================================
  // Logging Methods
  // ============================================================
  @override
  Future<List<LogEntry>> getLog() async {
    final result = await LocusChannels.methods.invokeMethod('getLog');
    if (result is List) {
      return result
          .map((entry) => LogEntry.fromMap(Map<String, dynamic>.from(entry)))
          .toList();
    }
    return [];
  }

  @override
  Future<void> emailLog(String email) async {
    await LocusChannels.methods.invokeMethod('emailLog', email);
  }

  @override
  Future<void> playSound(String name) async {
    await LocusChannels.methods.invokeMethod('playSound', name);
  }

  // ============================================================
  // Queue Methods
  // ============================================================
  @override
  Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) {
    return LocusSync.enqueue(payload,
        type: type, idempotencyKey: idempotencyKey);
  }

  @override
  Future<List<QueueItem>> getQueue({int? limit}) {
    return LocusSync.getQueue(limit: limit);
  }

  @override
  Future<void> clearQueue() {
    return LocusSync.clearQueue();
  }

  @override
  Future<int> syncQueue({int? limit}) {
    return LocusSync.syncQueue(limit: limit);
  }

  // ============================================================
  // Permissions
  // ============================================================
  @override
  Future<bool> requestPermission() {
    return LocusLocation.requestPermission();
  }

  // ============================================================
  // State-Agnostic Streams
  // ============================================================
  @override
  Stream<Location> get locationStream {
    return events
        .where((event) => event.type == EventType.location)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  @override
  Stream<Location> get motionChangeStream {
    return events
        .where((event) => event.type == EventType.motionChange)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  @override
  Stream<Activity> get activityStream {
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

  @override
  Stream<GeofenceEvent> get geofenceStream {
    return events
        .where((event) => event.type == EventType.geofence)
        .map((event) => event.data)
        .where((data) => data is GeofenceEvent)
        .cast<GeofenceEvent>();
  }

  @override
  Stream<ProviderChangeEvent> get providerStream {
    return events
        .where((event) => event.type == EventType.providerChange)
        .map((event) => event.data)
        .where((data) => data is ProviderChangeEvent)
        .cast<ProviderChangeEvent>();
  }

  @override
  Stream<ConnectivityChangeEvent> get connectivityStream {
    return events
        .where((event) => event.type == EventType.connectivityChange)
        .map((event) => event.data)
        .where((data) => data is ConnectivityChangeEvent)
        .cast<ConnectivityChangeEvent>();
  }

  @override
  Stream<Location> get heartbeatStream {
    return events
        .where((event) => event.type == EventType.heartbeat)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  @override
  Stream<HttpEvent> get httpStream {
    return events
        .where((event) => event.type == EventType.http)
        .cast<GeolocationEvent<HttpEvent>>()
        .map((event) => event.data);
  }

  @override
  Stream<bool> get enabledStream {
    return events
        .where((event) => event.type == EventType.enabledChange)
        .map((event) => event.data == true);
  }

  @override
  Stream<bool> get powerSaveStream {
    return events
        .where((event) => event.type == EventType.powerSaveChange)
        .map((event) => event.data)
        .where((data) => data is bool)
        .cast<bool>();
  }

  // ============================================================
  // Dynamic Headers
  // ============================================================
  Future<Map<String, String>> Function()? _headersCallback;

  @override
  void setHeadersCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _headersCallback = callback;
    _updateDynamicHeaders();
  }

  @override
  void clearHeadersCallback() {
    _headersCallback = null;
  }

  Future<void> _updateDynamicHeaders() async {
    if (_headersCallback == null) {
      debugPrint(
          '[Locus] refreshHeaders called but no headersCallback is set. Use setHeadersCallback() first.');
      return;
    }
    try {
      final headers = await _headersCallback!();
      await LocusChannels.methods.invokeMethod('setDynamicHeaders', headers);
    } catch (e) {
      debugPrint('[Locus] Error refreshing headers: $e');
    }
  }

  @override
  Future<void> refreshHeaders() async {
    await _updateDynamicHeaders();
  }

  // ============================================================
  // Typed Event Subscriptions
  // ============================================================
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

  // ============================================================
  // Trip Lifecycle
  // ============================================================
  @override
  Future<void> startTrip(TripConfig config) => LocusTrip.startTrip(config);

  @override
  TripSummary? stopTrip() => LocusTrip.stopTrip();

  @override
  TripState? getTripState() => LocusTrip.getTripState();

  @override
  Stream<TripEvent> get tripEvents => LocusTrip.tripEvents;

  @override
  StreamSubscription<TripEvent> onTripEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return tripEvents.listen(callback, onError: onError);
  }

  // ============================================================
  // Tracking Profiles
  // ============================================================
  @override
  TrackingProfile? get currentTrackingProfile =>
      LocusProfiles.currentTrackingProfile;

  @override
  Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  }) {
    return LocusProfiles.setTrackingProfiles(
      profiles,
      initialProfile: initialProfile,
      rules: rules,
      enableAutomation: enableAutomation,
    );
  }

  @override
  Future<void> setTrackingProfile(TrackingProfile profile) =>
      LocusProfiles.setTrackingProfile(profile);

  @override
  void startTrackingAutomation() => LocusProfiles.startTrackingAutomation();

  @override
  void stopTrackingAutomation() => LocusProfiles.stopTrackingAutomation();

  @override
  void clearTrackingProfiles() => LocusProfiles.clearTrackingProfiles();

  // ============================================================
  // Geofence Workflows
  // ============================================================
  @override
  Stream<GeofenceWorkflowEvent> get workflowEvents =>
      LocusWorkflows.workflowEvents;

  @override
  StreamSubscription<GeofenceWorkflowEvent> onWorkflowEvent(
    void Function(GeofenceWorkflowEvent event) callback, {
    Function? onError,
  }) {
    return workflowEvents.listen(callback, onError: onError);
  }

  @override
  void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) =>
      LocusWorkflows.registerGeofenceWorkflows(workflows);

  @override
  GeofenceWorkflowState? getWorkflowState(String workflowId) =>
      LocusWorkflows.getWorkflowState(workflowId);

  @override
  void clearGeofenceWorkflows() => LocusWorkflows.clearGeofenceWorkflows();

  @override
  void stopGeofenceWorkflows() => LocusWorkflows.stopGeofenceWorkflows();

  // ============================================================
  // Battery Optimization
  // ============================================================
  @override
  Future<BatteryStats> getBatteryStats() => LocusBattery.getBatteryStats();

  @override
  Future<PowerState> getPowerState() => LocusBattery.getPowerState();

  @override
  Future<BatteryRunway> estimateBatteryRunway() =>
      LocusBattery.estimateBatteryRunway();

  @override
  Stream<PowerStateChangeEvent> get powerStateStream =>
      LocusBattery.powerStateStream;

  @override
  StreamSubscription<PowerStateChangeEvent> onPowerStateChangeWithObj(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  }) {
    return LocusBattery.powerStateStream.listen(callback, onError: onError);
  }

  @override
  Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) =>
      LocusAdaptive.setAdaptiveTracking(config);

  @override
  AdaptiveTrackingConfig? get adaptiveTrackingConfig =>
      LocusAdaptive.adaptiveTrackingConfig;

  @override
  Future<AdaptiveSettings> calculateAdaptiveSettings() =>
      LocusAdaptive.calculateAdaptiveSettings();

  // ============================================================
  // Advanced Features
  // ============================================================
  @override
  Future<void> setSpoofDetection(SpoofDetectionConfig config) =>
      LocusFeatures.setSpoofDetection(config);

  @override
  SpoofDetectionConfig? get spoofDetectionConfig =>
      LocusFeatures.spoofDetectionConfig;

  @override
  SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) =>
      LocusFeatures.analyzeForSpoofing(location,
          isMockProvider: isMockProvider);

  @override
  Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]) =>
      LocusFeatures.startSignificantChangeMonitoring(config);

  @override
  Future<void> stopSignificantChangeMonitoring() =>
      LocusFeatures.stopSignificantChangeMonitoring();

  @override
  bool get isSignificantChangeMonitoringActive =>
      LocusFeatures.isSignificantChangeMonitoringActive;

  @override
  Stream<SignificantChangeEvent>? get significantChangeStream =>
      LocusFeatures.significantChangeStream;

  @override
  void setErrorHandler(ErrorRecoveryConfig config) =>
      LocusFeatures.setErrorHandler(config);

  @override
  ErrorRecoveryManager? get errorRecoveryManager =>
      LocusFeatures.errorRecoveryManager;

  @override
  Stream<LocusError>? get errorStream => LocusFeatures.errorStream;

  @override
  Future<RecoveryAction> handleError(LocusError error) =>
      LocusFeatures.handleError(error);

  @override
  Future<bool> isTracking() => LocusLifecycle.isTracking();

  @override
  bool get isForeground => LocusLifecycle.isForeground;

  @override
  void startLifecycleObserving() => LocusLifecycle.startLifecycleObserving();

  @override
  void stopLifecycleObserving() => LocusLifecycle.stopLifecycleObserving();

  @override
  Future<bool> isInActiveGeofence() => LocusLifecycle.isInActiveGeofence();

  // ============================================================
  // Diagnostics
  // ============================================================
  @override
  Future<DiagnosticsSnapshot> getDiagnostics() =>
      LocusDiagnostics.getDiagnostics();

  @override
  Future<bool> applyRemoteCommand(RemoteCommand command) =>
      LocusDiagnostics.applyRemoteCommand(command);

  @override
  Stream<LocationAnomaly> locationAnomalies({
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

  @override
  StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  }) {
    return locationQuality(config: config).listen(callback, onError: onError);
  }

  // ============================================================
  // Benchmark
  // ============================================================
  BatteryBenchmark? _activeBenchmark;

  @override
  Future<void> startBatteryBenchmark() async {
    final power = await getPowerState();
    _activeBenchmark = BatteryBenchmark();
    _activeBenchmark!.start(initialBattery: power.batteryLevel);
  }

  @override
  Future<BenchmarkResult?> stopBatteryBenchmark() async {
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

  @override
  void recordBenchmarkLocationUpdate({double? accuracy}) {
    _activeBenchmark?.recordLocationUpdate(accuracy: accuracy);
  }

  @override
  void recordBenchmarkSync() {
    _activeBenchmark?.recordSync();
  }

  // ============================================================
  // Sync Policy
  // ============================================================
  @override
  Future<void> setSyncPolicy(SyncPolicy policy) async {
    await LocusChannels.methods.invokeMethod('setSyncPolicy', policy.toMap());
  }

  @override
  Future<SyncDecision> evaluateSyncPolicy({
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

  Future<NetworkType> _getNetworkType() async {
    final result = await LocusChannels.methods.invokeMethod('getNetworkType');
    if (result is String) {
      return NetworkType.values.firstWhere(
        (e) => e.name == result,
        orElse: () => NetworkType.none,
      );
    }
    return NetworkType.none;
  }

  Future<bool> _isMeteredConnection() async {
    final result =
        await LocusChannels.methods.invokeMethod('isMeteredConnection');
    return result == true;
  }
}
