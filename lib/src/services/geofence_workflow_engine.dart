library;

import 'dart:async';
import 'dart:convert';

import 'package:locus/src/events/events.dart';
import 'package:locus/src/models/models.dart';

/// Abstraction for workflow state persistence.
abstract class WorkflowStateStore {
  /// Saves serialized workflow state.
  Future<void> save(String key, String jsonData);

  /// Loads serialized workflow state.
  Future<String?> load(String key);

  /// Removes persisted workflow state.
  Future<void> remove(String key);
}

class GeofenceWorkflowEngine {
  GeofenceWorkflowEngine({
    required Stream<GeolocationEvent<dynamic>> events,
    this.stateStore,
  }) : _events = events;

  final Stream<GeolocationEvent<dynamic>> _events;
  final StreamController<GeofenceWorkflowEvent> _controller =
      StreamController<GeofenceWorkflowEvent>.broadcast();

  /// Optional state store for persistence.
  final WorkflowStateStore? stateStore;

  static const _stateStoreKey = 'locus_workflow_states';

  final Map<String, GeofenceWorkflow> _workflows = {};
  final Map<String, _WorkflowRuntimeState> _states = {};
  StreamSubscription<GeolocationEvent<dynamic>>? _subscription;

  Stream<GeofenceWorkflowEvent> get events => _controller.stream;

  void registerWorkflows(List<GeofenceWorkflow> workflows) {
    for (final workflow in workflows) {
      _workflows[workflow.id] = workflow;
      _states.putIfAbsent(workflow.id, () => _WorkflowRuntimeState(workflow));
    }
  }

  void clearWorkflows() {
    _workflows.clear();
    _states.clear();
  }

  GeofenceWorkflowState? getState(String workflowId) {
    final runtime = _states[workflowId];
    return runtime?.snapshot();
  }

  /// Saves current workflow states to persistent storage.
  Future<void> saveState() async {
    if (stateStore == null) return;

    final statesData = <String, Map<String, dynamic>>{};
    for (final entry in _states.entries) {
      statesData[entry.key] = entry.value.toMap();
    }

    await stateStore!.save(_stateStoreKey, jsonEncode(statesData));
  }

  /// Loads workflow states from persistent storage.
  ///
  /// Call this after [registerWorkflows] to restore previous state.
  Future<void> loadState() async {
    if (stateStore == null) return;

    final jsonData = await stateStore!.load(_stateStoreKey);
    if (jsonData == null) return;

    try {
      final statesData = jsonDecode(jsonData) as Map<String, dynamic>;

      for (final entry in statesData.entries) {
        final workflow = _workflows[entry.key];
        if (workflow == null) continue;

        final stateMap = entry.value as Map<String, dynamic>;
        final runtime = _states[entry.key];
        runtime?.restoreFromMap(stateMap);
      }
    } catch (_) {
      // Invalid stored state - clear it
      await clearPersistedState();
    }
  }

  /// Clears persisted workflow state.
  Future<void> clearPersistedState() async {
    await stateStore?.remove(_stateStoreKey);
  }

  void start() {
    _subscription?.cancel();
    _subscription = _events.listen(_handleEvent);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    // Save state before disposing
    await saveState();
    stop();
    await _controller.close();
  }

  void _handleEvent(GeolocationEvent<dynamic> event) {
    if (event.type != EventType.geofence) {
      return;
    }
    if (event.data is! GeofenceEvent) {
      return;
    }
    final geofenceEvent = event.data as GeofenceEvent;
    for (final workflow in _workflows.values) {
      final runtime = _states[workflow.id];
      if (runtime == null) {
        continue;
      }
      final candidates = runtime.matchingSteps(geofenceEvent);
      for (final step in candidates) {
        // Check cooldown FIRST - this applies even to already-completed steps
        // to detect rapid re-triggering within cooldown period
        if (!runtime.isStepAllowed(step)) {
          _emitViolation(runtime, step, 'Cooldown not elapsed');
          continue;
        }

        // If already completed and cooldown passed, just skip (no violation)
        if (runtime.isCompletedStep(step)) {
          continue;
        }

        if (workflow.requireSequence && !runtime.isNextStep(step)) {
          _emitViolation(runtime, step, 'Out of sequence');
          continue;
        }

        runtime.completeStep(step);
        final status = runtime.isCompleted
            ? GeofenceWorkflowStatus.completed
            : GeofenceWorkflowStatus.inProgress;
        _controller.add(GeofenceWorkflowEvent(
          workflowId: workflow.id,
          status: status,
          state: runtime.snapshot(),
          step: step,
          timestamp: DateTime.now().toUtc(),
        ));
        break; // Process one step per event per workflow
      }
    }
  }

  void _emitViolation(
    _WorkflowRuntimeState runtime,
    GeofenceWorkflowStep step,
    String message,
  ) {
    _controller.add(GeofenceWorkflowEvent(
      workflowId: runtime.workflow.id,
      status: GeofenceWorkflowStatus.violation,
      state: runtime.snapshot(),
      step: step,
      timestamp: DateTime.now().toUtc(),
      message: message,
    ));
  }
}

class _WorkflowRuntimeState {
  _WorkflowRuntimeState(this.workflow)
      : currentIndex = 0,
        completedStepIds = <String>{};

  final GeofenceWorkflow workflow;
  int currentIndex;
  final Set<String> completedStepIds;
  final Map<String, DateTime> _lastCompletedAt = {};

  bool get isCompleted => completedStepIds.length >= workflow.steps.length;

  GeofenceWorkflowState snapshot() {
    return GeofenceWorkflowState(
      workflowId: workflow.id,
      currentIndex: currentIndex,
      completedStepIds: completedStepIds.toList(),
      completed: isCompleted,
    );
  }

  List<GeofenceWorkflowStep> matchingSteps(GeofenceEvent event) {
    return workflow.steps
        .where((step) =>
            step.geofenceIdentifier == event.geofence.identifier &&
            step.action == event.action)
        .toList();
  }

  bool isNextStep(GeofenceWorkflowStep step) {
    if (currentIndex >= workflow.steps.length) {
      return false;
    }
    return workflow.steps[currentIndex].id == step.id;
  }

  bool isCompletedStep(GeofenceWorkflowStep step) {
    return completedStepIds.contains(step.id);
  }

  bool isStepAllowed(GeofenceWorkflowStep step) {
    final cooldown = step.cooldownSeconds;
    if (cooldown <= 0) {
      return true;
    }
    final lastCompleted = _lastCompletedAt[step.id];
    if (lastCompleted == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(lastCompleted).inSeconds >=
        cooldown;
  }

  void completeStep(GeofenceWorkflowStep step) {
    completedStepIds.add(step.id);
    _lastCompletedAt[step.id] = DateTime.now().toUtc();

    if (workflow.requireSequence) {
      // For sequential workflows, only advance if this is the expected next step
      if (currentIndex < workflow.steps.length &&
          workflow.steps[currentIndex].id == step.id) {
        currentIndex += 1;
      }
    } else {
      // For non-sequential workflows, update currentIndex to reflect progress
      // Find the step's position and update if it's further than current
      final stepIndex = workflow.steps.indexWhere((s) => s.id == step.id);
      if (stepIndex >= 0 && stepIndex >= currentIndex) {
        currentIndex = stepIndex + 1;
      }
    }
  }

  /// Serializes runtime state to a map for persistence.
  Map<String, dynamic> toMap() {
    return {
      'currentIndex': currentIndex,
      'completedStepIds': completedStepIds.toList(),
      'lastCompletedAt': _lastCompletedAt.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
    };
  }

  /// Restores runtime state from a persisted map.
  void restoreFromMap(Map<String, dynamic> map) {
    currentIndex = (map['currentIndex'] as num?)?.toInt() ?? 0;

    final completedIds = map['completedStepIds'] as List<dynamic>?;
    if (completedIds != null) {
      completedStepIds.clear();
      for (final id in completedIds) {
        completedStepIds.add(id as String);
      }
    }

    final lastCompletedMap = map['lastCompletedAt'] as Map<String, dynamic>?;
    if (lastCompletedMap != null) {
      _lastCompletedAt.clear();
      for (final entry in lastCompletedMap.entries) {
        final dt = DateTime.tryParse(entry.value as String);
        if (dt != null) {
          _lastCompletedAt[entry.key] = dt;
        }
      }
    }
  }
}
