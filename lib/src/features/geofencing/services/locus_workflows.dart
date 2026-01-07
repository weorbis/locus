import 'dart:async';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_streams.dart';

/// Geofence Workflows management.
class LocusWorkflows {
  static GeofenceWorkflowEngine? _workflowEngine;

  static Stream<GeofenceWorkflowEvent> get workflowEvents {
    _workflowEngine ??= GeofenceWorkflowEngine(events: LocusStreams.events);
    return _workflowEngine!.events;
  }

  static Future<void> registerGeofenceWorkflows(List<GeofenceWorkflow> workflows) async {
    _workflowEngine ??= GeofenceWorkflowEngine(events: LocusStreams.events);
    _workflowEngine!.registerWorkflows(workflows);
    await _workflowEngine!.start();
  }

  static GeofenceWorkflowState? getWorkflowState(String workflowId) {
    return _workflowEngine?.getState(workflowId);
  }

  static void clearGeofenceWorkflows() {
    _workflowEngine?.clearWorkflows();
  }

  static Future<void> stopGeofenceWorkflows() async {
    await _workflowEngine?.stop();
  }

  static Future<void> dispose() async {
    await _workflowEngine?.dispose();
    _workflowEngine = null;
  }
}
