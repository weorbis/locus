import 'package:flutter/material.dart';
import 'package:locus_example/demos/widgets/action_button.dart';
import 'package:locus_example/demos/widgets/section_header.dart';

/// Trip start / stop controls. The full trip lifecycle (route recording,
/// summary persistence) is handled by the SDK; this card just exposes the
/// imperative actions.
class TripsDemoCard extends StatelessWidget {
  const TripsDemoCard({
    super.key,
    required this.onStartTrip,
    required this.onStopTrip,
  });

  final VoidCallback onStartTrip;
  final VoidCallback onStopTrip;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.trip_origin_rounded,
              title: 'Trips',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    onPressed: onStartTrip,
                    icon: Icons.play_arrow_rounded,
                    label: 'Start Trip',
                    filled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActionButton(
                    onPressed: onStopTrip,
                    icon: Icons.stop_rounded,
                    label: 'Stop Trip',
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
