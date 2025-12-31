import '../common/json_map.dart';
import 'geofence_workflow_step.dart';

class GeofenceWorkflow {
  final String id;
  final List<GeofenceWorkflowStep> steps;
  final bool requireSequence;

  const GeofenceWorkflow({
    required this.id,
    required this.steps,
    this.requireSequence = true,
  });

  JsonMap toMap() => {
        'id': id,
        'requireSequence': requireSequence,
        'steps': steps.map((step) => step.toMap()).toList(),
      };
}
