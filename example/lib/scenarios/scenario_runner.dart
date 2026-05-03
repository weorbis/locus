import 'dart:async';

import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';
import 'package:locus_example/scenarios/scenario_result.dart';

/// Names of the phases the runner walks every [Scenario] through. Kept as
/// constants so log payloads and `errorPhase` strings stay consistent.
///
/// Teardown is not represented here because teardown failures are recorded
/// as scenario events but never propagated as `errorPhase` — they must not
/// mask the original verdict.
class _Phase {
  static const String setup = 'setup';
  static const String execute = 'execute';
  static const String verify = 'verify';

  /// Synthetic phase used when a precondition (e.g. missing mock backend)
  /// stops the run before [Scenario.setup] is even invoked.
  static const String precondition = 'precondition';
}

/// Internal record of a phase outcome. Lets [ScenarioRunner.run] thread
/// failure information through a single linear flow without a tree of
/// nested try/catch blocks.
class _PhaseOutcome {
  const _PhaseOutcome({
    required this.cancelled,
    required this.errored,
    required this.errorPhase,
    required this.errorMessage,
  });

  const _PhaseOutcome.ok()
      : cancelled = false,
        errored = false,
        errorPhase = null,
        errorMessage = null;

  final bool cancelled;
  final bool errored;
  final String? errorPhase;
  final String? errorMessage;

  bool get failedHard => cancelled || errored;
}

/// Headless orchestrator for a single [Scenario] run.
///
/// The runner walks `setup -> execute -> verify -> teardown`, capturing the
/// recorder slice in between, and folds every possible outcome (pass, fail,
/// cancel, throw) into a [ScenarioResult]. It never throws to the caller and
/// never imports `package:flutter/widgets.dart` so it can be exercised under
/// pure Dart `flutter test` without a `WidgetTester`.
class ScenarioRunner {
  /// Builds a runner that records every scenario marker through [recorder]
  /// and exposes the optional [backend] to scenarios that need it.
  ScenarioRunner({required this.recorder, this.backend});

  /// Shared event log. Scenarios receive the same instance through their
  /// [ScenarioContext]; the runner uses it to stamp `scenario_started` /
  /// `scenario_finished` markers around each run.
  final EventRecorder recorder;

  /// Optional mock backend. Required iff a scenario sets
  /// [Scenario.requiresMockBackend].
  final MockBackend? backend;

  /// Runs a scenario from setup to teardown and produces a fully-populated
  /// [ScenarioResult]. Never throws — every failure is reflected in the
  /// returned [ScenarioResult.status] / [ScenarioResult.error] fields.
  ///
  /// [onManualStep] is invoked whenever the scenario calls
  /// [ScenarioContext.awaitManualStep]. The future returned by this method
  /// only completes after [onManualStep]'s future resolves (or throws
  /// [ScenarioCancelled]). If [onManualStep] throws [ScenarioCancelled] the
  /// run terminates with [ScenarioRunStatus.cancelled] but teardown still
  /// runs on a best-effort basis.
  Future<ScenarioResult> run(
    Scenario scenario, {
    required Future<void> Function(String prompt) onManualStep,
  }) async {
    final DateTime startedAt = DateTime.now().toUtc();

    // Scenario start marker — stamped before the precondition check so the
    // trace always shows that we attempted the run.
    recorder.log(
      EventCategory.scenario,
      'scenario_started',
      payload: <String, Object?>{
        'id': scenario.id,
        'displayName': scenario.displayName,
      },
      sourceId: scenario.id,
    );

    // Precondition: a scenario that needs a mock backend cannot run without
    // one. Bail before setup so we don't half-arrange the SDK.
    if (scenario.requiresMockBackend && backend == null) {
      const String message =
          'Scenario requires a mock backend but none was provided to the runner.';
      return _finalize(
        scenario: scenario,
        startedAt: startedAt,
        status: ScenarioRunStatus.errored,
        assertions: const <AssertionResult>[],
        errorPhase: _Phase.precondition,
        errorMessage: message,
      );
    }

    final ScenarioContext ctx = ScenarioContext(
      recorder: recorder,
      scenarioId: scenario.id,
      startedAt: startedAt,
      backend: backend,
      awaitManualStep: onManualStep,
    );

    // Phase 1: setup.
    final _PhaseOutcome setupOutcome =
        await _runPhase(_Phase.setup, () => scenario.setup(ctx));
    if (setupOutcome.failedHard) {
      await _safeTeardown(scenario, ctx);
      return _finalize(
        scenario: scenario,
        startedAt: startedAt,
        status: setupOutcome.cancelled
            ? ScenarioRunStatus.cancelled
            : ScenarioRunStatus.errored,
        assertions: const <AssertionResult>[],
        errorPhase: setupOutcome.errorPhase,
        errorMessage: setupOutcome.errorMessage,
      );
    }

    // Phase 2: execute.
    final _PhaseOutcome executeOutcome =
        await _runPhase(_Phase.execute, () => scenario.execute(ctx));
    if (executeOutcome.failedHard) {
      await _safeTeardown(scenario, ctx);
      return _finalize(
        scenario: scenario,
        startedAt: startedAt,
        status: executeOutcome.cancelled
            ? ScenarioRunStatus.cancelled
            : ScenarioRunStatus.errored,
        assertions: const <AssertionResult>[],
        errorPhase: executeOutcome.errorPhase,
        errorMessage: executeOutcome.errorMessage,
      );
    }

    // Phase 3: verify. We need the assertions list out of the closure, so
    // we use a local variable instead of the generic _runPhase helper.
    List<AssertionResult> assertions = const <AssertionResult>[];
    _PhaseOutcome verifyOutcome = const _PhaseOutcome.ok();
    try {
      assertions = await scenario.verify(ctx);
    } on ScenarioCancelled catch (e) {
      verifyOutcome = _PhaseOutcome(
        cancelled: true,
        errored: false,
        errorPhase: _Phase.verify,
        errorMessage: e.reason,
      );
    } catch (e, stack) {
      _logPhaseError(_Phase.verify, e, stack);
      verifyOutcome = _PhaseOutcome(
        cancelled: false,
        errored: true,
        errorPhase: _Phase.verify,
        errorMessage: e.toString(),
      );
    }

    if (verifyOutcome.failedHard) {
      await _safeTeardown(scenario, ctx);
      return _finalize(
        scenario: scenario,
        startedAt: startedAt,
        status: verifyOutcome.cancelled
            ? ScenarioRunStatus.cancelled
            : ScenarioRunStatus.errored,
        assertions: const <AssertionResult>[],
        errorPhase: verifyOutcome.errorPhase,
        errorMessage: verifyOutcome.errorMessage,
      );
    }

    // Phase 4: teardown. Always runs; teardown errors do not change the
    // pass/fail decision but are surfaced as scenario events.
    await _safeTeardown(scenario, ctx);

    final bool anyFailed =
        assertions.any((AssertionResult a) => a.status == AssertionStatus.fail);
    final ScenarioRunStatus status =
        anyFailed ? ScenarioRunStatus.failed : ScenarioRunStatus.passed;

    return _finalize(
      scenario: scenario,
      startedAt: startedAt,
      status: status,
      assertions: assertions,
      errorPhase: null,
      errorMessage: null,
    );
  }

  /// Runs a single phase closure and classifies its outcome. Logs the
  /// failure as a scenario event so the trace reflects what happened.
  Future<_PhaseOutcome> _runPhase(
    String phase,
    Future<void> Function() body,
  ) async {
    try {
      await body();
      return const _PhaseOutcome.ok();
    } on ScenarioCancelled catch (e) {
      recorder.log(
        EventCategory.scenario,
        'scenario_cancelled',
        payload: <String, Object?>{
          'phase': phase,
          'reason': e.reason,
        },
      );
      return _PhaseOutcome(
        cancelled: true,
        errored: false,
        errorPhase: phase,
        errorMessage: e.reason,
      );
    } catch (e, stack) {
      _logPhaseError(phase, e, stack);
      return _PhaseOutcome(
        cancelled: false,
        errored: true,
        errorPhase: phase,
        errorMessage: e.toString(),
      );
    }
  }

  void _logPhaseError(String phase, Object error, StackTrace stack) {
    recorder.log(
      EventCategory.scenario,
      'scenario_phase_error',
      payload: <String, Object?>{
        'phase': phase,
        'error': error.toString(),
        'stack': stack.toString(),
      },
    );
  }

  /// Runs teardown on a best-effort basis. Any throw is captured as a
  /// scenario event but does not propagate — teardown failures must never
  /// mask the original verdict.
  Future<void> _safeTeardown(Scenario scenario, ScenarioContext ctx) async {
    try {
      await scenario.teardown(ctx);
    } on ScenarioCancelled catch (e) {
      recorder.log(
        EventCategory.scenario,
        'scenario_teardown_cancelled',
        payload: <String, Object?>{'reason': e.reason},
      );
    } catch (e, stack) {
      recorder.log(
        EventCategory.scenario,
        'scenario_teardown_error',
        payload: <String, Object?>{
          'error': e.toString(),
          'stack': stack.toString(),
        },
      );
    }
  }

  /// Stamps the `scenario_finished` marker, captures the recorder slice and
  /// builds the [ScenarioResult]. Centralising this here guarantees every
  /// exit path goes through the same shape.
  ScenarioResult _finalize({
    required Scenario scenario,
    required DateTime startedAt,
    required ScenarioRunStatus status,
    required List<AssertionResult> assertions,
    required String? errorPhase,
    required String? errorMessage,
  }) {
    recorder.log(
      EventCategory.scenario,
      'scenario_finished',
      payload: <String, Object?>{
        'id': scenario.id,
        'status': status.name,
        if (errorPhase != null) 'errorPhase': errorPhase,
      },
      sourceId: scenario.id,
    );

    final DateTime finishedAt = DateTime.now().toUtc();
    final List<RecordedEvent> trace = recorder.since(startedAt);

    return ScenarioResult(
      scenarioId: scenario.id,
      displayName: scenario.displayName,
      startedAt: startedAt,
      finishedAt: finishedAt,
      status: status,
      assertions: assertions,
      trace: trace,
      error: errorMessage,
      errorPhase: errorPhase,
    );
  }
}
