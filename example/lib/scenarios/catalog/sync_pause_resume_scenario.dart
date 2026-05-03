import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// How long to wait after each pause/resume call so the
/// `pauseChanges` stream has a chance to emit before we move on. The SDK's
/// pause-state controller debounces nothing, so 500ms is generous and keeps
/// the scenario well under its 8s budget.
const Duration _kPauseStateSettleDelay = Duration(milliseconds: 500);

/// Scenario: data-sync pause and resume round-trip.
///
/// Guards against pause-state-stream regressions tracked by issue #35:
///
///   * Calling [SyncService.pause] must publish a `pause_state_changed`
///     event whose `payload['isPaused']` is `true`.
///   * Calling [SyncService.resume] must publish a subsequent
///     `pause_state_changed` event whose `payload['isPaused']` is `false`.
///   * The synchronous [SyncService.isPaused] getter must reflect the
///     `false` state once the round-trip completes.
///
/// Past regressions broke the round-trip in two distinct ways: (a) a 401
/// auto-pause path swallowed the explicit `app` pause without emitting a
/// state-change event, and (b) the resume codepath updated the in-memory
/// flag but never pushed the new state onto `pauseChanges`, leaving any
/// reactive UI ("sync paused — tap to retry") stuck on `true` forever.
class SyncPauseResumeScenario implements Scenario {
  @override
  String get id => 'sync-pause-resume';

  @override
  String get displayName => 'Sync pause and resume';

  @override
  ScenarioCategory get category => ScenarioCategory.sync;

  @override
  Duration get expectedDuration => const Duration(seconds: 8);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => false;

  @override
  String get description =>
      'Drives Locus.dataSync.pause() then Locus.dataSync.resume() and asserts '
      'both calls publish a pause_state_changed event with the right isPaused '
      'payload, and that the synchronous isPaused getter reads false at the '
      'end. Protects the reactive pauseChanges stream documented in issue #35: '
      'a regression that updates the internal flag without firing the stream '
      'leaves UIs that subscribe to pauseChanges (e.g. "sync paused — tap to '
      'retry" banners) stuck in a stale state with no recovery path short of '
      'an app restart.';

  @override
  Future<void> setup(ScenarioContext ctx) async {
    // Best-effort: if a previous scenario or external interaction left sync
    // paused, lift the pause so we observe a clean false → true → false
    // transition instead of an ambiguous true → true → false.
    if (Locus.dataSync.isPaused) {
      await Locus.dataSync.resume();
      await Future<void>.delayed(_kPauseStateSettleDelay);
    }
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    await Locus.dataSync.pause();
    ctx.log('dataSync_pause_called');
    await Future<void>.delayed(_kPauseStateSettleDelay);

    await Locus.dataSync.resume();
    ctx.log('dataSync_resume_called');
    await Future<void>.delayed(_kPauseStateSettleDelay);
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final List<RecordedEvent> trace = ctx.recorder.since(ctx.startedAt);

    final List<RecordedEvent> pauseStateEvents = trace
        .where((RecordedEvent e) =>
            e.category == EventCategory.sync && e.type == 'pause_state_changed')
        .toList(growable: false);

    final int pausedTrueIndex = pauseStateEvents.indexWhere(
      (RecordedEvent e) => e.payload['isPaused'] == true,
    );
    final int pausedFalseAfterTrueIndex = pausedTrueIndex < 0
        ? -1
        : pauseStateEvents.indexWhere(
            (RecordedEvent e) => e.payload['isPaused'] == false,
            pausedTrueIndex + 1,
          );

    final List<AssertionResult> results = <AssertionResult>[];

    if (pausedTrueIndex >= 0) {
      results.add(
        const AssertionResult.pass(
          'A pause_state_changed(isPaused: true) event was published after '
          'Locus.dataSync.pause()',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'A pause_state_changed(isPaused: true) event was published after '
          'Locus.dataSync.pause()',
          failureDetail:
              'No pause_state_changed event with isPaused=true was found in '
              'the recorder slice. Total pause_state_changed events recorded: '
              '${pauseStateEvents.length}. Likely cause: the pause() codepath '
              'updates internal state but skips the broadcast on '
              'SyncService.pauseChanges.',
          expected: '>=1 pause_state_changed event with isPaused=true',
          actual: '${pauseStateEvents.length} pause_state_changed events, '
              'none with isPaused=true',
        ),
      );
    }

    if (pausedFalseAfterTrueIndex >= 0) {
      results.add(
        const AssertionResult.pass(
          'A subsequent pause_state_changed(isPaused: false) event was '
          'published after Locus.dataSync.resume()',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'A subsequent pause_state_changed(isPaused: false) event was '
          'published after Locus.dataSync.resume()',
          failureDetail:
              'No pause_state_changed event with isPaused=false was found '
              'after the isPaused=true event. resume() may have updated the '
              'in-memory flag without re-publishing on pauseChanges (issue #35).',
          expected: 'pause_state_changed(isPaused: false) after the '
              'isPaused: true transition',
          actual: 'pauseStateEvents.length=${pauseStateEvents.length}, '
              'pausedTrueIndex=$pausedTrueIndex, '
              'pausedFalseAfterTrueIndex=$pausedFalseAfterTrueIndex',
        ),
      );
    }

    if (!Locus.dataSync.isPaused) {
      results.add(
        const AssertionResult.pass(
          'Locus.dataSync.isPaused reads false after the pause/resume '
          'round-trip',
        ),
      );
    } else {
      results.add(
        const AssertionResult.fail(
          'Locus.dataSync.isPaused reads false after the pause/resume '
          'round-trip',
          failureDetail:
              'Locus.dataSync.isPaused still reads true after resume() '
              'returned. resume() may have failed silently or been overridden '
              'by an HTTP 401/403 auto-pause that landed mid-scenario.',
          expected: false,
          actual: true,
        ),
      );
    }

    return results;
  }

  @override
  Future<void> teardown(ScenarioContext ctx) async {
    try {
      if (Locus.dataSync.isPaused) {
        await Locus.dataSync.resume();
      }
    } on Object catch (error) {
      ctx.log(
        'teardown_resume_failed',
        payload: <String, Object?>{'error': error.toString()},
      );
    }
  }
}
