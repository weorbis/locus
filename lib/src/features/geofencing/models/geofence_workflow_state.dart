import 'package:locus/src/shared/models/json_map.dart';

class GeofenceWorkflowState {
  final String workflowId;
  final int currentIndex;
  final List<String> completedStepIds;
  final bool completed;

  const GeofenceWorkflowState({
    required this.workflowId,
    required this.currentIndex,
    required this.completedStepIds,
    required this.completed,
  });

  JsonMap toMap() => {
        'workflowId': workflowId,
        'currentIndex': currentIndex,
        'completedStepIds': completedStepIds,
        'completed': completed,
      };
}
