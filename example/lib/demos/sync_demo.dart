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

String syncPolicyLabel(SyncPolicy policy) {
  if (identical(policy, SyncPolicy.aggressive)) return 'Aggressive';
  if (identical(policy, SyncPolicy.conservative)) return 'Conservative';
  if (identical(policy, SyncPolicy.minimal)) return 'Minimal';
  return 'Balanced';
}

/// Sync queue card — surfaces enqueue / load / sync / clear actions and
/// renders the most recent items.
class SyncQueueCard extends StatelessWidget {
  const SyncQueueCard({
    super.key,
    required this.queue,
    required this.lastQueueId,
    required this.onEnqueue,
    required this.onLoad,
    required this.onSyncNow,
    required this.onClear,
  });

  final List<QueueItem> queue;
  final String? lastQueueId;
  final VoidCallback onEnqueue;
  final VoidCallback onLoad;
  final VoidCallback onSyncNow;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final itemCount = queue.length > 5 ? 5 : queue.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.sync_rounded,
              title: 'Sync Queue',
              trailing: Text(
                '${queue.length} items',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: onEnqueue,
                    icon: Icons.add_rounded,
                    label: 'Enqueue',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onLoad,
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
                  child: ActionButton(
                    onPressed: onSyncNow,
                    icon: Icons.cloud_upload_outlined,
                    label: 'Sync Queue',
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
            if (lastQueueId != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last queued: $lastQueueId',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (queue.isNotEmpty) ...[
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemCount,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = queue[i];
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
}

/// Sync policy selector card.
class SyncPolicyCard extends StatelessWidget {
  const SyncPolicyCard({
    super.key,
    required this.currentPolicy,
    required this.lastDecision,
    required this.onSelectPolicy,
    required this.onEvaluate,
  });

  final SyncPolicy currentPolicy;
  final SyncDecision? lastDecision;
  final void Function(SyncPolicy policy, String label) onSelectPolicy;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final label = syncPolicyLabel(currentPolicy);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
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
                  child: ActionButton(
                    onPressed: () =>
                        onSelectPolicy(SyncPolicy.balanced, 'Balanced'),
                    icon: Icons.tune,
                    label: 'Balanced',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: () =>
                        onSelectPolicy(SyncPolicy.aggressive, 'Aggressive'),
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
                    onPressed: () =>
                        onSelectPolicy(SyncPolicy.conservative, 'Conservative'),
                    icon: Icons.slow_motion_video,
                    label: 'Conservative',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: () =>
                        onSelectPolicy(SyncPolicy.minimal, 'Minimal'),
                    icon: Icons.savings_outlined,
                    label: 'Minimal',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActionButton(
              onPressed: onEvaluate,
              icon: Icons.insights_rounded,
              label: 'Evaluate Policy',
              filled: true,
            ),
            if (lastDecision != null) ...[
              const SizedBox(height: 12),
              Text(
                lastDecision!.reason,
                style: const TextStyle(color: Colors.grey),
              ),
              if (lastDecision!.batchLimit != null)
                InfoRow(
                  icon: Icons.layers_outlined,
                  label: 'Batch Size',
                  value: '${lastDecision!.batchLimit}',
                ),
              if (lastDecision!.delay != null)
                InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Delay',
                  value: _formatDuration(lastDecision!.delay!),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sync context (shift / driver / route headers) selector.
class SyncContextCard extends StatelessWidget {
  const SyncContextCard({
    super.key,
    required this.context,
    required this.onApplyContext,
  });

  final Map<String, dynamic> context;
  final ValueChanged<Map<String, dynamic>> onApplyContext;

  @override
  Widget build(BuildContext _) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.badge_outlined,
              title: 'Sync Context',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: () => onApplyContext(const {
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
                  child: ActionButton(
                    onPressed: () => onApplyContext(const {
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
            InfoRow(
              icon: Icons.work_outline,
              label: 'Shift',
              value: context['shift_id']?.toString() ?? '-',
            ),
            InfoRow(
              icon: Icons.person_outline,
              label: 'Driver',
              value: context['driver_id']?.toString() ?? '-',
            ),
            InfoRow(
              icon: Icons.route,
              label: 'Route',
              value: context['route_id']?.toString() ?? '-',
            ),
          ],
        ),
      ),
    );
  }
}
