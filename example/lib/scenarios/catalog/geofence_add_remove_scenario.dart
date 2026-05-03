import 'dart:async';

import 'package:locus/locus.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Stable identifier for the geofence created and torn down by this
/// scenario. Centralised so setup/execute/teardown agree on the value.
const String _kFenceId = 'scenario-test-fence';

/// San Francisco anchor coords. Coordinates are arbitrary as long as they
/// are valid and stable — no tests depend on the actual position.
const double _kFenceLat = 37.7749;
const double _kFenceLng = -122.4194;
const double _kFenceRadiusMeters = 100.0;

/// Scenario: circular geofence add → list → remove → list round-trip.
///
/// Guards against the bug class where [GeofenceService.add] reports
/// `success`/`true` but [GeofenceService.getAll] does not include the
/// geofence (a divergence between the in-memory registry and the native
/// `GeofencingClient`), or where [GeofenceService.remove] succeeds but the
/// fence remains queryable. Both have shipped before during native-storage
/// migrations: the failure mode is silent — `add` returns true, the user
/// "sees" the fence registered, but enter/exit events never fire because
/// the registration silently failed inside the native client.
class GeofenceAddRemoveScenario implements Scenario {
  @override
  String get id => 'geofence-add-remove';

  @override
  String get displayName => 'Geofence add and remove round-trip';

  @override
  ScenarioCategory get category => ScenarioCategory.geofencing;

  @override
  Duration get expectedDuration => const Duration(seconds: 5);

  @override
  bool get requiresManualSteps => false;

  @override
  bool get requiresMockBackend => false;

  @override
  String get description =>
      'Adds a circular geofence, lists all fences, removes it, and re-lists. '
      'Asserts the post-add list contains exactly the fence that was just '
      'registered, and the post-remove list is empty. Protects against the '
      'silent-divergence bug class where add()/remove() report success but '
      'GeofencingClient state does not actually change — a fence that '
      'reports as registered but never fires enter/exit events because the '
      'native registration call failed mid-way through the migration.';

  @override
  Future<void> setup(ScenarioContext ctx) async {
    // GeofenceService does not currently expose a single `clear()` method;
    // `removeAll()` is the canonical bulk-remove entry point. Best-effort —
    // a fresh install may legitimately have nothing to remove.
    try {
      await Locus.geofencing.removeAll();
    } on Object catch (error) {
      ctx.log(
        'setup_removeAll_failed',
        payload: <String, Object?>{'error': error.toString()},
      );
    }

    // Sanity check: the harness expects an empty starting state. If the
    // platform refuses to drop everything (e.g. permissions revoked) we
    // surface a marker but let the assertions decide — the verify phase
    // is what gates the verdict.
    final List<Geofence> remaining = await Locus.geofencing.getAll();
    if (remaining.isNotEmpty) {
      ctx.log(
        'setup_starting_state_not_empty',
        payload: <String, Object?>{'count': remaining.length},
      );
    }
  }

  @override
  Future<void> execute(ScenarioContext ctx) async {
    const Geofence fence = Geofence(
      identifier: _kFenceId,
      latitude: _kFenceLat,
      longitude: _kFenceLng,
      radius: _kFenceRadiusMeters,
      notifyOnEntry: true,
    );
    await Locus.geofencing.add(fence);
    ctx.log('geofence_added', payload: <String, Object?>{'id': _kFenceId});

    final List<Geofence> afterAdd = await Locus.geofencing.getAll();
    ctx.log(
      'geofences_listed_after_add',
      payload: <String, Object?>{
        'count': afterAdd.length,
        'identifiers': <String>[
          for (final Geofence g in afterAdd) g.identifier,
        ],
      },
    );

    await Locus.geofencing.remove(_kFenceId);
    ctx.log('geofence_removed', payload: <String, Object?>{'id': _kFenceId});

    final List<Geofence> afterRemove = await Locus.geofencing.getAll();
    ctx.log(
      'geofences_listed_after_remove',
      payload: <String, Object?>{
        'count': afterRemove.length,
        'identifiers': <String>[
          for (final Geofence g in afterRemove) g.identifier,
        ],
      },
    );
  }

  @override
  Future<List<AssertionResult>> verify(ScenarioContext ctx) async {
    final List<RecordedEvent> trace = ctx.recorder.since(ctx.startedAt);
    final List<AssertionResult> results = <AssertionResult>[];

    // Re-read the live list so we are robust against the recorder buffer
    // having dropped our marker (capacity eviction, even though it's wildly
    // unlikely in a 5-second scenario).
    final List<Geofence> liveAfterRemove = await Locus.geofencing.getAll();

    // -------------------------------------------------------------------
    // Assertion 1: the post-add list must contain exactly the fence we
    // registered.
    // -------------------------------------------------------------------
    final RecordedEvent? postAddMarker = _firstWhereOrNull(
      trace,
      (RecordedEvent e) =>
          e.category == EventCategory.scenario &&
          e.type == 'geofences_listed_after_add',
    );

    if (postAddMarker == null) {
      results.add(
        const AssertionResult.fail(
          'Post-add list contains exactly the registered fence '
          '($_kFenceId)',
          failureDetail:
              'No geofences_listed_after_add marker was recorded — execute() '
              'did not reach the listing step. Likely an exception during '
              'add() or getAll(); inspect the trace for scenario_phase_error.',
        ),
      );
    } else {
      final Object? rawIds = postAddMarker.payload['identifiers'];
      final List<String> ids = rawIds is List
          ? <String>[
              for (final Object? id in rawIds)
                if (id is String) id,
            ]
          : const <String>[];
      final bool exactlyTheFence = ids.length == 1 && ids.single == _kFenceId;
      if (exactlyTheFence) {
        results.add(
          const AssertionResult.pass(
            'Post-add list contains exactly the registered fence '
            '($_kFenceId)',
          ),
        );
      } else {
        results.add(
          AssertionResult.fail(
            'Post-add list contains exactly the registered fence '
            '($_kFenceId)',
            failureDetail:
                'Expected a single fence with id "$_kFenceId" in the live '
                'registry after add(). Marker payload reported ids=$ids '
                '(count=${postAddMarker.payload['count']}). add() may have '
                'returned success without persisting to GeofencingClient.',
            expected: <String>[_kFenceId],
            actual: ids,
          ),
        );
      }
    }

    // -------------------------------------------------------------------
    // Assertion 2: the post-remove live list is empty.
    // -------------------------------------------------------------------
    if (liveAfterRemove.isEmpty) {
      results.add(
        const AssertionResult.pass(
          'Live geofence list is empty after remove($_kFenceId)',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'Live geofence list is empty after remove($_kFenceId)',
          failureDetail:
              'remove() returned but ${liveAfterRemove.length} fence(s) '
              'remain in the live registry: '
              '${liveAfterRemove.map((Geofence g) => g.identifier).toList()}. '
              'remove() may have returned success without dropping the '
              'native registration.',
          expected: 0,
          actual: liveAfterRemove.length,
        ),
      );
    }

    // -------------------------------------------------------------------
    // Assertion 3: no error-category events fired during execute.
    // -------------------------------------------------------------------
    final List<RecordedEvent> errors = trace
        .where((RecordedEvent e) => e.category == EventCategory.error)
        .toList(growable: false);
    if (errors.isEmpty) {
      results.add(
        const AssertionResult.pass(
          'No error-category events fired during the round-trip',
        ),
      );
    } else {
      results.add(
        AssertionResult.fail(
          'No error-category events fired during the round-trip',
          failureDetail: '${errors.length} error event(s) recorded; first: '
              '${errors.first.type} (${errors.first.payload})',
          expected: 0,
          actual: errors.length,
        ),
      );
    }

    return results;
  }

  @override
  Future<void> teardown(ScenarioContext ctx) async {
    // Idempotent best-effort: remove the fence again in case execute()
    // bailed before the explicit remove. Any "not found" error is expected
    // when execute completed cleanly; we capture every other failure as a
    // scenario marker but never propagate.
    try {
      await Locus.geofencing.remove(_kFenceId);
    } on Object catch (error) {
      final String message = error.toString();
      if (!message.toLowerCase().contains('not found')) {
        ctx.log(
          'teardown_remove_failed',
          payload: <String, Object?>{'error': message},
        );
      }
    }
  }
}

/// Mirrors the missing-from-Iterable `firstWhereOrNull` from package:collection
/// without taking a dependency. Returns `null` when no element matches.
RecordedEvent? _firstWhereOrNull(
  Iterable<RecordedEvent> source,
  bool Function(RecordedEvent) test,
) {
  for (final RecordedEvent event in source) {
    if (test(event)) return event;
  }
  return null;
}
