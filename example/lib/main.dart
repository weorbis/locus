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
  List<Location> _storedLocations = [];

  // Toggles
  bool _isRunning = false;
  bool _isReady = false;
  bool _scheduleEnabled = false;
  bool _spoofDetectionEnabled = false;
  bool _significantChangesEnabled = false;
  String? _benchmarkStatus;
  TrackingProfile? _currentProfile;

  @override
  void initState() {
    super.initState();
    unawaited(_configure());
  }

  @override
  void dispose() {
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
      persistMode: PersistMode.location,
      maxDaysToPersist: 7,
      maxRecordsToPersist: 200,
      maxMonitoredGeofences: 20,
      url: 'https://example.com/locations',
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

    // Demo: Custom sync body builder
    await Locus.setSyncBodyBuilder((locations, extras) async {
      return {
        'app': 'locus_example',
        'timestamp': DateTime.now().toIso8601String(),
        'locations': locations.map((l) => l.toMap()).toList(),
        ...extras,
      };
    });

    setState(() => _isReady = true);
  }

  Future<void> _configureProfiles() async {
    await Locus.setTrackingProfiles(
      {
        TrackingProfile.offDuty: ConfigPresets.lowPower,
        TrackingProfile.standby: ConfigPresets.balanced,
        TrackingProfile.enRoute: ConfigPresets.tracking,
        TrackingProfile.arrived: ConfigPresets.trail,
      },
      initialProfile: TrackingProfile.standby,
    );
    setState(() => _currentProfile = Locus.currentTrackingProfile);
  }

  void _setupListeners() {
    _subscriptions.addAll([
      Locus.location.stream.listen((loc) {
        _recordEvent('location', _formatLocation(loc));
        setState(() => _latestLocation = loc);
      }),
      Locus.location.motionChanges.listen((loc) {
        _recordEvent('motion', 'Motion: ${loc.isMoving == true ? "moving" : "stationary"}');
        setState(() => _latestLocation = loc);
      }),
      Locus.instance.activityStream.listen((activity) {
        _recordEvent('activity', 'Activity: ${activity.type.name} (${activity.confidence}%)');
        setState(() => _lastActivity = activity);
      }),
      Locus.trips.events.listen((event) {
        _recordEvent('trip', 'Trip: ${event.type.name}');
        if (event.summary != null) setState(() => _lastTripSummary = event.summary);
      }),
      Locus.instance.providerStream.listen((event) {
        _recordEvent('provider', 'Provider: ${event.authorizationStatus.name}');
        setState(() => _lastProvider = event);
      }),
      Locus.geofencing.events.listen((event) {
        _recordEvent('geofence', 'Geofence: ${event.geofence.identifier} ${event.action.name}');
        setState(() => _lastGeofence = event);
      }),
      Locus.dataSync.connectivityEvents.listen((event) {
        _recordEvent('connectivity', 'Network: ${event.connected ? "online" : "offline"}');
        setState(() => _lastConnectivity = event);
      }),
      Locus.instance.enabledStream.listen((enabled) {
        _recordEvent('state', 'Tracking: ${enabled ? "started" : "stopped"}');
        setState(() => _isRunning = enabled);
      }),
      Locus.dataSync.events.listen((event) {
        _recordEvent('http', 'HTTP: ${event.status} ${event.ok ? "OK" : "FAILED"}');
        setState(() => _lastHttp = event);
      }),
      Locus.instance.onNotificationAction((action) {
        _recordEvent('notification', 'Action: $action');
        setState(() => _lastNotificationAction = action);
      }),
    ]);
  }

  // ===========================================================================
  // Actions
  // ===========================================================================

  Future<void> _refreshState() async {
    final state = await Locus.getState();
    setState(() {
      _lastState = state;
      _isRunning = state.enabled;
      _scheduleEnabled = state.schedulerEnabled ?? false;
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
      _showSnackbar('Position: ${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}');
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
    await Locus.geofencing.add(const Geofence(
      identifier: 'demo_geofence',
      radius: 100,
      latitude: 37.4219983,
      longitude: -122.084,
      notifyOnEntry: true,
      notifyOnExit: true,
    ));
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
    await Locus.privacy.add(PrivacyZone.create(
      identifier: 'demo_zone',
      latitude: 37.4219983,
      longitude: -122.084,
      radius: 200,
      action: PrivacyZoneAction.obfuscate,
    ));
    final count = (await Locus.privacy.getAll()).length;
    _showSnackbar('Privacy zone added ($count total)');
    _recordEvent('privacy', 'Added demo_zone');
  }

  Future<void> _clearPrivacyZones() async {
    final count = (await Locus.privacy.getAll()).length;
    await Locus.privacy.removeAll();
    _showSnackbar('Cleared $count privacy zone(s)');
    _recordEvent('privacy', 'Cleared all');
  }

  Future<void> _startTrip() async {
    await Locus.trips.start(const TripConfig(startOnMoving: true));
    _showSnackbar('Trip started');
    _recordEvent('trip', 'Trip started');
  }

  Future<void> _stopTrip() async {
    final summary = await Locus.trips.stop();
    setState(() => _lastTripSummary = summary);
    if (summary != null) {
      _showSnackbar('Trip: ${summary.distanceMeters.toStringAsFixed(0)}m');
    } else {
      _showSnackbar('Trip stopped');
    }
    _recordEvent('trip', 'Trip stopped');
  }

  Future<void> _syncNow() async {
    final result = await Locus.dataSync.now();
    _showSnackbar('Sync: $result');
    _recordEvent('sync', 'Manual sync: $result');
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
    _recordEvent('battery', '${state.batteryLevel}%, GPS: ${(stats.gpsOnTimePercent * 100).toStringAsFixed(0)}%');
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
      await Locus.startSignificantChangeMonitoring(SignificantChangeConfig.defaults);
    } else {
      await Locus.stopSignificantChangeMonitoring();
    }
    setState(() => _significantChangesEnabled = enabled);
    _showSnackbar('Significant changes: ${enabled ? "ON" : "OFF"}');
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  void _recordEvent(String type, String message) {
    final time = DateTime.now();
    final ts = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
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
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: isSuccess ? const Color(0xFF2E7D5F) : const Color(0xFFB33A3A),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                const Text('Locus', style: TextStyle(fontWeight: FontWeight.bold)),
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
                value: '${_lastActivity!.type.name} (${_lastActivity!.confidence}%)',
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
            const _SectionHeader(icon: Icons.play_circle_outline, title: 'Tracking'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    onPressed: _toggleTracking,
                    icon: _isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            const _SectionHeader(icon: Icons.bolt_rounded, title: 'Quick Actions'),
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
                  icon: Icons.sync_rounded,
                  label: 'Sync',
                  onTap: _syncNow,
                ),
              ],
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
            const _SectionHeader(icon: Icons.insights_rounded, title: 'Event Stats'),
            const SizedBox(height: 16),
            if (sorted.isEmpty)
              const Text('No events yet', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sorted.take(8).map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                      Text('No events yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFF0F0F0),
                      child: Icon(Icons.circle, size: 8, color: Colors.grey),
                    ),
                    title: Text(
                      _events[i],
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_storedLocations.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
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
                      ? Text('${_lastLog!.length} entries', style: const TextStyle(fontSize: 12, color: Colors.grey))
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
                        final ts = '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}';
                        return '[$ts] ${e.level}: ${e.message}';
                      }).join('\n'),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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
                      ? Text('${_powerState!.batteryLevel}%', style: const TextStyle(fontWeight: FontWeight.w600))
                      : null,
                ),
                const SizedBox(height: 16),
                if (_batteryStats != null) ...[
                  _InfoRow(
                    icon: Icons.gps_fixed,
                    label: 'GPS On Time',
                    value: '${(_batteryStats!.gpsOnTimePercent * 100).toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 8),
                ],
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
                        icon: _benchmarkStatus != null ? Icons.stop_rounded : Icons.speed_rounded,
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
        Card(
          child: Column(
            children: [
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.info_outline_rounded, title: 'About'),
                const SizedBox(height: 16),
                const Text(
                  'Locus Example App demonstrates the core features of the Locus SDK including location tracking, geofencing, privacy zones, and sync.',
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
  const _SectionHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
  const _InfoRow({required this.icon, required this.label, required this.value});

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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
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
                ? Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(100))
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
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
