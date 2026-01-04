/// Debug overlay widget for visualizing Locus state during development.
///
/// Provides a floating overlay that shows real-time location, activity,
/// battery, sync queue, geofence, and service state information.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locus/src/locus.dart';
import 'package:locus/src/models.dart';

/// A debug overlay widget that displays real-time Locus information.
///
/// Add this widget to your app during development to visualize
/// location tracking state, current position, activity, and more.
///
/// Example:
/// ```dart
/// Stack(
///   children: [
///     YourApp(),
///     if (kDebugMode) const LocusDebugOverlay(),
///   ],
/// )
/// ```
class LocusDebugOverlay extends StatefulWidget {
  /// Creates a debug overlay widget.
  const LocusDebugOverlay({
    super.key,
    this.position = DebugOverlayPosition.bottomRight,
    this.expanded = false,
    this.showMap = false,
    this.opacity = 0.9,
  });

  /// Position of the overlay on screen.
  final DebugOverlayPosition position;

  /// Whether the overlay starts expanded.
  final bool expanded;

  /// Whether to show a mini-map (requires additional setup).
  final bool showMap;

  /// Overlay background opacity.
  final double opacity;

  @override
  State<LocusDebugOverlay> createState() => _LocusDebugOverlayState();
}

/// Position options for the debug overlay.
enum DebugOverlayPosition {
  /// Top-left corner.
  topLeft,

  /// Top-right corner.
  topRight,

  /// Bottom-left corner.
  bottomLeft,

  /// Bottom-right corner.
  bottomRight,
}

class _LocusDebugOverlayState extends State<LocusDebugOverlay> {
  bool _isExpanded = false;
  Location? _lastLocation;
  bool _isEnabled = false;
  bool _isMoving = false;
  double _odometer = 0;
  int _locationCount = 0;
  final _locations = <Location>[];
  final _subscriptions = <StreamSubscription>[];

  // Battery state
  BatteryStats? _batteryStats;
  BatteryRunway? _batteryRunway;

  // Sync queue state
  int _pendingSyncCount = 0;
  int _syncSuccessCount = 0;
  int _syncFailureCount = 0;

  // Geofence state
  int _geofenceCount = 0;
  int _geofenceEventCount = 0;

  // Performance metrics
  DateTime? _trackingStartTime;
  final _locationTimestamps = <DateTime>[];

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.expanded;
    _trackingStartTime = DateTime.now();
    _setupListeners();
    _loadInitialState();
    _startPeriodicUpdates();
  }

  Timer? _updateTimer;

  void _startPeriodicUpdates() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadBatteryData(),
      _loadSyncQueueData(),
      _loadGeofenceData(),
    ]);
  }

  Future<void> _loadBatteryData() async {
    try {
      final stats = await Locus.getBatteryStats();
      final runway = await Locus.estimateBatteryRunway();
      if (mounted) {
        setState(() {
          _batteryStats = stats;
          _batteryRunway = runway;
        });
      }
    } catch (_) {
      // Battery data may not be available
    }
  }

  Future<void> _loadSyncQueueData() async {
    try {
      final queue = await Locus.getQueue();
      if (mounted) {
        setState(() {
          _pendingSyncCount = queue.length;
        });
      }
    } catch (_) {
      // Queue may not be available
    }
  }

  Future<void> _loadGeofenceData() async {
    try {
      final geofences = await Locus.getGeofences();
      if (mounted) {
        setState(() {
          _geofenceCount = geofences.length;
        });
      }
    } catch (_) {
      // Geofences may not be available
    }
  }

  Future<void> _loadInitialState() async {
    try {
      final state = await Locus.getState();
      if (mounted) {
        setState(() {
          _isEnabled = state.enabled;
          _isMoving = state.isMoving;
          _odometer = state.odometer ?? 0;
          _lastLocation = state.location;
        });
      }
      await _refreshData();
    } catch (_) {
      // SDK may not be initialized yet
    }
  }

  void _setupListeners() {
    _subscriptions.add(
      Locus.onLocation((location) {
        if (mounted) {
          final now = DateTime.now();
          setState(() {
            _lastLocation = location;
            _locationCount++;
            _odometer = location.odometer ?? _odometer;
            _locations.insert(0, location);
            if (_locations.length > 50) {
              _locations.removeLast();
            }
            // Track timestamps for locations per minute calculation
            _locationTimestamps.add(now);
            // Remove timestamps older than 1 minute
            _locationTimestamps.removeWhere(
              (ts) => now.difference(ts).inSeconds > 60,
            );
          });
        }
      }),
    );

    _subscriptions.add(
      Locus.onEnabledChange((enabled) {
        if (mounted) {
          setState(() {
            _isEnabled = enabled;
            if (enabled) {
              _trackingStartTime = DateTime.now();
            }
          });
        }
      }),
    );

    _subscriptions.add(
      Locus.onMotionChange((location) {
        if (mounted) {
          setState(() => _isMoving = location.isMoving ?? false);
        }
      }),
    );

    _subscriptions.add(
      Locus.onGeofence((event) {
        if (mounted) {
          setState(() => _geofenceEventCount++);
        }
      }),
    );

    _subscriptions.add(
      Locus.onHttp((event) {
        if (mounted) {
          setState(() {
            if (event.ok) {
              _syncSuccessCount++;
            } else {
              _syncFailureCount++;
            }
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: _getTop(),
      bottom: _getBottom(),
      left: _getLeft(),
      right: _getRight(),
      child: SafeArea(
        child: _buildOverlay(),
      ),
    );
  }

  double? _getTop() {
    switch (widget.position) {
      case DebugOverlayPosition.topLeft:
      case DebugOverlayPosition.topRight:
        return 8;
      default:
        return null;
    }
  }

  double? _getBottom() {
    switch (widget.position) {
      case DebugOverlayPosition.bottomLeft:
      case DebugOverlayPosition.bottomRight:
        return 8;
      default:
        return null;
    }
  }

  double? _getLeft() {
    switch (widget.position) {
      case DebugOverlayPosition.topLeft:
      case DebugOverlayPosition.bottomLeft:
        return 8;
      default:
        return null;
    }
  }

  double? _getRight() {
    switch (widget.position) {
      case DebugOverlayPosition.topRight:
      case DebugOverlayPosition.bottomRight:
        return 8;
      default:
        return null;
    }
  }

  Widget _buildOverlay() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Colors.black.withAlpha((widget.opacity * 255).toInt()),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
      ),
    );
  }

  Widget _buildCollapsedView() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isEnabled ? Icons.location_on : Icons.location_off,
              color: _isEnabled ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEnabled ? 'Tracking ON' : 'Tracking OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lastLocation != null)
                  Text(
                    '${_lastLocation!.coords.latitude.toStringAsFixed(4)}, '
                    '${_lastLocation!.coords.longitude.toStringAsFixed(4)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.expand_more,
              color: Colors.white.withAlpha(179),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedView() {
    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusSection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildLocationSection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildBatterySection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildSyncQueueSection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildGeofenceSection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildActivitySection(),
                  const Divider(color: Colors.white24, height: 24),
                  _buildStatsSection(),
                  if (_locations.isNotEmpty) ...[
                    const Divider(color: Colors.white24, height: 24),
                    _buildRecentLocationsSection(),
                  ],
                ],
              ),
            ),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Locus Debug',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => _isExpanded = false),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Status'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatusChip(
                'Tracking',
                _isEnabled,
                Icons.gps_fixed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusChip(
                'Motion',
                _isMoving,
                Icons.directions_walk,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, bool active, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.green.withAlpha(51) : Colors.red.withAlpha(51),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label: ${active ? "ON" : "OFF"}',
              style: TextStyle(
                color: active ? Colors.green : Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Location'),
        const SizedBox(height: 8),
        if (_lastLocation != null) ...[
          _buildInfoRow(
            'Latitude',
            _lastLocation!.coords.latitude.toStringAsFixed(6),
          ),
          _buildInfoRow(
            'Longitude',
            _lastLocation!.coords.longitude.toStringAsFixed(6),
          ),
          _buildInfoRow(
            'Accuracy',
            '${_lastLocation!.coords.accuracy.toStringAsFixed(1)} m',
          ),
          _buildInfoRow(
            'Speed',
            '${((_lastLocation!.coords.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h',
          ),
          _buildInfoRow(
            'Heading',
            '${_lastLocation!.coords.heading?.toStringAsFixed(0) ?? '?'}°',
          ),
          _buildInfoRow(
            'Altitude',
            '${_lastLocation!.coords.altitude?.toStringAsFixed(1) ?? '?'} m',
          ),
        ] else
          const Text(
            'No location data yet',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
      ],
    );
  }

  Widget _buildActivitySection() {
    final activity = _lastLocation?.activity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Activity'),
        const SizedBox(height: 8),
        if (activity != null) ...[
          Row(
            children: [
              Icon(
                _getActivityIcon(activity.type),
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                activity.type.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${activity.confidence}%',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ] else
          const Text(
            'No activity data',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
      ],
    );
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.still:
        return Icons.accessibility_new;
      case ActivityType.walking:
      case ActivityType.onFoot:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.inVehicle:
        return Icons.directions_car;
      case ActivityType.onBicycle:
        return Icons.directions_bike;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildBatterySection() {
    final stats = _batteryStats;
    final runway = _batteryRunway;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Battery'),
        const SizedBox(height: 8),
        if (stats != null || runway != null) ...[
          Row(
            children: [
              Icon(
                _getBatteryIcon(
                  runway?.currentLevel ?? stats?.currentBatteryLevel ?? 50,
                  runway?.isCharging ?? stats?.isCharging ?? false,
                ),
                color: _getBatteryColor(
                  runway?.currentLevel ?? stats?.currentBatteryLevel ?? 50,
                ),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${runway?.currentLevel ?? stats?.currentBatteryLevel ?? '?'}%',
                style: TextStyle(
                  color: _getBatteryColor(
                    runway?.currentLevel ?? stats?.currentBatteryLevel ?? 50,
                  ),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (runway?.isCharging == true || stats?.isCharging == true) ...[
                const SizedBox(width: 4),
                const Icon(Icons.bolt, color: Colors.amber, size: 14),
              ],
            ],
          ),
          const SizedBox(height: 4),
          if (stats != null) ...[
            _buildInfoRow(
              'Optimization',
              stats.optimizationLevel.name,
            ),
            _buildInfoRow(
              'GPS On',
              '${stats.gpsOnTimePercent.toStringAsFixed(1)}%',
            ),
          ],
          if (runway != null) ...[
            _buildInfoRow(
              'Runway',
              _formatDuration(runway.duration),
            ),
            _buildInfoRow(
              'Confidence',
              '${(runway.confidence * 100).toInt()}%',
            ),
          ],
        ] else
          const Text(
            'No battery data',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
      ],
    );
  }

  IconData _getBatteryIcon(int level, bool isCharging) {
    if (isCharging) return Icons.battery_charging_full;
    if (level > 80) return Icons.battery_full;
    if (level > 50) return Icons.battery_5_bar;
    if (level > 20) return Icons.battery_3_bar;
    return Icons.battery_alert;
  }

  Color _getBatteryColor(int level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m';
  }

  Widget _buildSyncQueueSection() {
    final total = _syncSuccessCount + _syncFailureCount;
    final successRate = total > 0 ? (_syncSuccessCount / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Sync Queue'),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildMiniStat(
              'Pending',
              '$_pendingSyncCount',
              _pendingSyncCount > 0 ? Colors.amber : Colors.green,
            ),
            const SizedBox(width: 12),
            _buildMiniStat(
              'Success',
              '$_syncSuccessCount',
              Colors.green,
            ),
            const SizedBox(width: 12),
            _buildMiniStat(
              'Failed',
              '$_syncFailureCount',
              _syncFailureCount > 0 ? Colors.red : Colors.white54,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (total > 0)
          _buildInfoRow(
            'Success Rate',
            '${successRate.toStringAsFixed(1)}%',
          ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildGeofenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Geofences'),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.hexagon_outlined,
              color: _geofenceCount > 0 ? Colors.blue : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '$_geofenceCount active',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildInfoRow('Events', '$_geofenceEventCount'),
      ],
    );
  }

  Widget _buildStatsSection() {
    final locationsPerMinute = _locationTimestamps.length.toDouble();
    final trackingDuration = _trackingStartTime != null
        ? DateTime.now().difference(_trackingStartTime!)
        : Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Stats'),
        const SizedBox(height: 8),
        _buildInfoRow(
          'Odometer',
          '${(_odometer / 1000).toStringAsFixed(2)} km',
        ),
        _buildInfoRow('Locations', '$_locationCount'),
        _buildInfoRow(
          'Loc/min',
          locationsPerMinute.toStringAsFixed(1),
        ),
        if (trackingDuration.inMinutes > 0)
          _buildInfoRow(
            'Tracking',
            _formatDuration(trackingDuration),
          ),
        if (_lastLocation != null)
          _buildInfoRow(
            'Last Update',
            _formatTime(_lastLocation!.timestamp),
          ),
      ],
    );
  }

  Widget _buildRecentLocationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Recent (${_locations.length})'),
        const SizedBox(height: 8),
        ...(_locations.take(5).map((loc) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    _formatTime(loc.timestamp),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${loc.coords.latitude.toStringAsFixed(4)}, ${loc.coords.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ))),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: _isEnabled ? Icons.stop : Icons.play_arrow,
            label: _isEnabled ? 'Stop' : 'Start',
            onPressed: () async {
              if (_isEnabled) {
                await Locus.stop();
              } else {
                await Locus.start();
              }
            },
          ),
          _buildControlButton(
            icon: Icons.my_location,
            label: 'Current',
            onPressed: () async {
              final location = await Locus.getCurrentPosition();
              if (mounted) {
                setState(() => _lastLocation = location);
              }
            },
          ),
          _buildControlButton(
            icon: Icons.refresh,
            label: 'Reset',
            onPressed: () {
              setState(() {
                _locations.clear();
                _locationCount = 0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withAlpha(179),
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
