import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:locus/locus.dart';

void main() => runApp(const LocusExampleApp());

// =============================================================================
// App Entry Point
// =============================================================================

class LocusExampleApp extends StatefulWidget {
  const LocusExampleApp({super.key});

  @override
  State<LocusExampleApp> createState() => _LocusExampleAppState();
}

class _LocusExampleAppState extends State<LocusExampleApp> {
  static const int _maxEventEntries = 250;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Stream subscriptions
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // State
  final List<String> _events = [];
  final Map<String, int> _eventCounts = {};
  Location? _latestLocation;
  Activity? _lastActivity;

  ConnectivityChangeEvent? _lastConnectivity;

  GeolocationState? _lastState;

  List<LogEntry>? _lastLog;

  PowerState? _powerState;
  BatteryStats? _batteryStats;
  BatteryRunway? _batteryRunway;
  AdaptiveSettings? _adaptiveSettings;
  AdaptiveTrackingConfig? _adaptiveTrackingConfig;
  PowerStateChangeEvent? _lastPowerEvent;
  List<Location> _storedLocations = [];
  LocationSummary? _locationSummary;
  List<QueueItem> _syncQueue = [];
  DiagnosticsSnapshot? _diagnostics;
  List<PolygonGeofence> _polygonGeofences = [];
  List<PrivacyZone> _privacyZones = [];
  GeofenceWorkflowEvent? _lastWorkflowEvent;
  LocationQuality? _lastQuality;
  LocationAnomaly? _lastAnomaly;
  StreamSubscription<LocationQuality>? _qualitySubscription;
  StreamSubscription<LocationAnomaly>? _anomalySubscription;

  // Toggles
  bool _isRunning = false;
  bool _isReady = false;

  bool _spoofDetectionEnabled = false;
  bool _significantChangesEnabled = false;
  bool _isSyncPaused = false;
  bool _automationEnabled = false;
  bool _qualityMonitoringEnabled = false;
  bool _anomalyMonitoringEnabled = false;
  bool _workflowRegistered = false;
  String? _benchmarkStatus;
  TrackingProfile? _currentProfile;
  SyncPolicy _syncPolicy = SyncPolicy.balanced;
  SyncDecision? _syncDecision;
  String? _lastQueueId;
  String _activeScenario = 'None';
  Map<String, dynamic> _syncContext = const {
    'shift_id': 'shift-001',
    'driver_id': 'driver-42',
    'route_id': 'route-7',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_configure());
  }

  @override
  void dispose() {
    unawaited(_qualitySubscription?.cancel());
    unawaited(_anomalySubscription?.cancel());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  // ===========================================================================
  // Configuration
  // ===========================================================================

  Future<void> _configure() async {
    final isGranted = await Locus.requestPermission();
    if (!isGranted) {
      _showSnackbar('Location permission required', isSuccess: false);
      return;
    }

    final config = Config(
      stationaryRadius: 25,
      motionTriggerDelay: 15000,
      activityRecognitionInterval: 10000,
      startOnBoot: true,
      stopOnTerminate: false,
      enableHeadless: true,
      autoSync: true,
      batchSync: true,
      maxBatchSize: 5,
      autoSyncThreshold: 1,
      queueMaxDays: 7,
      queueMaxRecords: 500,
      persistMode: PersistMode.location,
      maxDaysToPersist: 7,
      maxRecordsToPersist: 200,
      maxMonitoredGeofences: 20,
      url: 'https://example.com/locations',
      extras: _syncContext,
      adaptiveTracking: AdaptiveTrackingConfig.balanced,
      logLevel: LogLevel.info,
      notification: const NotificationConfig(
        title: 'Locus Example',
        text: 'Tracking location in background',
      ),
    );

    await Locus.ready(config);
    await _configureProfiles();
    _setupListeners();
    await _refreshState();
    await Locus.dataSync.setPolicy(_syncPolicy);
    await Locus.battery.setAdaptiveTracking(AdaptiveTrackingConfig.balanced);

    // Demo: Custom sync body builder
    await Locus.setSyncBodyBuilder((locations, extras) async {
      return {
        'app': 'locus_example',
        'timestamp': DateTime.now().toIso8601String(),
        'locations': locations.map((l) => l.toMap()).toList(),
        ...extras,
      };
    });
    Locus.dataSync.setHeadersCallback(() async {
      return {
        'X-Client': 'locus_example',
        'X-Shift-Id': _syncContext['shift_id']?.toString() ?? 'unknown',
      };
    });
    Locus.dataSync.setPreSyncValidator((locations, extras) async {
      final hasShift = extras['shift_id'] != null;
      if (!hasShift) {
        _recordEvent('sync', 'Sync skipped (missing shift_id)');
      }
      return hasShift;
    });

    setState(() {
      _isReady = true;
      _adaptiveTrackingConfig = AdaptiveTrackingConfig.balanced;
    });
  }

  Future<void> _configureProfiles({bool enableAutomation = false}) async {
    final rules = enableAutomation
        ? [
            const TrackingProfileRule(
              profile: TrackingProfile.enRoute,
              type: TrackingProfileRuleType.activity,
              activity: ActivityType.inVehicle,
              cooldownSeconds: 60,
            ),
            const TrackingProfileRule(
              profile: TrackingProfile.standby,
              type: TrackingProfileRuleType.activity,
              activity: ActivityType.still,
              cooldownSeconds: 60,
            ),
            const TrackingProfileRule(
              profile: TrackingProfile.arrived,
              type: TrackingProfileRuleType.geofence,
              geofenceAction: GeofenceAction.enter,
              geofenceIdentifier: 'delivery_dropoff',
              cooldownSeconds: 120,
            ),
          ]
        : const <TrackingProfileRule>[];
    await Locus.setTrackingProfiles({
      TrackingProfile.offDuty: ConfigPresets.lowPower,
      TrackingProfile.standby: ConfigPresets.balanced,
      TrackingProfile.enRoute: ConfigPresets.tracking,
      TrackingProfile.arrived: ConfigPresets.trail,
    },
        initialProfile: TrackingProfile.standby,
        rules: rules,
        enableAutomation: enableAutomation);
    setState(() {
      _currentProfile = Locus.currentTrackingProfile;
      _automationEnabled = enableAutomation;
    });
  }

  void _setupListeners() {
    _subscriptions.addAll([
      Locus.location.stream.listen((loc) {
        _recordEvent('location', _formatLocation(loc));
        setState(() => _latestLocation = loc);
      }),
      Locus.location.motionChanges.listen((loc) {
        _recordEvent(
          'motion',
          'Motion: ${loc.isMoving == true ? "moving" : "stationary"}',
        );
        setState(() => _latestLocation = loc);
      }),
      Locus.location.heartbeats.listen((loc) {
        _recordEvent('heartbeat', 'Heartbeat: ${_formatLocation(loc)}');
      }),
      Locus.instance.activityStream.listen((activity) {
        _recordEvent(
          'activity',
          'Activity: ${activity.type.name} (${activity.confidence}%)',
        );
        setState(() => _lastActivity = activity);
      }),
      Locus.trips.events.listen((event) {
        _recordEvent('trip', 'Trip: ${event.type.name}');
      }),
      Locus.instance.providerStream.listen((event) {
        _recordEvent('provider', 'Provider: ${event.authorizationStatus.name}');
      }),
      Locus.geofencing.events.listen((event) {
        _recordEvent(
          'geofence',
          'Geofence: ${event.geofence.identifier} ${event.action.name}',
        );
      }),
      Locus.geofencing.polygonEvents.listen((event) {
        _recordEvent(
          'polygon',
          'Polygon: ${event.geofence.identifier} ${event.type.name}',
        );
      }),
      Locus.geofencing.workflowEvents.listen((event) {
        _recordEvent(
          'workflow',
          'Workflow: ${event.workflowId} ${event.status.name}',
        );
        setState(() => _lastWorkflowEvent = event);
      }),
      Locus.privacy.events.listen((event) {
        _recordEvent(
          'privacy',
          'Privacy: ${event.zone.identifier} ${event.type.name}',
        );
      }),
      Locus.dataSync.connectivityEvents.listen((event) {
        _recordEvent(
          'connectivity',
          'Network: ${event.connected ? "online" : "offline"}',
        );
        setState(() => _lastConnectivity = event);
      }),
      Locus.battery.powerStateEvents.listen((event) {
        _recordEvent(
          'power',
          'Power: ${event.changeType.name} ${event.current.batteryLevel}%',
        );
        setState(() => _lastPowerEvent = event);
      }),
      Locus.battery.powerSaveChanges.listen((enabled) {
        _recordEvent('power', 'Power save: ${enabled ? "ON" : "OFF"}');
      }),
      Locus.instance.enabledStream.listen((enabled) {
        _recordEvent('state', 'Tracking: ${enabled ? "started" : "stopped"}');
        setState(() => _isRunning = enabled);
      }),
      Locus.dataSync.events.listen((event) {
        _recordEvent(
          'http',
          'HTTP: ${event.status} ${event.ok ? "OK" : "FAILED"}',
        );
      }),
      Locus.instance.onNotificationAction((action) {
        _recordEvent('notification', 'Action: $action');
      }),
    ]);
  }

  // ===========================================================================
  // Actions
  // ===========================================================================

  Future<void> _refreshState() async {
    final state = await Locus.getState();
    _isSyncPaused = Locus.dataSync.isPaused;
    setState(() {
      _lastState = state;
      _isRunning = state.enabled;
    });
  }

  Future<void> _toggleTracking() async {
    if (!_isReady) {
      _showSnackbar('SDK not ready', isSuccess: false);
      return;
    }
    if (_isRunning) {
      await Locus.stop();
      _showSnackbar('Tracking stopped');
    } else {
      await Locus.start();
      _showSnackbar('Tracking started');
    }
    await _refreshState();
  }

  Future<void> _getPosition() async {
    try {
      final loc = await Locus.location.getCurrentPosition();
      setState(() => _latestLocation = loc);
      _showSnackbar(
        'Position: ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}',
      );
      _recordEvent('position', _formatLocation(loc));
    } catch (e) {
      _showSnackbar('Failed to get position', isSuccess: false);
    }
  }

  Future<void> _setProfile(TrackingProfile profile) async {
    await Locus.setTrackingProfile(profile);
    setState(() => _currentProfile = profile);
    _showSnackbar('Profile: ${profile.name}');
    _recordEvent('profile', 'Switched to ${profile.name}');
  }

  Future<void> _addGeofence() async {
    await Locus.geofencing.add(
      const Geofence(
        identifier: 'demo_geofence',
        radius: 100,
        latitude: 37.4219983,
        longitude: -122.084,
        notifyOnEntry: true,
        notifyOnExit: true,
      ),
    );
    final count = (await Locus.geofencing.getAll()).length;
    _showSnackbar('Geofence added ($count total)');
    _recordEvent('geofence', 'Added demo_geofence');
  }

  Future<void> _clearGeofences() async {
    final count = (await Locus.geofencing.getAll()).length;
    await Locus.geofencing.removeAll();
    _showSnackbar('Cleared $count geofence(s)');
    _recordEvent('geofence', 'Cleared all');
  }

  Future<void> _addPrivacyZone() async {
    await Locus.privacy.add(
      PrivacyZone.create(
        identifier: 'demo_zone',
        latitude: 37.4219983,
        longitude: -122.084,
        radius: 200,
        action: PrivacyZoneAction.obfuscate,
      ),
    );
    final zones = await Locus.privacy.getAll();
    setState(() => _privacyZones = zones);
    final count = zones.length;
    _showSnackbar('Privacy zone added ($count total)');
    _recordEvent('privacy', 'Added demo_zone');
  }

  Future<void> _startTrip() async {
    await Locus.trips.start(const TripConfig(startOnMoving: true));
    _showSnackbar('Trip started');
    _recordEvent('trip', 'Trip started');
  }

  Future<void> _stopTrip() async {
    final summary = await Locus.trips.stop();
    // setState(() => _lastTripSummary = summary);
    if (summary != null) {
      _showSnackbar('Trip: ${summary.distanceMeters.toStringAsFixed(0)}m');
    } else {
      _showSnackbar('Trip stopped');
    }
    _recordEvent('trip', 'Trip stopped');
  }

  Future<void> _syncNow() async {
    if (_isSyncPaused) {
      _showSnackbar('Sync is paused', isSuccess: false);
      return;
    }
    final result = await Locus.dataSync.now();
    _showSnackbar('Sync: $result');
    _recordEvent('sync', 'Manual sync: $result');
  }

  Future<void> _toggleSyncPause() async {
    if (_isSyncPaused) {
      await Locus.dataSync.resume();
      setState(() => _isSyncPaused = false);
      _showSnackbar('Sync resumed');
      _recordEvent('sync', 'Sync resumed');
    } else {
      await Locus.dataSync.pause();
      setState(() => _isSyncPaused = true);
      _showSnackbar('Sync paused');
      _recordEvent('sync', 'Sync paused');
    }
  }

  Future<void> _loadLocations() async {
    final locs = await Locus.location.getLocations(limit: 50);
    setState(() => _storedLocations = locs);
    _showSnackbar('Loaded ${locs.length} location(s)');
  }

  Future<void> _clearLocations() async {
    await Locus.location.destroyLocations();
    setState(() => _storedLocations = []);
    _showSnackbar('Locations cleared');
  }

  Future<void> _loadLogs() async {
    final logs = await Locus.getLog();
    setState(() => _lastLog = logs);
    _showSnackbar('Loaded ${logs.length} log entries');
  }

  Future<void> _refreshBattery() async {
    final state = await Locus.battery.getPowerState();
    final stats = await Locus.battery.getStats();
    setState(() {
      _powerState = state;
      _batteryStats = stats;
    });
    _showSnackbar('Battery: ${state.batteryLevel}%');
    _recordEvent(
      'battery',
      '${state.batteryLevel}%, GPS: ${(stats.gpsOnTimePercent * 100).toStringAsFixed(0)}%',
    );
  }

  Future<void> _toggleBenchmark() async {
    if (_benchmarkStatus == null) {
      await Locus.startBatteryBenchmark();
      setState(() => _benchmarkStatus = 'Running');
      _showSnackbar('Benchmark started');
    } else {
      await Locus.stopBatteryBenchmark();
      setState(() => _benchmarkStatus = null);
      _showSnackbar('Benchmark stopped');
    }
  }

  Future<void> _toggleSpoof() async {
    final enabled = !_spoofDetectionEnabled;
    await Locus.setSpoofDetection(
      enabled ? SpoofDetectionConfig.high : SpoofDetectionConfig.disabled,
    );
    setState(() => _spoofDetectionEnabled = enabled);
    _showSnackbar('Spoof detection: ${enabled ? "ON" : "OFF"}');
  }

  Future<void> _toggleSignificant() async {
    final enabled = !_significantChangesEnabled;
    if (enabled) {
      await Locus.startSignificantChangeMonitoring(
        SignificantChangeConfig.defaults,
      );
    } else {
      await Locus.stopSignificantChangeMonitoring();
    }
    setState(() => _significantChangesEnabled = enabled);
    _showSnackbar('Significant changes: ${enabled ? "ON" : "OFF"}');
  }

  Future<void> _toggleAutomation() async {
    final enabled = !_automationEnabled;
    await _configureProfiles(enableAutomation: enabled);
    _showSnackbar('Automation: ${enabled ? "ON" : "OFF"}');
    _recordEvent('profile', 'Automation ${enabled ? "enabled" : "disabled"}');
  }

  Future<void> _applySyncContext(Map<String, dynamic> context) async {
    await Locus.setConfig(Config(extras: context));
    await Locus.dataSync.refreshHeaders();
    setState(() => _syncContext = Map<String, dynamic>.from(context));
    _showSnackbar('Context: ${context['shift_id'] ?? 'updated'}');
    _recordEvent('config', 'Context updated');
  }

  Future<void> _applySyncPolicy(SyncPolicy policy, String label) async {
    await Locus.dataSync.setPolicy(policy);
    setState(() => _syncPolicy = policy);
    _showSnackbar('Sync policy: $label');
    _recordEvent('sync', 'Policy set: $label');
  }

  Future<void> _evaluateSyncPolicy() async {
    final decision = await Locus.dataSync.evaluatePolicy(policy: _syncPolicy);
    setState(() => _syncDecision = decision);
    _showSnackbar(decision.reason);
    _recordEvent('sync', 'Policy decision: ${decision.reason}');
  }

  Future<void> _enqueueCheckIn() async {
    final payload = {
      'type': 'check_in',
      'timestamp': DateTime.now().toIso8601String(),
      'context': _syncContext,
      if (_latestLocation != null) 'coords': _latestLocation!.coords.toMap(),
    };
    final id = await Locus.dataSync.enqueue(
      payload,
      type: 'check_in',
      idempotencyKey: 'check_in_${DateTime.now().millisecondsSinceEpoch}',
    );
    setState(() => _lastQueueId = id);
    _showSnackbar('Queued check-in');
    _recordEvent('queue', 'Enqueued check-in: $id');
  }

  Future<void> _loadSyncQueue() async {
    final items = await Locus.dataSync.getQueue(limit: 20);
    setState(() => _syncQueue = items);
    _showSnackbar('Queue: ${items.length} item(s)');
  }

  Future<void> _syncQueueNow() async {
    final count = await Locus.dataSync.syncQueue(limit: 20);
    _showSnackbar('Synced $count queued item(s)');
    _recordEvent('sync', 'Queue sync: $count');
    await _loadSyncQueue();
  }

  Future<void> _clearSyncQueue() async {
    await Locus.dataSync.clearQueue();
    setState(() => _syncQueue = []);
    _showSnackbar('Queue cleared');
    _recordEvent('queue', 'Queue cleared');
  }

  Future<void> _addPolygonGeofence() async {
    final polygon = PolygonGeofence(
      identifier: 'campus_zone',
      vertices: [
        const GeoPoint(latitude: 37.4232, longitude: -122.0852),
        const GeoPoint(latitude: 37.4232, longitude: -122.0824),
        const GeoPoint(latitude: 37.4210, longitude: -122.0824),
        const GeoPoint(latitude: 37.4210, longitude: -122.0852),
      ],
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: true,
      loiteringDelay: 10000,
      extras: {'name': 'Demo Campus'},
    );
    final added = await Locus.geofencing.addPolygon(polygon);
    final polygons = await Locus.geofencing.getAllPolygons();
    setState(() => _polygonGeofences = polygons);
    _showSnackbar(added ? 'Polygon added' : 'Polygon exists');
    _recordEvent('polygon', 'Polygons: ${polygons.length}');
  }

  Future<void> _clearPolygonGeofences() async {
    await Locus.geofencing.removeAllPolygons();
    setState(() => _polygonGeofences = []);
    _showSnackbar('Polygons cleared');
    _recordEvent('polygon', 'Cleared polygons');
  }

  Future<void> _registerDeliveryWorkflow() async {
    await Locus.geofencing.addAll(const [
      Geofence(
        identifier: 'delivery_pickup',
        radius: 120,
        latitude: 37.4228,
        longitude: -122.085,
        notifyOnEntry: true,
        notifyOnExit: false,
      ),
      Geofence(
        identifier: 'delivery_dropoff',
        radius: 120,
        latitude: 37.4187,
        longitude: -122.0816,
        notifyOnEntry: true,
        notifyOnExit: true,
      ),
    ]);
    const workflow = GeofenceWorkflow(
      id: 'delivery_flow',
      requireSequence: true,
      steps: [
        GeofenceWorkflowStep(
          id: 'pickup',
          geofenceIdentifier: 'delivery_pickup',
          action: GeofenceAction.enter,
          cooldownSeconds: 30,
        ),
        GeofenceWorkflowStep(
          id: 'dropoff',
          geofenceIdentifier: 'delivery_dropoff',
          action: GeofenceAction.enter,
          cooldownSeconds: 30,
        ),
      ],
    );
    Locus.geofencing.registerWorkflows([workflow]);
    setState(() => _workflowRegistered = true);
    _showSnackbar('Workflow registered');
    _recordEvent('workflow', 'Registered delivery workflow');
  }

  void _stopWorkflows() {
    Locus.geofencing.stopWorkflows();
    Locus.geofencing.clearWorkflows();
    setState(() => _workflowRegistered = false);
    _showSnackbar('Workflows cleared');
    _recordEvent('workflow', 'Workflows cleared');
  }

  Future<void> _loadPrivacyZones() async {
    final zones = await Locus.privacy.getAll();
    setState(() => _privacyZones = zones);
    _showSnackbar('Privacy zones: ${zones.length}');
  }

  Future<void> _clearPrivacyZones() async {
    await Locus.privacy.removeAll();
    setState(() => _privacyZones = []);
    _showSnackbar('Privacy zones cleared');
    _recordEvent('privacy', 'Cleared all zones');
  }

  Future<void> _loadLocationSummary() async {
    final summary = await Locus.location.getSummary(
      query: LocationQuery.lastHours(12, limit: 250),
    );
    setState(() => _locationSummary = summary);
    _showSnackbar('Summary: ${summary.locationCount} points');
  }

  Future<void> _loadDiagnostics() async {
    final snapshot = await Locus.getDiagnostics();
    setState(() => _diagnostics = snapshot);
    _showSnackbar('Diagnostics captured');
    _recordEvent('diagnostics', 'Diagnostics snapshot captured');
  }

  Future<void> _setAdaptiveTracking(
    AdaptiveTrackingConfig config,
    String label,
  ) async {
    await Locus.battery.setAdaptiveTracking(config);
    setState(() => _adaptiveTrackingConfig = config);
    _showSnackbar('Adaptive: $label');
    _recordEvent('battery', 'Adaptive tracking: $label');
  }

  Future<void> _calculateAdaptiveSettings() async {
    final settings = await Locus.battery.calculateAdaptiveSettings();
    setState(() => _adaptiveSettings = settings);
    _showSnackbar('Adaptive settings updated');
  }

  Future<void> _estimateRunway() async {
    final runway = await Locus.battery.estimateRunway();
    setState(() => _batteryRunway = runway);
    _showSnackbar(runway.recommendation);
  }

  Future<void> _toggleQualityMonitoring() async {
    if (_qualityMonitoringEnabled) {
      await _qualitySubscription?.cancel();
      setState(() {
        _qualityMonitoringEnabled = false;
        _lastQuality = null;
      });
      _showSnackbar('Quality monitoring stopped');
      return;
    }
    _qualitySubscription = Locus.locationQuality(
      config: const LocationQualityConfig(maxAccuracyMeters: 80, windowSize: 5),
    ).listen((quality) {
      setState(() => _lastQuality = quality);
      _recordEvent(
        'quality',
        'Quality: ${(quality.overallScore * 100).toStringAsFixed(0)}%',
      );
    });
    setState(() => _qualityMonitoringEnabled = true);
    _showSnackbar('Quality monitoring started');
  }

  Future<void> _toggleAnomalyMonitoring() async {
    if (_anomalyMonitoringEnabled) {
      await _anomalySubscription?.cancel();
      setState(() {
        _anomalyMonitoringEnabled = false;
        _lastAnomaly = null;
      });
      _showSnackbar('Anomaly monitoring stopped');
      return;
    }
    _anomalySubscription = Locus.locationAnomalies(
      config: const LocationAnomalyConfig(maxSpeedKph: 180),
    ).listen((anomaly) {
      setState(() => _lastAnomaly = anomaly);
      _recordEvent(
        'anomaly',
        'Anomaly: ${anomaly.speedKph.toStringAsFixed(0)} kph',
      );
    });
    setState(() => _anomalyMonitoringEnabled = true);
    _showSnackbar('Anomaly monitoring started');
  }

  Future<void> _setPace(bool isMoving) async {
    await Locus.location.changePace(isMoving);
    _showSnackbar('Pace: ${isMoving ? "moving" : "stationary"}');
    _recordEvent('motion', 'Pace set: ${isMoving ? "moving" : "stationary"}');
  }

  Future<void> _resetOdometer() async {
    await Locus.location.setOdometer(0);
    await _refreshState();
    _showSnackbar('Odometer reset');
    _recordEvent('state', 'Odometer reset');
  }

  Future<void> _activateDeliveryOps() async {
    if (!_ensureReady()) return;
    await _applySyncContext({
      'shift_id': 'shift-204',
      'driver_id': 'driver-17',
      'route_id': 'route-5',
      'tenant': 'west-coast',
    });
    await _applySyncPolicy(SyncPolicy.balanced, 'Balanced');
    await _setAdaptiveTracking(AdaptiveTrackingConfig.balanced, 'Balanced');
    await _registerDeliveryWorkflow();
    await _configureProfiles(enableAutomation: true);
    if (Locus.trips.getState() == null) {
      await Locus.trips.start(
        const TripConfig(
          tripId: 'delivery-204',
          startOnMoving: true,
          destination: RoutePoint(
            latitude: 37.4187,
            longitude: -122.0816,
          ),
          waypoints: [
            RoutePoint(latitude: 37.4215, longitude: -122.0834),
          ],
        ),
      );
    }
    if (!_isRunning) {
      await Locus.start();
    }
    setState(() => _activeScenario = 'Delivery Ops');
    _showSnackbar('Delivery ops ready');
    _recordEvent('scenario', 'Delivery ops activated');
  }

  Future<void> _activatePrivacyMode() async {
    if (!_ensureReady()) return;
    await _addPrivacyZone();
    if (!_spoofDetectionEnabled) {
      await _toggleSpoof();
    }
    setState(() => _activeScenario = 'Privacy Mode');
    _showSnackbar('Privacy mode enabled');
    _recordEvent('scenario', 'Privacy mode enabled');
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  bool _ensureReady() {
    if (!_isReady) {
      _showSnackbar('SDK not ready', isSuccess: false);
      return false;
    }
    return true;
  }

  void _recordEvent(String type, String message) {
    final time = DateTime.now();
    final ts =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    setState(() {
      _events.insert(0, '[$ts] $message');
      _eventCounts[type] = (_eventCounts[type] ?? 0) + 1;
      if (_events.length > _maxEventEntries) _events.removeLast();
    });
  }

  void _showSnackbar(String message, {bool isSuccess = true}) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            isSuccess ? const Color(0xFF2E7D5F) : const Color(0xFFB33A3A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatLocation(Location loc) {
    return '${loc.coords.latitude.toStringAsFixed(5)}, ${loc.coords.longitude.toStringAsFixed(5)} (±${loc.coords.accuracy.toStringAsFixed(0)}m)';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 24) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes >= 1) {
      return '${duration.inMinutes}m';
    }
    return '${duration.inSeconds}s';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _adaptiveTrackingLabel(AdaptiveTrackingConfig? config) {
    if (config == null) return 'Unknown';
    if (!config.enabled) return 'Disabled';
    if (identical(config, AdaptiveTrackingConfig.aggressive)) {
      return 'Aggressive';
    }
    if (identical(config, AdaptiveTrackingConfig.balanced)) {
      return 'Balanced';
    }
    return 'Custom';
  }

  String _syncPolicyLabel(SyncPolicy policy) {
    if (identical(policy, SyncPolicy.aggressive)) return 'Aggressive';
    if (identical(policy, SyncPolicy.conservative)) return 'Conservative';
    if (identical(policy, SyncPolicy.minimal)) return 'Minimal';
    return 'Balanced';
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locus Example',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5D4B),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      home: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: Row(
              children: [
                SvgPicture.asset(
                  'assets/locus_logo.svg',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Locus',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _refreshState,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
                Tab(icon: Icon(Icons.list_alt_rounded), text: 'Events'),
                Tab(icon: Icon(Icons.storage_rounded), text: 'Storage'),
                Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildDashboard(),
              _buildEvents(),
              _buildStorage(),
              _buildSettings(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Dashboard Tab
  // ===========================================================================

  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        _buildTrackingControls(),
        const SizedBox(height: 16),
        _buildProfileSelector(),
        const SizedBox(height: 16),
        _buildQuickActions(),
        const SizedBox(height: 16),
        _buildGeofencingTools(),
        const SizedBox(height: 16),
        _buildUseCases(),
        const SizedBox(height: 16),
        _buildEventStats(),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusIndicator(active: _isReady, label: 'Ready'),
                const SizedBox(width: 12),
                _StatusIndicator(active: _isRunning, label: 'Tracking'),
                const SizedBox(width: 12),
                _StatusIndicator(
                  active: _lastState?.isMoving ?? false,
                  label: _lastState?.isMoving == true ? 'Moving' : 'Stationary',
                ),
              ],
            ),
            if (_latestLocation != null) ...[
              const Divider(height: 32),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: _formatLocation(_latestLocation!),
              ),
            ],
            if (_lastActivity != null)
              _InfoRow(
                icon: Icons.directions_walk_rounded,
                label: 'Activity',
                value:
                    '${_lastActivity!.type.name} (${_lastActivity!.confidence}%)',
              ),
            if (_lastConnectivity != null)
              _InfoRow(
                icon: Icons.wifi_rounded,
                label: 'Network',
                value: _lastConnectivity!.connected ? 'Online' : 'Offline',
              ),
            if (_lastState?.odometer != null)
              _InfoRow(
                icon: Icons.straighten_rounded,
                label: 'Odometer',
                value: '${_lastState!.odometer!.toStringAsFixed(0)} m',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.play_circle_outline,
              title: 'Tracking',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _toggleTracking,
                    icon: _isRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    label: _isRunning ? 'Stop' : 'Start',
                    color: _isRunning ? Colors.red : Colors.green,
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _getPosition,
                    icon: Icons.my_location_rounded,
                    label: 'Get Position',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.tune_rounded,
              title: 'Profile',
              trailing: _currentProfile != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _currentProfile!.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ProfileChip(
                  label: 'Off Duty',
                  icon: Icons.bedtime_outlined,
                  selected: _currentProfile == TrackingProfile.offDuty,
                  onTap: () => _setProfile(TrackingProfile.offDuty),
                ),
                _ProfileChip(
                  label: 'Standby',
                  icon: Icons.pause_circle_outline,
                  selected: _currentProfile == TrackingProfile.standby,
                  onTap: () => _setProfile(TrackingProfile.standby),
                ),
                _ProfileChip(
                  label: 'En Route',
                  icon: Icons.navigation_outlined,
                  selected: _currentProfile == TrackingProfile.enRoute,
                  onTap: () => _setProfile(TrackingProfile.enRoute),
                ),
                _ProfileChip(
                  label: 'Arrived',
                  icon: Icons.flag_outlined,
                  selected: _currentProfile == TrackingProfile.arrived,
                  onTap: () => _setProfile(TrackingProfile.arrived),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.bolt_rounded,
              title: 'Quick Actions',
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                _QuickActionTile(
                  icon: Icons.add_location_alt_rounded,
                  label: 'Geofence',
                  onTap: _addGeofence,
                ),
                _QuickActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear Geo',
                  onTap: _clearGeofences,
                ),
                _QuickActionTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy',
                  onTap: _addPrivacyZone,
                ),
                _QuickActionTile(
                  icon: Icons.trip_origin_rounded,
                  label: 'Start Trip',
                  onTap: _startTrip,
                ),
                _QuickActionTile(
                  icon: Icons.stop_circle_outlined,
                  label: 'Stop Trip',
                  onTap: _stopTrip,
                ),
                _QuickActionTile(
                  icon: _isSyncPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: _isSyncPaused ? 'Resume Sync' : 'Pause Sync',
                  onTap: _toggleSyncPause,
                ),
                _QuickActionTile(
                  icon: Icons.sync_rounded,
                  label: 'Sync Now',
                  onTap: _syncNow,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeofencingTools() {
    final workflowStatus = _lastWorkflowEvent?.status.name ?? 'idle';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.map_outlined,
              title: 'Geofencing',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatusIndicator(
                  active: _polygonGeofences.isNotEmpty,
                  label: 'Polygons ${_polygonGeofences.length}',
                ),
                const SizedBox(width: 12),
                _StatusIndicator(
                  active: _workflowRegistered,
                  label:
                      _workflowRegistered ? 'Workflow $workflowStatus' : 'No',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _addPolygonGeofence,
                    icon: Icons.crop_square_rounded,
                    label: 'Add Polygon',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _clearPolygonGeofences,
                    icon: Icons.layers_clear_rounded,
                    label: 'Clear Polygons',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _registerDeliveryWorkflow,
                    icon: Icons.route,
                    label: 'Register Flow',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _stopWorkflows,
                    icon: Icons.stop_circle_outlined,
                    label: 'Clear Flow',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUseCases() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.workspaces_filled,
              title: 'Use Cases',
            ),
            const SizedBox(height: 12),
            Text(
              'Active: $_activeScenario',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _activateDeliveryOps,
                    icon: Icons.local_shipping_outlined,
                    label: 'Delivery Ops',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _activatePrivacyMode,
                    icon: Icons.shield_outlined,
                    label: 'Privacy Mode',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Shift',
              value: _syncContext['shift_id']?.toString() ?? '-',
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Driver',
              value: _syncContext['driver_id']?.toString() ?? '-',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventStats() {
    final sorted = _eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.insights_rounded,
              title: 'Event Stats',
            ),
            const SizedBox(height: 16),
            if (sorted.isEmpty)
              const Text('No events yet', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sorted.take(8).map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Events Tab
  // ===========================================================================

  Widget _buildEvents() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_events.length} events',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _events.clear();
                    _eventCounts.clear();
                  });
                  _showSnackbar('Events cleared');
                },
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No events yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFF0F0F0),
                      child: Icon(Icons.circle, size: 8, color: Colors.grey),
                    ),
                    title: Text(
                      _events[i],
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Storage Tab
  // ===========================================================================

  Widget _buildStorage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon: Icons.storage_rounded,
                  title: 'Stored Locations',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_storedLocations.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        onPressed: _loadLocations,
                        icon: Icons.download_rounded,
                        label: 'Load',
                        filled: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        onPressed: _clearLocations,
                        icon: Icons.delete_outline_rounded,
                        label: 'Clear',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_storedLocations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _storedLocations.length.clamp(0, 20),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final loc = _storedLocations[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    _formatLocation(loc),
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    loc.timestamp.toLocal().toString().substring(0, 19),
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildSyncQueueCard(),
        const SizedBox(height: 16),
        _buildHistorySummaryCard(),
        const SizedBox(height: 16),
        _buildPrivacyZonesCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon: Icons.article_outlined,
                  title: 'Logs',
                  trailing: _lastLog != null
                      ? Text(
                          '${_lastLog!.length} entries',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                _ActionButton(
                  onPressed: _loadLogs,
                  icon: Icons.refresh_rounded,
                  label: 'Load Logs',
                  filled: true,
                ),
                if (_lastLog != null && _lastLog!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _lastLog!.take(10).map((e) {
                        final ts =
                            '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}';
                        return '[$ts] ${e.level}: ${e.message}';
                      }).join('\n'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncQueueCard() {
    final itemCount = _syncQueue.length > 5 ? 5 : _syncQueue.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.sync_rounded,
              title: 'Sync Queue',
              trailing: Text(
                '${_syncQueue.length} items',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _enqueueCheckIn,
                    icon: Icons.add_rounded,
                    label: 'Enqueue',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _loadSyncQueue,
                    icon: Icons.refresh_rounded,
                    label: 'Load',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _syncQueueNow,
                    icon: Icons.cloud_upload_outlined,
                    label: 'Sync Queue',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _clearSyncQueue,
                    icon: Icons.delete_outline_rounded,
                    label: 'Clear',
                  ),
                ),
              ],
            ),
            if (_lastQueueId != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last queued: $_lastQueueId',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_syncQueue.isNotEmpty) ...[
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemCount,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = _syncQueue[i];
                  final shortIdLength = item.id.length > 6 ? 6 : item.id.length;
                  return ListTile(
                    dense: true,
                    title: Text(
                      item.type ?? 'payload',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${item.createdAt.toLocal().toString().substring(0, 19)} · retries ${item.retryCount}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      item.id.substring(0, shortIdLength),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySummaryCard() {
    final summary = _locationSummary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.insights_rounded,
              title: 'History Summary',
              trailing: summary != null
                  ? Text(
                      '${summary.locationCount} pts',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            _ActionButton(
              onPressed: _loadLocationSummary,
              icon: Icons.insights_outlined,
              label: 'Load last 12h',
              filled: true,
            ),
            if (summary == null) ...[
              const SizedBox(height: 12),
              const Text(
                'No summary loaded',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.straighten_rounded,
                label: 'Distance',
                value: _formatDistance(summary.totalDistanceMeters),
              ),
              _InfoRow(
                icon: Icons.directions_walk_rounded,
                label: 'Moving',
                value:
                    '${_formatDuration(summary.movingDuration)} (${summary.movingPercent.toStringAsFixed(0)}%)',
              ),
              _InfoRow(
                icon: Icons.pause_circle_outline,
                label: 'Stationary',
                value: _formatDuration(summary.stationaryDuration),
              ),
              if (summary.averageAccuracyMeters != null)
                _InfoRow(
                  icon: Icons.gps_fixed,
                  label: 'Avg Accuracy',
                  value:
                      '${summary.averageAccuracyMeters!.toStringAsFixed(0)} m',
                ),
              _InfoRow(
                icon: Icons.place_outlined,
                label: 'Frequent Spots',
                value: '${summary.frequentLocations.length}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyZonesCard() {
    final zones = _privacyZones;
    final itemCount = zones.length > 4 ? 4 : zones.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Zones',
              trailing: Text(
                '${zones.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _addPrivacyZone,
                    icon: Icons.add_rounded,
                    label: 'Add Demo',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _loadPrivacyZones,
                    icon: Icons.refresh_rounded,
                    label: 'Load',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _clearPrivacyZones,
                    icon: Icons.delete_outline_rounded,
                    label: 'Clear',
                  ),
                ),
              ],
            ),
            if (zones.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'No privacy zones saved',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemCount,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final zone = zones[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      zone.identifier,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${zone.action.name} · ${zone.enabled ? "enabled" : "disabled"}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdaptiveTrackingCard() {
    final label = _adaptiveTrackingLabel(_adaptiveTrackingConfig);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.battery_charging_full_rounded,
              title: 'Adaptive Tracking',
              trailing: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _setAdaptiveTracking(
                        AdaptiveTrackingConfig.balanced, 'Balanced'),
                    icon: Icons.tune,
                    label: 'Balanced',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _setAdaptiveTracking(
                        AdaptiveTrackingConfig.aggressive, 'Aggressive'),
                    icon: Icons.flash_on,
                    label: 'Aggressive',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _setAdaptiveTracking(
                        AdaptiveTrackingConfig.disabled, 'Disabled'),
                    icon: Icons.power_settings_new,
                    label: 'Disable',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _calculateAdaptiveSettings,
                    icon: Icons.tune,
                    label: 'Calc Settings',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ActionButton(
              onPressed: _estimateRunway,
              icon: Icons.timelapse,
              label: 'Estimate Runway',
              filled: true,
            ),
            if (_adaptiveSettings != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.my_location_outlined,
                label: 'Accuracy',
                value: _adaptiveSettings!.desiredAccuracy.name,
              ),
              _InfoRow(
                icon: Icons.linear_scale,
                label: 'Distance Filter',
                value:
                    '${_adaptiveSettings!.distanceFilter.toStringAsFixed(0)} m',
              ),
              _InfoRow(
                icon: Icons.favorite_border,
                label: 'Heartbeat',
                value: '${_adaptiveSettings!.heartbeatInterval}s',
              ),
            ],
            if (_batteryRunway != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.battery_full_rounded,
                label: 'Runway',
                value: _batteryRunway!.formattedDuration,
              ),
              _InfoRow(
                icon: Icons.battery_2_bar_rounded,
                label: 'Low Power',
                value: _batteryRunway!.formattedLowPowerDuration,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncPolicyCard() {
    final label = _syncPolicyLabel(_syncPolicy);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.sync_rounded,
              title: 'Sync Policy',
              trailing: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () =>
                        _applySyncPolicy(SyncPolicy.balanced, 'Balanced'),
                    icon: Icons.tune,
                    label: 'Balanced',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () =>
                        _applySyncPolicy(SyncPolicy.aggressive, 'Aggressive'),
                    icon: Icons.flash_on,
                    label: 'Aggressive',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _applySyncPolicy(
                        SyncPolicy.conservative, 'Conservative'),
                    icon: Icons.slow_motion_video,
                    label: 'Conservative',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () =>
                        _applySyncPolicy(SyncPolicy.minimal, 'Minimal'),
                    icon: Icons.savings_outlined,
                    label: 'Minimal',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ActionButton(
              onPressed: _evaluateSyncPolicy,
              icon: Icons.insights_rounded,
              label: 'Evaluate Policy',
              filled: true,
            ),
            if (_syncDecision != null) ...[
              const SizedBox(height: 12),
              Text(
                _syncDecision!.reason,
                style: const TextStyle(color: Colors.grey),
              ),
              if (_syncDecision!.batchLimit != null)
                _InfoRow(
                  icon: Icons.layers_outlined,
                  label: 'Batch Size',
                  value: '${_syncDecision!.batchLimit}',
                ),
              if (_syncDecision!.delay != null)
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Delay',
                  value: _formatDuration(_syncDecision!.delay!),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncContextCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.badge_outlined,
              title: 'Sync Context',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _applySyncContext(const {
                      'shift_id': 'shift-001',
                      'driver_id': 'driver-42',
                      'route_id': 'route-7',
                    }),
                    icon: Icons.route,
                    label: 'Shift A',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _applySyncContext(const {
                      'shift_id': 'shift-002',
                      'driver_id': 'driver-55',
                      'route_id': 'route-12',
                      'priority': 'rush',
                    }),
                    icon: Icons.route,
                    label: 'Shift B',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.work_outline,
              label: 'Shift',
              value: _syncContext['shift_id']?.toString() ?? '-',
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Driver',
              value: _syncContext['driver_id']?.toString() ?? '-',
            ),
            _InfoRow(
              icon: Icons.route,
              label: 'Route',
              value: _syncContext['route_id']?.toString() ?? '-',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringCard() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Monitoring & Automation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.smart_toy_outlined),
            title: const Text('Tracking Automation'),
            subtitle: const Text('Auto-switch profiles based on rules'),
            value: _automationEnabled,
            onChanged: (_) => _toggleAutomation(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality),
            title: const Text('Quality Monitoring'),
            subtitle: const Text('Assess signal quality'),
            value: _qualityMonitoringEnabled,
            onChanged: (_) => _toggleQualityMonitoring(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.report_problem_outlined),
            title: const Text('Anomaly Detection'),
            subtitle: const Text('Detect implausible jumps'),
            value: _anomalyMonitoringEnabled,
            onChanged: (_) => _toggleAnomalyMonitoring(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.security_rounded),
            title: const Text('Spoof Detection'),
            subtitle: const Text('Detect mock locations'),
            value: _spoofDetectionEnabled,
            onChanged: (_) => _toggleSpoof(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.compare_arrows_rounded),
            title: const Text('Significant Changes'),
            subtitle: const Text('Ultra-low power monitoring'),
            value: _significantChangesEnabled,
            onChanged: (_) => _toggleSignificant(),
          ),
          if (_lastQuality != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.insights_rounded,
                    label: 'Quality Score',
                    value:
                        '${(_lastQuality!.overallScore * 100).toStringAsFixed(0)}%',
                  ),
                  _InfoRow(
                    icon: Icons.speed_rounded,
                    label: 'Jitter',
                    value:
                        '${(_lastQuality!.jitterScore * 100).toStringAsFixed(0)}%',
                  ),
                  _InfoRow(
                    icon: Icons.shield_outlined,
                    label: 'Spoof Suspect',
                    value: _lastQuality!.isSpoofSuspected ? 'Yes' : 'No',
                  ),
                ],
              ),
            ),
          ],
          if (_lastAnomaly != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _InfoRow(
                icon: Icons.warning_rounded,
                label: 'Last Anomaly',
                value: '${_lastAnomaly!.speedKph.toStringAsFixed(0)} kph',
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _setPace(true),
                    icon: Icons.directions_walk_rounded,
                    label: 'Set Moving',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: () => _setPace(false),
                    icon: Icons.do_not_disturb_on_outlined,
                    label: 'Set Stationary',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    onPressed: _resetOdometer,
                    icon: Icons.restore_rounded,
                    label: 'Reset Odo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard() {
    final snapshot = _diagnostics;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.health_and_safety_outlined,
              title: 'Diagnostics',
              trailing: snapshot != null
                  ? Text(
                      snapshot.capturedAt.toLocal().toString().substring(0, 16),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            _ActionButton(
              onPressed: _loadDiagnostics,
              icon: Icons.health_and_safety_outlined,
              label: 'Capture Snapshot',
              filled: true,
            ),
            if (snapshot != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.queue,
                label: 'Queue Size',
                value: '${snapshot.queue.length}',
              ),
              if (snapshot.state != null)
                _InfoRow(
                  icon: Icons.play_circle_outline,
                  label: 'Tracking',
                  value: snapshot.state!.enabled ? 'On' : 'Off',
                ),
              if (snapshot.state?.isMoving != null)
                _InfoRow(
                  icon: Icons.directions_walk_rounded,
                  label: 'Moving',
                  value: snapshot.state!.isMoving ? 'Yes' : 'No',
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Settings Tab
  // ===========================================================================

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Battery',
                  trailing: _powerState != null
                      ? Text(
                          '${_powerState!.batteryLevel}%',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                if (_batteryStats != null) ...[
                  _InfoRow(
                    icon: Icons.gps_fixed,
                    label: 'GPS On Time',
                    value:
                        '${(_batteryStats!.gpsOnTimePercent * 100).toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 8),
                ],
                if (_powerState != null)
                  _InfoRow(
                    icon: Icons.power,
                    label: 'Charging',
                    value: _powerState!.isCharging ? 'Yes' : 'No',
                  ),
                if (_lastPowerEvent != null)
                  _InfoRow(
                    icon: Icons.power_settings_new,
                    label: 'Last Power Change',
                    value: _lastPowerEvent!.changeType.name,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        onPressed: _refreshBattery,
                        icon: Icons.refresh_rounded,
                        label: 'Refresh',
                        filled: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        onPressed: _toggleBenchmark,
                        icon: _benchmarkStatus != null
                            ? Icons.stop_rounded
                            : Icons.speed_rounded,
                        label: _benchmarkStatus ?? 'Benchmark',
                        color: _benchmarkStatus != null ? Colors.red : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildAdaptiveTrackingCard(),
        const SizedBox(height: 16),
        _buildSyncPolicyCard(),
        const SizedBox(height: 16),
        _buildSyncContextCard(),
        const SizedBox(height: 16),
        _buildMonitoringCard(),
        const SizedBox(height: 16),
        _buildDiagnosticsCard(),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon: Icons.info_outline_rounded,
                  title: 'About',
                ),
                SizedBox(height: 16),
                Text(
                  'Locus Example App showcases tracking profiles, sync queues, adaptive tracking, polygon geofences, workflows, diagnostics, and quality monitoring.',
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Reusable Components
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0xFF4CAF50) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? const Color(0xFF4CAF50) : const Color(0xFFBDBDBD),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active ? const Color(0xFF2E7D32) : const Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.color,
    this.filled = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: effectiveColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: effectiveColor),
      label: Text(label, style: TextStyle(color: effectiveColor)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: effectiveColor.withAlpha(100)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
                  )
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F8F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
