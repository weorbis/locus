import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/section_header.dart';

/// Privacy zones list + manage controls.
class PrivacyZonesCard extends StatelessWidget {
  const PrivacyZonesCard({
    super.key,
    required this.zones,
    required this.onAdd,
    required this.onLoad,
    required this.onClear,
  });

  final List<PrivacyZone> zones;
  final VoidCallback onAdd;
  final VoidCallback onLoad;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final itemCount = zones.length > 4 ? 4 : zones.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
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
                  child: ActionButton(
                    onPressed: onAdd,
                    icon: Icons.add_rounded,
                    label: 'Add Demo',
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
}
