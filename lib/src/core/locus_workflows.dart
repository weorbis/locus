import 'dart:async';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'locus_streams.dart';

/// Geofence Workflows management.
class LocusWorkflows {
  static GeofenceWorkflowEngine? _workflowEngine;

  static Stream<GeofenceWorkflowEvent> get workflowEvents {
    _workflowEngine ??= GeofenceWorkflowEngine(events: LocusStreams.events);
    return _workflowEngine!.events;
  }

  static void registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) {
    _workflowEngine ??= GeofenceWorkflowEngine(events: LocusStreams.events);
    _workflowEngine!.registerWorkflows(workflows);
    _workflowEngine!.start();
  }

  static GeofenceWorkflowState? getWorkflowState(String workflowId) {
    return _workflowEngine?.getState(workflowId);
  }

  static void clearGeofenceWorkflows() {
    _workflowEngine?.clearWorkflows();
  }

  static void stopGeofenceWorkflows() {
    _workflowEngine?.stop();
  }

  static Future<void> dispose() async {
    await _workflowEngine?.dispose();
    _workflowEngine = null;
  }
}
