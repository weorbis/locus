import 'geofence_workflow_state.dart';
import 'geofence_workflow_step.dart';

enum GeofenceWorkflowStatus {
  inProgress,
  completed,
  violation,
}

class GeofenceWorkflowEvent {
  final String workflowId;
  final GeofenceWorkflowStatus status;
  final GeofenceWorkflowState state;
  final GeofenceWorkflowStep? step;
  final DateTime timestamp;
  final String? message;

  const GeofenceWorkflowEvent({
    required this.workflowId,
    required this.status,
    required this.state,
    required this.timestamp,
    this.step,
    this.message,
  });
}
