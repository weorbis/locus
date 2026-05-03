import 'dart:async';

import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';

/// What the scenario primarily exercises. Used purely for grouping in the
/// runner UI; logic should not branch on this.
enum ScenarioCategory {
  /// Exercises tracking lifecycle, foreground service, headless tasks.
  lifecycle,

  /// Exercises sync queue, retry, pause/resume, drain.
  sync,

  /// Exercises HTTP layer behavior under adversarial backend responses.
  /// Requires the mock backend to be running.
  httpAdversarial,

  /// Exercises geofencing flows, including polygon and workflow engines.
  geofencing,

  /// Exercises battery / adaptive tracking transitions.
  battery,
}

/// Runtime context the runner hands every scenario phase. Anything a scenario
/// needs from the outside world — event log, mock backend, manual-step
/// acknowledgement — comes through here, never through globals.
class ScenarioContext {
  ScenarioContext({
    required this.recorder,
    required this.scenarioId,
    required this.startedAt,
    required this.awaitManualStep,
    this.backend,
  });

  /// The shared event recorder. Scenarios should `record(...)` markers via
  /// the recorder rather than logging directly to console.
  final EventRecorder recorder;

  /// Stable id of the running scenario. Mirrors [Scenario.id] and is the
  /// `sourceId` to attach to scenario-emitted events.
  final String scenarioId;

  /// Wall-clock time the scenario started (the call to `setup`). Used as
  /// the cutoff for `recorder.since(startedAt)` in `verify`.
  final DateTime startedAt;

  /// Mock backend instance, when one is required by this scenario. Phase 1
  /// scenarios leave this null; Phase 2 scenarios assert non-null in setup.
  final MockBackend? backend;

  /// Suspends until the human running the harness confirms a manual step
  /// (e.g. "swipe the app away from recents now"). The runner UI surfaces
  /// the prompt and resolves the future on tap.
  ///
  /// Throws [ScenarioCancelled] if the user aborts the scenario instead of
  /// confirming.
  final Future<void> Function(String prompt) awaitManualStep;

  /// Convenience: attach the scenario id to a scenario-authored log entry.
  /// Equivalent to `recorder.log(EventCategory.scenario, ...)` with
  /// `sourceId: scenarioId` filled in.
  void log(String type, {Map<String, Object?>? payload}) {
    recorder.log(
      EventCategory.scenario,
      type,
      payload: payload,
      sourceId: scenarioId,
    );
  }
}

/// Thrown to interrupt a scenario when the user aborts a pending manual step.
class ScenarioCancelled implements Exception {
  const ScenarioCancelled(this.reason);
  final String reason;
  @override
  String toString() => 'ScenarioCancelled: $reason';
}

/// A scripted, end-to-end exercise of one production-affecting code path.
///
/// Scenarios run through four phases. The runner enforces ordering and
/// always invokes [teardown] — even when a phase throws — so the next
/// scenario starts from a clean slate.
///
/// ```
///   setup()      arrange preconditions; cheap; no SDK action
///     ↓
///   execute()    drive the SDK / backend through the action under test
///     ↓
///   verify()     read the recorded events, return assertions
///     ↓
///   teardown()   undo whatever setup/execute did, even on failure
/// ```
abstract class Scenario {
  /// Stable, kebab-case identifier. Used as the `sourceId` on emitted events
  /// and (eventually) as the integration-test name. Must not change once a
  /// scenario ships, since bug reports reference it.
  String get id;

  /// Title shown in the runner list. Mutable across versions.
  String get displayName;

  /// One-paragraph rationale: which production-affecting bug class does
  /// this scenario protect, and how does it do so?
  String get description;

  ScenarioCategory get category;

  /// Best-effort wall-clock budget. The runner displays this; it does not
  /// time out automatically.
  Duration get expectedDuration;

  /// Whether this scenario requires the user to physically interact with
  /// the device (swipe app away, toggle airplane mode, etc.). Headless
  /// runners (integration_test) skip these by default.
  bool get requiresManualSteps;

  /// Whether [ScenarioContext.backend] must be non-null. The runner
  /// configures the mock backend before invoking [setup] when true.
  bool get requiresMockBackend;

  /// Arranges preconditions: clear queues, set initial config, position
  /// the mock backend in the right mode. Should not yet exercise the path
  /// under test.
  Future<void> setup(ScenarioContext ctx);

  /// Drives the action under test. May call [ScenarioContext.awaitManualStep]
  /// to block on human input.
  Future<void> execute(ScenarioContext ctx);

  /// Returns one [AssertionResult] per logical check. Reads
  /// `ctx.recorder.since(ctx.startedAt)` to inspect what happened during
  /// [execute]. Should not have side effects on the SDK or backend.
  Future<List<AssertionResult>> verify(ScenarioContext ctx);

  /// Undoes whatever was set up. Must be idempotent and tolerant of partial
  /// state — `setup` may have failed midway.
  Future<void> teardown(ScenarioContext ctx);
}
