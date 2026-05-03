import 'package:flutter/material.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/section_header.dart';
import 'package:locus_example/demos/widgets/status_indicator.dart';

/// Geofencing controls — circular adds/clears live in the Quick Actions
/// grid; this card focuses on polygons and workflow registration.
class GeofencingDemoCard extends StatelessWidget {
  const GeofencingDemoCard({
    super.key,
    required this.polygonCount,
    required this.workflowRegistered,
    required this.lastWorkflowEvent,
    required this.onAddPolygon,
    required this.onClearPolygons,
    required this.onRegisterWorkflow,
    required this.onClearWorkflows,
  });

  final int polygonCount;
  final bool workflowRegistered;
  final GeofenceWorkflowEvent? lastWorkflowEvent;
  final VoidCallback onAddPolygon;
  final VoidCallback onClearPolygons;
  final VoidCallback onRegisterWorkflow;
  final VoidCallback onClearWorkflows;

  @override
  Widget build(BuildContext context) {
    final workflowStatus = lastWorkflowEvent?.status.name ?? 'idle';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.map_outlined,
              title: 'Geofencing',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                StatusIndicator(
                  active: polygonCount > 0,
                  label: 'Polygons $polygonCount',
                ),
                const SizedBox(width: 12),
                StatusIndicator(
                  active: workflowRegistered,
                  label: workflowRegistered ? 'Workflow $workflowStatus' : 'No',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: onAddPolygon,
                    icon: Icons.crop_square_rounded,
                    label: 'Add Polygon',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onClearPolygons,
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
                  child: ActionButton(
                    onPressed: onRegisterWorkflow,
                    icon: Icons.route,
                    label: 'Register Flow',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onClearWorkflows,
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
}
