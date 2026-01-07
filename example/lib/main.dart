import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:locus/locus.dart';

void main() => runApp(const MotionRecognitionApp());

enum TrackingPreset {
  lowPower,
  balanced,
  tracking,
  trail,
}

class MotionRecognitionApp extends StatefulWidget {
  const MotionRecognitionApp({super.key});

  @override
  State<MotionRecognitionApp> createState() => _MotionRecognitionAppState();
}

class _MotionRecognitionAppState extends State<MotionRecognitionApp> {
  static const int _maxEventEntries = 250;

  StreamSubscription<Location>? _locationSubscription;
  StreamSubscription<Location>? _motionSubscription;
  StreamSubscription<Activity>? _activitySubscription;
  StreamSubscription<LocationAnomaly>? _anomalySubscription;
  StreamSubscription<TripEvent>? _tripSubscription;
  StreamSubscription<GeofenceWorkflowEvent>? _workflowSubscription;
  StreamSubscription<ProviderChangeEvent>? _providerSubscription;
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;
  StreamSubscription<dynamic>? _geofencesChangeSubscription;
  StreamSubscription<Location>? _heartbeatSubscription;
  StreamSubscription<Location>? _scheduleSubscription;
  StreamSubscription<ConnectivityChangeEvent>? _connectivitySubscription;
  StreamSubscription<bool>? _powerSaveSubscription;
  StreamSubscription<bool>? _enabledSubscription;
  StreamSubscription<HttpEvent>? _httpSubscription;
  StreamSubscription<String>? _notificationActionSubscription;

  final List<String> _events = [];
  final Map<String, int> _eventCounts = {};
  Location? _latestLocation;
  Activity? _lastActivity;
  ProviderChangeEvent? _lastProvider;
  ConnectivityChangeEvent? _lastConnectivity;
  GeofenceEvent? _lastGeofence;
  HttpEvent? _lastHttp;
  GeolocationState? _lastState;
  String? _lastNotificationAction;
  List<LogEntry>? _lastLog;
  TripSummary? _lastTripSummary;

  PowerState? _powerState;
  BatteryStats? _batteryStats;
  bool _spoofDetectionEnabled = false;
  bool _significantChangesEnabled = false;
  String? _benchmarkStatus;

  bool _isRunning = false;
  bool _isReady = false;
  bool _scheduleEnabled = false;
  TrackingPreset _selectedPreset = TrackingPreset.tracking;
  TrackingProfile? _currentProfile;

  List<Location> _storedLocations = [];

  @override
  void initState() {
    super.initState();
    // Run configuration without awaiting to keep initState synchronous.
    unawaited(_configure());
  }

  Future<void> _configure() async {
    final isGranted = await Locus.requestPermission();
    if (!isGranted) {
      _showSnackbar('Location permission is required to use this app.');
      return;
    }

    final config = _buildConfig(_selectedPreset);

    await Locus.ready(config);
    await _configureTrackingProfiles();
    _configureWorkflow();
    _setupListeners();
    await _refreshState();

    setState(() {
      _isReady = true;
    });
  }

  Config _buildConfig(TrackingPreset preset) {
    final presetConfig = switch (preset) {
      TrackingPreset.lowPower => ConfigPresets.lowPower,
      TrackingPreset.balanced => ConfigPresets.balanced,
      TrackingPreset.tracking => ConfigPresets.tracking,
      TrackingPreset.trail => ConfigPresets.trail,
    };

    return presetConfig.copyWith(
      stationaryRadius: 25,
      motionTriggerDelay: 15000,
      activityRecognitionInterval: 10000,
      startOnBoot: true,
      stopOnTerminate: false,
      enableHeadless: true,
      disableAutoSyncOnCellular: true,
      maxBatchSize: 20,
      autoSyncThreshold: 10,
      maxRetry: 3,
      retryDelay: 5000,
      retryDelayMultiplier: 2.0,
      maxRetryDelay: 60000,
      persistMode: PersistMode.location,
      maxDaysToPersist: 7,
      maxRecordsToPersist: 200,
      maxMonitoredGeofences: 20,
      url: 'https://example.com/locations',
      logLevel: LogLevel.info,
      logMaxDays: 7,
      schedule: const ['08:00-12:00', '13:00-18:00'],
      notification: const NotificationConfig(
        title: 'Locus',
        text: 'Tracking location in background',
        actions: ['PAUSE', 'STOP'],
      ),
    );
  }

  String _presetLabel(TrackingPreset preset) {
    return switch (preset) {
      TrackingPreset.lowPower => 'Low Power',
      TrackingPreset.balanced => 'Balanced',
      TrackingPreset.tracking => 'Tracking',
      TrackingPreset.trail => 'Trail',
    };
  }

  Future<void> _applyPreset(TrackingPreset preset) async {
    final config = _buildConfig(preset);
    await Locus.setConfig(config);
    setState(() {
      _selectedPreset = preset;
    });
    _recordEvent('preset', 'preset ${_presetLabel(preset)} applied');
  }

  Future<void> _configureTrackingProfiles() async {
    await Locus.setTrackingProfiles(
      {
        TrackingProfile.offDuty: ConfigPresets.lowPower,
        TrackingProfile.standby: ConfigPresets.balanced,
        TrackingProfile.enRoute: ConfigPresets.tracking,
        TrackingProfile.arrived: ConfigPresets.trail,
      },
      initialProfile: TrackingProfile.standby,
      enableAutomation: false,
    );
    setState(() {
      _currentProfile = Locus.currentTrackingProfile;
    });
  }

  Future<void> _applyProfile(TrackingProfile profile) async {
    await Locus.setTrackingProfile(profile);
    setState(() {
      _currentProfile = Locus.currentTrackingProfile;
    });
    _recordEvent('profile', 'profile ${profile.name} applied');
  }

  void _configureWorkflow() {
    Locus.geofencing.registerWorkflows(const [
      GeofenceWorkflow(
        id: 'pickup_dropoff',
        steps: [
          GeofenceWorkflowStep(
            id: 'pickup',
            geofenceIdentifier: 'demo_geofence',
            action: GeofenceAction.enter,
          ),
          GeofenceWorkflowStep(
            id: 'dropoff',
            geofenceIdentifier: 'demo_geofence',
            action: GeofenceAction.exit,
          ),
        ],
      ),
    ]);
  }

  @override
  void dispose() {
    unawaited(_locationSubscription?.cancel());
    unawaited(_motionSubscription?.cancel());
    unawaited(_activitySubscription?.cancel());
    unawaited(_anomalySubscription?.cancel());
    unawaited(_tripSubscription?.cancel());
    unawaited(_workflowSubscription?.cancel());
    unawaited(_providerSubscription?.cancel());
    unawaited(_geofenceSubscription?.cancel());
    unawaited(_geofencesChangeSubscription?.cancel());
    unawaited(_heartbeatSubscription?.cancel());
    unawaited(_scheduleSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_powerSaveSubscription?.cancel());
    unawaited(_enabledSubscription?.cancel());
    unawaited(_httpSubscription?.cancel());
    unawaited(_notificationActionSubscription?.cancel());
    super.dispose();
  }

  void _setupListeners() {
    _locationSubscription = Locus.location.stream.listen((location) {
      _recordEvent(
        'location',
        _formatLocationEvent(location, 'location'),
        updateState: () => _latestLocation = location,
      );
    }, onError: _onError);

    _motionSubscription = Locus.location.motionChanges.listen((location) {
      _recordEvent(
        'motionchange',
        _formatLocationEvent(location, 'motionchange'),
        updateState: () => _latestLocation = location,
      );
    }, onError: _onError);

    _activitySubscription = Locus.instance.activityStream.listen((activity) {
      _recordEvent(
        'activitychange',
        'activity ${activity.type.name} (${activity.confidence}%)',
        updateState: () => _lastActivity = activity,
      );
    }, onError: _onError);

    _anomalySubscription = Locus.onLocationAnomaly(
      (anomaly) {
        _recordEvent(
          'anomaly',
          'anomaly ${anomaly.speedKph.toStringAsFixed(1)} kph over '
              '${anomaly.distanceMeters.toStringAsFixed(0)} m',
        );
      },
      config: const LocationAnomalyConfig(
        maxSpeedKph: 200,
        minDistanceMeters: 500,
      ),
      onError: _onError,
    );

    _tripSubscription = Locus.trips.events.listen((event) {
      _recordEvent('trip', 'trip ${event.type.name}');
      if (event.summary != null) {
        setState(() {
          _lastTripSummary = event.summary;
        });
      }
    }, onError: _onError);

    _workflowSubscription = Locus.geofencing.workflowEvents.listen((event) {
      _recordEvent(
        'workflow',
        'workflow ${event.workflowId} ${event.status.name}',
      );
    }, onError: _onError);

    _providerSubscription = Locus.instance.providerStream.listen((event) {
      _recordEvent(
        'providerchange',
        'provider enabled=${event.enabled} auth=${event.authorizationStatus.name}',
        updateState: () => _lastProvider = event,
      );
    }, onError: _onError);

    _geofenceSubscription = Locus.geofencing.events.listen((event) {
      _recordEvent(
        'geofence',
        'geofence ${event.geofence.identifier} ${event.action.name}',
        updateState: () => _lastGeofence = event,
      );
    }, onError: _onError);

    _geofencesChangeSubscription = Locus.geofencing.onGeofencesChange((event) {
      _recordEvent('geofenceschange', 'geofences change: $event');
    }, onError: _onError);

    _heartbeatSubscription = Locus.location.heartbeats.listen((location) {
      _recordEvent('heartbeat', _formatLocationEvent(location, 'heartbeat'));
    }, onError: _onError);

    _scheduleSubscription = Locus.instance.onSchedule((location) {
      _recordEvent('schedule', _formatLocationEvent(location, 'schedule'));
    }, onError: _onError);

    _connectivitySubscription =
        Locus.dataSync.connectivityEvents.listen((event) {
      _recordEvent(
        'connectivity',
        'connectivity ${event.networkType ?? 'unknown'} connected=${event.connected}',
        updateState: () => _lastConnectivity = event,
      );
    }, onError: _onError);

    _powerSaveSubscription = Locus.instance.powerSaveStream.listen((enabled) {
      _recordEvent('powersave', 'powersave enabled=$enabled');
    }, onError: _onError);

    _enabledSubscription = Locus.instance.enabledStream.listen((enabled) {
      _recordEvent(
        'enabledchange',
        'enabled=$enabled',
        updateState: () => _isRunning = enabled,
      );
    }, onError: _onError);

    _httpSubscription = Locus.dataSync.events.listen((event) {
      _recordEvent(
        'http',
        'http status=${event.status} ok=${event.ok}',
        updateState: () => _lastHttp = event,
      );
    }, onError: _onError);

    _notificationActionSubscription =
        Locus.instance.onNotificationAction((action) {
      _recordEvent(
        'notification',
        'notification action=$action',
        updateState: () => _lastNotificationAction = action,
      );
    }, onError: _onError);
  }

  Future<void> _refreshState() async {
    final state = await Locus.getState();
    setState(() {
      _lastState = state;
      _isRunning = state.enabled;
      _scheduleEnabled = state.schedulerEnabled ?? _scheduleEnabled;
    });
  }

  Future<void> _startOrStopTracking() async {
    if (!_isReady) {
      _showSnackbar('Call ready() first.');
      return;
    }
    if (_isRunning) {
      await Locus.stop();
    } else {
      await Locus.start();
    }
    await _refreshState();
  }

  Future<void> _getCurrentPosition() async {
    try {
      final location = await Locus.location.getCurrentPosition();
      _showSnackbar(
        'Position: ${location.coords.latitude.toStringAsFixed(5)}, ${location.coords.longitude.toStringAsFixed(5)}',
      );
      _recordEvent(
        'currentposition',
        _formatLocationEvent(location, 'getCurrentPosition'),
        updateState: () => _latestLocation = location,
      );
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _toggleSchedule() async {
    if (_scheduleEnabled) {
      await Locus.stopSchedule();
    } else {
      await Locus.startSchedule();
    }
    setState(() {
      _scheduleEnabled = !_scheduleEnabled;
    });
  }

  Future<void> _loadStoredLocations() async {
    final locations = await Locus.location.getLocations(limit: 50);
    setState(() {
      _storedLocations = locations;
    });
  }

  Future<void> _clearStoredLocations() async {
    await Locus.location.destroyLocations();
    setState(() {
      _storedLocations = [];
    });
  }

  Future<void> _startTrip() async {
    await Locus.trips.start(const TripConfig(
      startOnMoving: true,
      updateIntervalSeconds: 30,
      route: [
        RoutePoint(latitude: 37.4219983, longitude: -122.084),
        RoutePoint(latitude: 37.4279613, longitude: -122.0857497),
      ],
      routeDeviationThresholdMeters: 150,
    ));
    _recordEvent('trip', 'trip start requested');
  }

  Future<void> _stopTrip() async {
    final summary = await Locus.trips.stop();
    if (!mounted) return;
    setState(() {
      _lastTripSummary = summary;
    });
    _recordEvent('trip', 'trip stop requested');
  }

  Future<void> _addDemoGeofence() async {
    await Locus.geofencing.add(const Geofence(
      identifier: 'demo_geofence',
      radius: 100,
      latitude: 37.4219983,
      longitude: -122.084,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: true,
      loiteringDelay: 300000,
      extras: {'source': 'example'},
    ));
    _showSnackbar('Geofence added');
  }

  Future<void> _removeAllGeofences() async {
    await Locus.geofencing.removeAll();
    _showSnackbar('Geofences cleared');
  }

  Future<void> _loadLog() async {
    final log = await Locus.getLog();
    setState(() {
      _lastLog = log;
    });
  }

  void _clearEvents() {
    setState(() {
      _events.clear();
      _eventCounts.clear();
    });
  }

  void _recordEvent(
    String type,
    String message, {
    VoidCallback? updateState,
  }) {
    final timestamp = _formatTimestamp(DateTime.now());
    setState(() {
      updateState?.call();
      _events.insert(0, '[$timestamp] $message');
      _eventCounts[type] = (_eventCounts[type] ?? 0) + 1;
      if (_events.length > _maxEventEntries) {
        _events.removeLast();
      }
    });
  }

  void _onError(Object error) {
    if (mounted) {
      _showSnackbar('Error: $error');
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F5D50),
      brightness: Brightness.light,
    );

    return MaterialApp(
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F1EC),
        textTheme: GoogleFonts.spaceGroteskTextTheme(),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      home: DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Locus'),
            actions: [
              IconButton(
                onPressed: _refreshState,
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                onPressed: _clearEvents,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Overview', icon: Icon(Icons.route)),
                Tab(text: 'Events', icon: Icon(Icons.timeline)),
                Tab(text: 'Storage', icon: Icon(Icons.storage)),
                Tab(text: 'Diagnostics', icon: Icon(Icons.tune)),
                Tab(text: 'Advanced', icon: Icon(Icons.science)),
              ],
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF4F1EC),
                  Color(0xFFE7EFEA),
                ],
              ),
            ),
            child: TabBarView(
              children: [
                _buildOverviewTab(),
                _buildEventsTab(),
                _buildStorageTab(),
                _buildDiagnosticsTab(),
                _buildAdvancedTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStatusPanel(),
          _buildControlPanel(),
          _buildQuickStats(),
        ],
      ),
    );
  }

  Widget _buildEventsTab() {
    return Column(
      children: [
        _buildEventSummary(),
        Expanded(child: _buildEventList()),
      ],
    );
  }

  Widget _buildStorageTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStoragePanel(),
          _buildStoredList(),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildDiagnosticsPanel(),
          _buildLogPanel(),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    final location = _latestLocation;
    final provider = _lastProvider;
    final connectivity = _lastConnectivity;
    final state = _lastState;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  label: _isReady ? 'Ready' : 'Not Ready',
                  icon: Icons.flash_on,
                  active: _isReady,
                ),
                _buildStatusChip(
                  label: _isRunning ? 'Tracking' : 'Stopped',
                  icon: _isRunning ? Icons.play_arrow : Icons.pause,
                  active: _isRunning,
                ),
                _buildStatusChip(
                  label: state?.isMoving == true ? 'Moving' : 'Stationary',
                  icon: Icons.directions_walk,
                  active: state?.isMoving == true,
                ),
                _buildStatusChip(
                  label: _scheduleEnabled ? 'Schedule On' : 'Schedule Off',
                  icon: Icons.schedule,
                  active: _scheduleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Odometer: ${state?.odometer?.toStringAsFixed(1) ?? '0'} m'),
            const SizedBox(height: 6),
            Text(
              'Latest: ${location != null ? location.event ?? 'location' : 'N/A'}',
            ),
            if (location != null)
              Text(
                'Lat ${location.coords.latitude.toStringAsFixed(5)}, '
                'Lng ${location.coords.longitude.toStringAsFixed(5)}',
              ),
            const SizedBox(height: 6),
            Text(
              'Provider: ${provider?.authorizationStatus.name ?? 'unknown'} | '
              'Availability: ${provider?.availability.name ?? 'unknown'}',
            ),
            Text(
              'Connectivity: ${connectivity?.networkType ?? 'unknown'} '
              '(${connectivity?.connected == true ? 'online' : 'offline'})',
            ),
            if (_lastActivity != null)
              Text(
                'Activity: ${_lastActivity!.type.name} '
                '(${_lastActivity!.confidence}%)',
              ),
            if (_lastHttp != null)
              Text('Last HTTP: ${_lastHttp!.status} ok=${_lastHttp!.ok}'),
            if (_lastGeofence != null)
              Text(
                'Last Geofence: ${_lastGeofence!.geofence.identifier} '
                '${_lastGeofence!.action.name}',
              ),
            if (_currentProfile != null)
              Text('Profile: ${_currentProfile!.name}'),
            if (_lastTripSummary != null)
              Text(
                'Last Trip: ${_lastTripSummary!.distanceMeters.toStringAsFixed(0)} m '
                'in ${_lastTripSummary!.durationSeconds}s',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required IconData icon,
    required bool active,
  }) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.grey;
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TrackingPreset>(
                    initialValue: _selectedPreset,
                    decoration: const InputDecoration(
                      labelText: 'Tracking preset',
                      border: OutlineInputBorder(),
                    ),
                    items: TrackingPreset.values
                        .map(
                          (preset) => DropdownMenuItem(
                            value: preset,
                            child: Text(_presetLabel(preset)),
                          ),
                        )
                        .toList(),
                    onChanged: (preset) async {
                      if (preset != null) {
                        await _applyPreset(preset);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _startOrStopTracking,
                  icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(_isRunning ? 'Stop Tracking' : 'Start Tracking'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isRunning
                        ? Colors.redAccent
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _getCurrentPosition,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Get Position'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _toggleSchedule,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    _scheduleEnabled ? 'Stop Schedule' : 'Start Schedule',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addDemoGeofence,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Add Geofence'),
                ),
                OutlinedButton.icon(
                  onPressed: _removeAllGeofences,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Geofences'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _applyProfile(TrackingProfile.offDuty),
                  icon: const Icon(Icons.bedtime_outlined),
                  label: const Text('Off Duty'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _applyProfile(TrackingProfile.standby),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Standby'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _applyProfile(TrackingProfile.enRoute),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('En Route'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _applyProfile(TrackingProfile.arrived),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Arrived'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _startTrip,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Start Trip'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _stopTrip(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Trip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final entries = _eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Event Pulse',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty) const Text('No events recorded yet.'),
            if (entries.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entries
                    .map(
                      (entry) => Chip(
                        label: Text('${entry.key}: ${entry.value}'),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total events: ${_events.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Max: $_maxEventEntries',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList() {
    return ListView.separated(
      itemCount: _events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, int idx) {
        final entry = _events[idx];
        return ListTile(
          leading: const Icon(Icons.location_pin),
          title: Text(entry),
        );
      },
    );
  }

  Widget _buildStoragePanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stored Locations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _loadStoredLocations,
                  icon: const Icon(Icons.download),
                  label: const Text('Load'),
                ),
                OutlinedButton.icon(
                  onPressed: _clearStoredLocations,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
                Chip(
                  label: Text('Count: ${_storedLocations.length}'),
                ),
              ],
            ),
            if (_storedLocations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Latest stored: ${_storedLocations.last.coords.latitude.toStringAsFixed(5)}, '
                '${_storedLocations.last.coords.longitude.toStringAsFixed(5)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStoredList() {
    if (_storedLocations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _storedLocations.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, int index) {
            final location = _storedLocations[index];
            return ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(
                '${location.coords.latitude.toStringAsFixed(5)}, '
                '${location.coords.longitude.toStringAsFixed(5)}',
              ),
              subtitle: Text(
                location.timestamp.toIso8601String(),
              ),
              trailing: Text(
                '${location.coords.accuracy.toStringAsFixed(1)}m',
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    final state = _lastState;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Enabled: ${state?.enabled ?? false}'),
            Text('Moving: ${state?.isMoving ?? false}'),
            Text('Scheduler: ${state?.schedulerEnabled ?? false}'),
            Text('Odometer: ${state?.odometer?.toStringAsFixed(1) ?? '0'}'),
            const SizedBox(height: 8),
            if (_lastProvider != null)
              Text(
                'Provider status: ${_lastProvider!.authorizationStatus.name}',
              ),
            if (_lastConnectivity != null)
              Text(
                'Network: ${_lastConnectivity!.networkType ?? 'unknown'} '
                '(${_lastConnectivity!.connected ? 'online' : 'offline'})',
              ),
            if (_lastNotificationAction != null)
              Text('Notification action: $_lastNotificationAction'),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Logs',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _loadLog,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Load Log'),
                ),
              ],
            ),
            if (_lastLog != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _lastLog!.isEmpty
                      ? 'No logs yet.'
                      : _formatLogEntries(_lastLog!),
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildBatteryOptimizationCard(),
          _buildSpoofDetectionCard(),
          _buildSignificantChangesCard(),
          _buildErrorRecoveryCard(),
        ],
      ),
    );
  }

  Widget _buildBatteryOptimizationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_charging_full),
                const SizedBox(width: 8),
                Text(
                  'Battery Optimization',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_powerState != null) ...[
              Text(
                'Battery: ${_powerState!.batteryLevel}% '
                '(${_powerState!.isCharging ? "Charging" : "Discharging"})',
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _refreshBatteryStats,
                  child: const Text('Refresh Stats'),
                ),
                FilledButton.tonal(
                  onPressed: _benchmarkStatus == null ? _toggleBenchmark : null,
                  child: const Text('Start Benchmark'),
                ),
                if (_benchmarkStatus != null)
                  FilledButton(
                    onPressed: _toggleBenchmark,
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Stop Benchmark'),
                  ),
              ],
            ),
            if (_batteryStats != null) ...[
              const SizedBox(height: 16),
              const Text('Stats:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'GPS On Time: ${(_batteryStats!.gpsOnTimePercent * 100).toStringAsFixed(1)}%'),
              Text(
                  'Drain Rate: ${_batteryStats!.estimatedDrainPerHour?.toStringAsFixed(1) ?? "N/A"}%/hr'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpoofDetectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security),
                const SizedBox(width: 8),
                Text(
                  'Spoof Detection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Enable Detection'),
              subtitle: const Text('Detect mock/spoofed locations'),
              value: _spoofDetectionEnabled,
              onChanged: (val) => _toggleSpoofDetection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignificantChangesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows),
                const SizedBox(width: 8),
                Text(
                  'Significant Changes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Monitor Changes'),
              subtitle: const Text('Ultra-low power (~500m)'),
              value: _significantChangesEnabled,
              onChanged: (val) => _toggleSignificantChanges(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorRecoveryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.healing),
                const SizedBox(width: 8),
                Text(
                  'Error Recovery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _simulateError,
              child: const Text('Simulate Network Error'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshBatteryStats() async {
    final state = await Locus.battery.getPowerState();
    final stats = await Locus.battery.getStats();
    setState(() {
      _powerState = state;
      _batteryStats = stats;
    });
  }

  Future<void> _toggleBenchmark() async {
    if (_benchmarkStatus == null) {
      await Locus.startBatteryBenchmark();
      setState(() => _benchmarkStatus = 'Running...');
      _showSnackbar('Benchmark started');
    } else {
      await Locus.stopBatteryBenchmark();
      setState(() => _benchmarkStatus = null);
      _showSnackbar('Benchmark stopped');
    }
  }

  Future<void> _toggleSpoofDetection() async {
    final newValue = !_spoofDetectionEnabled;
    await Locus.setSpoofDetection(
      newValue ? SpoofDetectionConfig.high : SpoofDetectionConfig.disabled,
    );
    setState(() => _spoofDetectionEnabled = newValue);
    _showSnackbar('Spoof detection ${newValue ? "enabled" : "disabled"}');
  }

  Future<void> _toggleSignificantChanges() async {
    final newValue = !_significantChangesEnabled;
    if (newValue) {
      await Locus.startSignificantChangeMonitoring(
        SignificantChangeConfig.defaults,
      );
    } else {
      await Locus.stopSignificantChangeMonitoring();
    }
    setState(() => _significantChangesEnabled = newValue);
  }

  Future<void> _simulateError() async {
    await Locus.handleError(LocusError.networkError(
      message: 'Simulated connection failure',
      originalError: 'Simulated',
    ));
    // The ErrorRecoveryManager logs this, so check logs
    _showSnackbar('Simulated error injected');
  }

  String _formatLocationEvent(Location location, String label) {
    final lat = location.coords.latitude.toStringAsFixed(5);
    final lng = location.coords.longitude.toStringAsFixed(5);
    return '$label: $lat, $lng (acc ${location.coords.accuracy.toStringAsFixed(1)}m)';
  }

  String _formatTimestamp(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    final seconds = time.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatLogEntries(List<LogEntry> entries) {
    return entries.take(12).map((entry) {
      final timestamp = _formatTimestamp(entry.timestamp.toLocal());
      final tag = entry.tag;
      final level = tag == null ? entry.level : '${entry.level}/$tag';
      return '[$timestamp] $level ${entry.message}';
    }).join('\n');
  }
}
