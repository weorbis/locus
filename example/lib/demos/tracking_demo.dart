import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/info_row.dart';
import 'package:locus_example/demos/widgets/profile_chip.dart';
import 'package:locus_example/demos/widgets/section_header.dart';
import 'package:locus_example/demos/widgets/status_indicator.dart';

/// Snapshot of tracking state forwarded to [TrackingStatusCard].
class TrackingStatusData {
  const TrackingStatusData({
    required this.isReady,
    required this.isRunning,
    required this.lastState,
    required this.latestLocation,
    required this.lastActivity,
    required this.lastConnectivity,
  });

  final bool isReady;
  final bool isRunning;
  final GeolocationState? lastState;
  final Location? latestLocation;
  final Activity? lastActivity;
  final ConnectivityChangeEvent? lastConnectivity;
}

/// Top-of-dashboard card that summarises tracking state, activity, and
/// network connectivity.
class TrackingStatusCard extends StatelessWidget {
  const TrackingStatusCard({super.key, required this.data});

  final TrackingStatusData data;

  String _formatLocation(Location loc) {
    return '${loc.coords.latitude.toStringAsFixed(5)}, ${loc.coords.longitude.toStringAsFixed(5)} (±${loc.coords.accuracy.toStringAsFixed(0)}m)';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusIndicator(active: data.isReady, label: 'Ready'),
                const SizedBox(width: 12),
                StatusIndicator(active: data.isRunning, label: 'Tracking'),
                const SizedBox(width: 12),
                StatusIndicator(
                  active: data.lastState?.isMoving ?? false,
                  label: data.lastState?.isMoving == true
                      ? 'Moving'
                      : 'Stationary',
                ),
              ],
            ),
            if (data.latestLocation != null) ...[
              const Divider(height: 32),
              InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: _formatLocation(data.latestLocation!),
              ),
            ],
            if (data.lastActivity != null)
              InfoRow(
                icon: Icons.directions_walk_rounded,
                label: 'Activity',
                value:
                    '${data.lastActivity!.type.name} (${data.lastActivity!.confidence}%)',
              ),
            if (data.lastConnectivity != null)
              InfoRow(
                icon: Icons.wifi_rounded,
                label: 'Network',
                value: data.lastConnectivity!.connected ? 'Online' : 'Offline',
              ),
            if (data.lastState?.odometer != null)
              InfoRow(
                icon: Icons.straighten_rounded,
                label: 'Odometer',
                value: '${data.lastState!.odometer!.toStringAsFixed(0)} m',
              ),
          ],
        ),
      ),
    );
  }
}

/// Start/stop, position lookup, and notification controls.
class TrackingControlsCard extends StatelessWidget {
  const TrackingControlsCard({
    super.key,
    required this.isRunning,
    required this.onToggleTracking,
    required this.onGetPosition,
    required this.onUpdateNotification,
  });

  final bool isRunning;
  final VoidCallback onToggleTracking;
  final VoidCallback onGetPosition;
  final VoidCallback onUpdateNotification;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.play_circle_outline,
              title: 'Tracking',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: onToggleTracking,
                    icon: isRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    label: isRunning ? 'Stop' : 'Start',
                    color: isRunning ? Colors.red : Colors.green,
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onGetPosition,
                    icon: Icons.my_location_rounded,
                    label: 'Get Position',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActionButton(
              onPressed: isRunning ? onUpdateNotification : null,
              icon: Icons.notifications_active_rounded,
              label: 'Update Notification',
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile selector (off-duty / standby / en-route / arrived).
class TrackingProfileCard extends StatelessWidget {
  const TrackingProfileCard({
    super.key,
    required this.currentProfile,
    required this.onSelect,
  });

  final TrackingProfile? currentProfile;
  final ValueChanged<TrackingProfile> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.tune_rounded,
              title: 'Profile',
              trailing: currentProfile != null
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
                        currentProfile!.name,
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
                ProfileChip(
                  label: 'Off Duty',
                  icon: Icons.bedtime_outlined,
                  selected: currentProfile == TrackingProfile.offDuty,
                  onTap: () => onSelect(TrackingProfile.offDuty),
                ),
                ProfileChip(
                  label: 'Standby',
                  icon: Icons.pause_circle_outline,
                  selected: currentProfile == TrackingProfile.standby,
                  onTap: () => onSelect(TrackingProfile.standby),
                ),
                ProfileChip(
                  label: 'En Route',
                  icon: Icons.navigation_outlined,
                  selected: currentProfile == TrackingProfile.enRoute,
                  onTap: () => onSelect(TrackingProfile.enRoute),
                ),
                ProfileChip(
                  label: 'Arrived',
                  icon: Icons.flag_outlined,
                  selected: currentProfile == TrackingProfile.arrived,
                  onTap: () => onSelect(TrackingProfile.arrived),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
