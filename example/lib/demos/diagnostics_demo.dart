import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/info_row.dart';
import 'package:locus_example/demos/widgets/section_header.dart';

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

String _formatLocation(Location loc) {
  return '${loc.coords.latitude.toStringAsFixed(5)}, ${loc.coords.longitude.toStringAsFixed(5)} (±${loc.coords.accuracy.toStringAsFixed(0)}m)';
}

/// Stored locations card — load / clear plus a preview list of the latest
/// stored points.
class StoredLocationsCard extends StatelessWidget {
  const StoredLocationsCard({
    super.key,
    required this.locations,
    required this.onLoad,
    required this.onClear,
  });

  final List<Location> locations;
  final VoidCallback onLoad;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
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
                      '${locations.length}',
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
                      child: ActionButton(
                        onPressed: onLoad,
                        icon: Icons.download_rounded,
                        label: 'Load',
                        filled: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionButton(
                        onPressed: onClear,
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
        if (locations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: locations.length.clamp(0, 20),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final loc = locations[i];
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
      ],
    );
  }
}

/// Logs card — fetches recent SDK log entries on demand.
class LogsCard extends StatelessWidget {
  const LogsCard({
    super.key,
    required this.logs,
    required this.onLoad,
  });

  final List<LogEntry>? logs;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.article_outlined,
              title: 'Logs',
              trailing: logs != null
                  ? Text(
                      '${logs!.length} entries',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            ActionButton(
              onPressed: onLoad,
              icon: Icons.refresh_rounded,
              label: 'Load Logs',
              filled: true,
            ),
            if (logs != null && logs!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  logs!.take(10).map((e) {
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
    );
  }
}

/// History summary card (last-N-hours stats).
class HistorySummaryCard extends StatelessWidget {
  const HistorySummaryCard({
    super.key,
    required this.summary,
    required this.onLoad,
  });

  final LocationSummary? summary;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.insights_rounded,
              title: 'History Summary',
              trailing: summary != null
                  ? Text(
                      '${summary!.locationCount} pts',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            ActionButton(
              onPressed: onLoad,
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
              InfoRow(
                icon: Icons.straighten_rounded,
                label: 'Distance',
                value: _formatDistance(summary!.totalDistanceMeters),
              ),
              InfoRow(
                icon: Icons.directions_walk_rounded,
                label: 'Moving',
                value:
                    '${_formatDuration(summary!.movingDuration)} (${summary!.movingPercent.toStringAsFixed(0)}%)',
              ),
              InfoRow(
                icon: Icons.pause_circle_outline,
                label: 'Stationary',
                value: _formatDuration(summary!.stationaryDuration),
              ),
              if (summary!.averageAccuracyMeters != null)
                InfoRow(
                  icon: Icons.gps_fixed,
                  label: 'Avg Accuracy',
                  value:
                      '${summary!.averageAccuracyMeters!.toStringAsFixed(0)} m',
                ),
              InfoRow(
                icon: Icons.place_outlined,
                label: 'Frequent Spots',
                value: '${summary!.frequentLocations.length}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Diagnostics snapshot card — captures and surfaces queue / state info.
class DiagnosticsCard extends StatelessWidget {
  const DiagnosticsCard({
    super.key,
    required this.snapshot,
    required this.onCapture,
  });

  final DiagnosticsSnapshot? snapshot;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.health_and_safety_outlined,
              title: 'Diagnostics',
              trailing: snapshot != null
                  ? Text(
                      snapshot!.capturedAt
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            ActionButton(
              onPressed: onCapture,
              icon: Icons.health_and_safety_outlined,
              label: 'Capture Snapshot',
              filled: true,
            ),
            if (snapshot != null) ...[
              const SizedBox(height: 16),
              InfoRow(
                icon: Icons.queue,
                label: 'Queue Size',
                value: '${snapshot!.queue.length}',
              ),
              if (snapshot!.state != null)
                InfoRow(
                  icon: Icons.play_circle_outline,
                  label: 'Tracking',
                  value: snapshot!.state!.enabled ? 'On' : 'Off',
                ),
              if (snapshot!.state?.isMoving != null)
                InfoRow(
                  icon: Icons.directions_walk_rounded,
                  label: 'Moving',
                  value: snapshot!.state!.isMoving ? 'Yes' : 'No',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Monitoring + automation switches and pace controls.
class MonitoringCard extends StatelessWidget {
  const MonitoringCard({
    super.key,
    required this.automationEnabled,
    required this.qualityMonitoringEnabled,
    required this.anomalyMonitoringEnabled,
    required this.spoofDetectionEnabled,
    required this.significantChangesEnabled,
    required this.lastQuality,
    required this.lastAnomaly,
    required this.onToggleAutomation,
    required this.onToggleQuality,
    required this.onToggleAnomaly,
    required this.onToggleSpoof,
    required this.onToggleSignificant,
    required this.onSetPace,
    required this.onResetOdometer,
  });

  final bool automationEnabled;
  final bool qualityMonitoringEnabled;
  final bool anomalyMonitoringEnabled;
  final bool spoofDetectionEnabled;
  final bool significantChangesEnabled;
  final LocationQuality? lastQuality;
  final LocationAnomaly? lastAnomaly;
  final VoidCallback onToggleAutomation;
  final VoidCallback onToggleQuality;
  final VoidCallback onToggleAnomaly;
  final VoidCallback onToggleSpoof;
  final VoidCallback onToggleSignificant;
  final ValueChanged<bool> onSetPace;
  final VoidCallback onResetOdometer;

  @override
  Widget build(BuildContext context) {
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
            value: automationEnabled,
            onChanged: (_) => onToggleAutomation(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality),
            title: const Text('Quality Monitoring'),
            subtitle: const Text('Assess signal quality'),
            value: qualityMonitoringEnabled,
            onChanged: (_) => onToggleQuality(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.report_problem_outlined),
            title: const Text('Anomaly Detection'),
            subtitle: const Text('Detect implausible jumps'),
            value: anomalyMonitoringEnabled,
            onChanged: (_) => onToggleAnomaly(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.security_rounded),
            title: const Text('Spoof Detection'),
            subtitle: const Text('Detect mock locations'),
            value: spoofDetectionEnabled,
            onChanged: (_) => onToggleSpoof(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.compare_arrows_rounded),
            title: const Text('Significant Changes'),
            subtitle: const Text('Ultra-low power monitoring'),
            value: significantChangesEnabled,
            onChanged: (_) => onToggleSignificant(),
          ),
          if (lastQuality != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.insights_rounded,
                    label: 'Quality Score',
                    value:
                        '${(lastQuality!.overallScore * 100).toStringAsFixed(0)}%',
                  ),
                  InfoRow(
                    icon: Icons.speed_rounded,
                    label: 'Jitter',
                    value:
                        '${(lastQuality!.jitterScore * 100).toStringAsFixed(0)}%',
                  ),
                  InfoRow(
                    icon: Icons.shield_outlined,
                    label: 'Spoof Suspect',
                    value: lastQuality!.isSpoofSuspected ? 'Yes' : 'No',
                  ),
                ],
              ),
            ),
          ],
          if (lastAnomaly != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: InfoRow(
                icon: Icons.warning_rounded,
                label: 'Last Anomaly',
                value: '${lastAnomaly!.speedKph.toStringAsFixed(0)} kph',
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: () => onSetPace(true),
                    icon: Icons.directions_walk_rounded,
                    label: 'Set Moving',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: () => onSetPace(false),
                    icon: Icons.do_not_disturb_on_outlined,
                    label: 'Set Stationary',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onResetOdometer,
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
}

/// Counts of recorded SDK events grouped by type — surfaced as a chip wrap.
class EventStatsCard extends StatelessWidget {
  const EventStatsCard({super.key, required this.eventCounts});

  final Map<String, int> eventCounts;

  @override
  Widget build(BuildContext context) {
    final sorted = eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
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
}

/// Scrollable event log — header (with count + clear) plus the list view.
class EventsView extends StatelessWidget {
  const EventsView({
    super.key,
    required this.events,
    required this.onClear,
  });

  final List<String> events;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${events.length} events',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
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
                  itemCount: events.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFF0F0F0),
                      child: Icon(Icons.circle, size: 8, color: Colors.grey),
                    ),
                    title: Text(
                      events[i],
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
}
