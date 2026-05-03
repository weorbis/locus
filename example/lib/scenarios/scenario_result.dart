import 'package:flutter/foundation.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/scenarios/assertion_result.dart';

enum ScenarioRunStatus {
  /// All assertions passed.
  passed,

  /// At least one assertion failed.
  failed,

  /// Scenario threw mid-phase (setup/execute/verify/teardown).
  errored,

  /// User aborted the run before assertions ran.
  cancelled,
}

/// Aggregate output of one scenario run, suitable for display, JSON export
/// and bug-report attachment.
@immutable
class ScenarioResult {
  ScenarioResult({
    required this.scenarioId,
    required this.displayName,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required List<AssertionResult> assertions,
    required List<RecordedEvent> trace,
    this.error,
    this.errorPhase,
  })  : assertions = List.unmodifiable(assertions),
        trace = List.unmodifiable(trace);

  final String scenarioId;
  final String displayName;
  final DateTime startedAt;
  final DateTime finishedAt;
  final ScenarioRunStatus status;
  final List<AssertionResult> assertions;

  /// Slice of the recorder buffer captured between [startedAt] and
  /// [finishedAt]. Attached to results so a failed scenario produces a
  /// self-contained report — the runner UI and JSON exporter both read
  /// from here, not from the live recorder.
  final List<RecordedEvent> trace;

  /// String form of the exception when [status] is [ScenarioRunStatus.errored].
  final String? error;

  /// Which phase threw. One of `setup` / `execute` / `verify` / `teardown`.
  final String? errorPhase;

  Duration get duration => finishedAt.difference(startedAt);

  int get passedCount =>
      assertions.where((a) => a.status == AssertionStatus.pass).length;
  int get failedCount =>
      assertions.where((a) => a.status == AssertionStatus.fail).length;
  int get skippedCount =>
      assertions.where((a) => a.status == AssertionStatus.skip).length;

  Map<String, Object?> toJson() => <String, Object?>{
        'scenarioId': scenarioId,
        'displayName': displayName,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'finishedAt': finishedAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'status': status.name,
        'assertions': assertions.map((a) => a.toJson()).toList(),
        'trace': trace.map((e) => e.toJson()).toList(),
        if (error != null) 'error': error,
        if (errorPhase != null) 'errorPhase': errorPhase,
      };
}
