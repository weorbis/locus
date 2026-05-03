import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/info_row.dart';
import 'package:locus_example/demos/widgets/section_header.dart';

String adaptiveTrackingLabel(AdaptiveTrackingConfig? config) {
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

/// Battery level / charging summary + benchmark control.
class BatteryStatusCard extends StatelessWidget {
  const BatteryStatusCard({
    super.key,
    required this.powerState,
    required this.batteryStats,
    required this.lastPowerEvent,
    required this.benchmarkStatus,
    required this.onRefresh,
    required this.onToggleBenchmark,
  });

  final PowerState? powerState;
  final BatteryStats? batteryStats;
  final PowerStateChangeEvent? lastPowerEvent;
  final String? benchmarkStatus;
  final VoidCallback onRefresh;
  final VoidCallback onToggleBenchmark;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.battery_charging_full_rounded,
              title: 'Battery',
              trailing: powerState != null
                  ? Text(
                      '${powerState!.batteryLevel}%',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            if (batteryStats != null) ...[
              InfoRow(
                icon: Icons.gps_fixed,
                label: 'GPS On Time',
                value:
                    '${(batteryStats!.gpsOnTimePercent * 100).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 8),
            ],
            if (powerState != null)
              InfoRow(
                icon: Icons.power,
                label: 'Charging',
                value: powerState!.isCharging ? 'Yes' : 'No',
              ),
            if (lastPowerEvent != null)
              InfoRow(
                icon: Icons.power_settings_new,
                label: 'Last Power Change',
                value: lastPowerEvent!.changeType.name,
              ),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: onRefresh,
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onToggleBenchmark,
                    icon: benchmarkStatus != null
                        ? Icons.stop_rounded
                        : Icons.speed_rounded,
                    label: benchmarkStatus ?? 'Benchmark',
                    color: benchmarkStatus != null ? Colors.red : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Adaptive-tracking selector and runway estimation card.
class AdaptiveTrackingCard extends StatelessWidget {
  const AdaptiveTrackingCard({
    super.key,
    required this.config,
    required this.adaptiveSettings,
    required this.batteryRunway,
    required this.onSetConfig,
    required this.onCalculateSettings,
    required this.onEstimateRunway,
  });

  final AdaptiveTrackingConfig? config;
  final AdaptiveSettings? adaptiveSettings;
  final BatteryRunway? batteryRunway;
  final void Function(AdaptiveTrackingConfig config, String label) onSetConfig;
  final VoidCallback onCalculateSettings;
  final VoidCallback onEstimateRunway;

  @override
  Widget build(BuildContext _) {
    final label = adaptiveTrackingLabel(config);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
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
                  child: ActionButton(
                    onPressed: () => onSetConfig(
                        AdaptiveTrackingConfig.balanced, 'Balanced'),
                    icon: Icons.tune,
                    label: 'Balanced',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: () => onSetConfig(
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
                  child: ActionButton(
                    onPressed: () => onSetConfig(
                        AdaptiveTrackingConfig.disabled, 'Disabled'),
                    icon: Icons.power_settings_new,
                    label: 'Disable',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onCalculateSettings,
                    icon: Icons.tune,
                    label: 'Calc Settings',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActionButton(
              onPressed: onEstimateRunway,
              icon: Icons.timelapse,
              label: 'Estimate Runway',
              filled: true,
            ),
            if (adaptiveSettings != null) ...[
              const SizedBox(height: 16),
              InfoRow(
                icon: Icons.my_location_outlined,
                label: 'Accuracy',
                value: adaptiveSettings!.desiredAccuracy.name,
              ),
              InfoRow(
                icon: Icons.linear_scale,
                label: 'Distance Filter',
                value:
                    '${adaptiveSettings!.distanceFilter.toStringAsFixed(0)} m',
              ),
              InfoRow(
                icon: Icons.favorite_border,
                label: 'Heartbeat',
                value: '${adaptiveSettings!.heartbeatInterval}s',
              ),
            ],
            if (batteryRunway != null) ...[
              const SizedBox(height: 12),
              InfoRow(
                icon: Icons.battery_full_rounded,
                label: 'Runway',
                value: batteryRunway!.formattedDuration,
              ),
              InfoRow(
                icon: Icons.battery_2_bar_rounded,
                label: 'Low Power',
                value: batteryRunway!.formattedLowPowerDuration,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
