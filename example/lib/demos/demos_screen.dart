import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/battery_demo.dart';
import 'package:locus_example/demos/diagnostics_demo.dart';
import 'package:locus_example/demos/geofencing_demo.dart';
import 'package:locus_example/demos/privacy_demo.dart';
import 'package:locus_example/demos/sync_demo.dart';
import 'package:locus_example/demos/tracking_demo.dart';
import 'package:locus_example/demos/trips_demo.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/info_row.dart';
import 'package:locus_example/demos/widgets/quick_action_tile.dart';
import 'package:locus_example/demos/widgets/section_header.dart';

/// Hosts the per-feature demo cards and owns the SDK state shared between
/// them. Mirrors the original monolithic example layout — Dashboard /
/// Events / Storage / Settings — but each card now lives in its own file.
class DemosScreen extends StatefulWidget {
  const DemosScreen({super.key});

  @override
  State<DemosScreen> createState() => _DemosScreenState();
}

class _DemosScreenState extends State<DemosScreen> {
  static const int _maxEventEntries = 250;

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
    await Locus.dataSync.setHeadersCallback(() async {
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

  Future<void> _updateNotification() async {
    final odometer = _lastState?.odometer ?? 0;
    final distance = (odometer / 1000).toStringAsFixed(2);
    final updated = await Locus.updateNotification(
      title: 'Locus Tracker',
      text: 'Distance: $distance km',
    );
    if (updated) {
      _showSnackbar('Notification updated');
    } else {
      _showSnackbar('Notification not updated (tracking inactive)',
          isSuccess: false);
    }
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 1,
            child: Row(
              children: [
                const Expanded(
                  child: TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(
                          icon: Icon(Icons.dashboard_rounded),
                          text: 'Dashboard'),
                      Tab(icon: Icon(Icons.list_alt_rounded), text: 'Events'),
                      Tab(icon: Icon(Icons.storage_rounded), text: 'Storage'),
                      Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _refreshState,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDashboard(),
                EventsView(
                  events: _events,
                  onClear: () {
                    setState(() {
                      _events.clear();
                      _eventCounts.clear();
                    });
                    _showSnackbar('Events cleared');
                  },
                ),
                _buildStorage(),
                _buildSettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Dashboard tab
  // ===========================================================================

  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TrackingStatusCard(
          data: TrackingStatusData(
            isReady: _isReady,
            isRunning: _isRunning,
            lastState: _lastState,
            latestLocation: _latestLocation,
            lastActivity: _lastActivity,
            lastConnectivity: _lastConnectivity,
          ),
        ),
        const SizedBox(height: 16),
        TrackingControlsCard(
          isRunning: _isRunning,
          onToggleTracking: _toggleTracking,
          onGetPosition: _getPosition,
          onUpdateNotification: _updateNotification,
        ),
        const SizedBox(height: 16),
        TrackingProfileCard(
          currentProfile: _currentProfile,
          onSelect: _setProfile,
        ),
        const SizedBox(height: 16),
        _buildQuickActions(),
        const SizedBox(height: 16),
        GeofencingDemoCard(
          polygonCount: _polygonGeofences.length,
          workflowRegistered: _workflowRegistered,
          lastWorkflowEvent: _lastWorkflowEvent,
          onAddPolygon: _addPolygonGeofence,
          onClearPolygons: _clearPolygonGeofences,
          onRegisterWorkflow: _registerDeliveryWorkflow,
          onClearWorkflows: _stopWorkflows,
        ),
        const SizedBox(height: 16),
        TripsDemoCard(
          onStartTrip: _startTrip,
          onStopTrip: _stopTrip,
        ),
        const SizedBox(height: 16),
        _buildUseCases(),
        const SizedBox(height: 16),
        EventStatsCard(eventCounts: _eventCounts),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
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
                QuickActionTile(
                  icon: Icons.add_location_alt_rounded,
                  label: 'Geofence',
                  onTap: _addGeofence,
                ),
                QuickActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear Geo',
                  onTap: _clearGeofences,
                ),
                QuickActionTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy',
                  onTap: _addPrivacyZone,
                ),
                QuickActionTile(
                  icon: Icons.trip_origin_rounded,
                  label: 'Start Trip',
                  onTap: _startTrip,
                ),
                QuickActionTile(
                  icon: Icons.stop_circle_outlined,
                  label: 'Stop Trip',
                  onTap: _stopTrip,
                ),
                QuickActionTile(
                  icon: _isSyncPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: _isSyncPaused ? 'Resume Sync' : 'Pause Sync',
                  onTap: _toggleSyncPause,
                ),
                QuickActionTile(
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

  Widget _buildUseCases() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
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
                  child: ActionButton(
                    onPressed: _activateDeliveryOps,
                    icon: Icons.local_shipping_outlined,
                    label: 'Delivery Ops',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: _activatePrivacyMode,
                    icon: Icons.shield_outlined,
                    label: 'Privacy Mode',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoRow(
              icon: Icons.badge_outlined,
              label: 'Shift',
              value: _syncContext['shift_id']?.toString() ?? '-',
            ),
            InfoRow(
              icon: Icons.person_outline,
              label: 'Driver',
              value: _syncContext['driver_id']?.toString() ?? '-',
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Storage tab
  // ===========================================================================

  Widget _buildStorage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StoredLocationsCard(
          locations: _storedLocations,
          onLoad: _loadLocations,
          onClear: _clearLocations,
        ),
        const SizedBox(height: 16),
        SyncQueueCard(
          queue: _syncQueue,
          lastQueueId: _lastQueueId,
          onEnqueue: _enqueueCheckIn,
          onLoad: _loadSyncQueue,
          onSyncNow: _syncQueueNow,
          onClear: _clearSyncQueue,
        ),
        const SizedBox(height: 16),
        HistorySummaryCard(
          summary: _locationSummary,
          onLoad: _loadLocationSummary,
        ),
        const SizedBox(height: 16),
        PrivacyZonesCard(
          zones: _privacyZones,
          onAdd: _addPrivacyZone,
          onLoad: _loadPrivacyZones,
          onClear: _clearPrivacyZones,
        ),
        const SizedBox(height: 16),
        LogsCard(logs: _lastLog, onLoad: _loadLogs),
      ],
    );
  }

  // ===========================================================================
  // Settings tab
  // ===========================================================================

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BatteryStatusCard(
          powerState: _powerState,
          batteryStats: _batteryStats,
          lastPowerEvent: _lastPowerEvent,
          benchmarkStatus: _benchmarkStatus,
          onRefresh: _refreshBattery,
          onToggleBenchmark: _toggleBenchmark,
        ),
        const SizedBox(height: 16),
        AdaptiveTrackingCard(
          config: _adaptiveTrackingConfig,
          adaptiveSettings: _adaptiveSettings,
          batteryRunway: _batteryRunway,
          onSetConfig: _setAdaptiveTracking,
          onCalculateSettings: _calculateAdaptiveSettings,
          onEstimateRunway: _estimateRunway,
        ),
        const SizedBox(height: 16),
        SyncPolicyCard(
          currentPolicy: _syncPolicy,
          lastDecision: _syncDecision,
          onSelectPolicy: _applySyncPolicy,
          onEvaluate: _evaluateSyncPolicy,
        ),
        const SizedBox(height: 16),
        SyncContextCard(
          context: _syncContext,
          onApplyContext: _applySyncContext,
        ),
        const SizedBox(height: 16),
        MonitoringCard(
          automationEnabled: _automationEnabled,
          qualityMonitoringEnabled: _qualityMonitoringEnabled,
          anomalyMonitoringEnabled: _anomalyMonitoringEnabled,
          spoofDetectionEnabled: _spoofDetectionEnabled,
          significantChangesEnabled: _significantChangesEnabled,
          lastQuality: _lastQuality,
          lastAnomaly: _lastAnomaly,
          onToggleAutomation: _toggleAutomation,
          onToggleQuality: _toggleQualityMonitoring,
          onToggleAnomaly: _toggleAnomalyMonitoring,
          onToggleSpoof: _toggleSpoof,
          onToggleSignificant: _toggleSignificant,
          onSetPace: _setPace,
          onResetOdometer: _resetOdometer,
        ),
        const SizedBox(height: 16),
        DiagnosticsCard(snapshot: _diagnostics, onCapture: _loadDiagnostics),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
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
