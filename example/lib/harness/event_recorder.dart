import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locus_example/harness/recorded_event.dart';

/// Fixed-size, append-only event buffer that subscribes to every SDK stream
/// the harness cares about and exposes:
///
///   * a stable, JSON-exportable history (the last [capacity] entries),
///   * a broadcast stream of new entries for live-render UIs,
///   * `whereCategory` / `since` views used by scenarios to assert.
///
/// The recorder owns its subscriptions: callers must invoke [dispose] to
/// release them. A single recorder is meant to live for the lifetime of the
/// example app — not per scenario — so the entire run is captured.
abstract class EventRecorder implements Listenable {
  /// Bounded history capacity. When exceeded, oldest entries are evicted
  /// in FIFO order.
  int get capacity;

  /// Total entries recorded since [start] (monotonic, can exceed [capacity]).
  int get totalRecorded;

  /// Current contents of the ring buffer, oldest first. Returned as an
  /// unmodifiable view so callers can iterate without copying.
  List<RecordedEvent> get events;

  /// Broadcast stream of newly-appended entries. Late subscribers do not
  /// receive prior history — read [events] for that.
  Stream<RecordedEvent> get appended;

  /// Begins listening to SDK streams. Idempotent; subsequent calls are
  /// no-ops while the recorder is already active.
  Future<void> start();

  /// Cancels SDK subscriptions but preserves accumulated [events] so an
  /// exporter can still read them. Idempotent.
  Future<void> stop();

  /// Manually appends an event. Used by scenarios and UI components to
  /// inject markers (`scenario_started`, `manual_step_acknowledged`).
  void record(RecordedEvent event);

  /// Convenience: appends an event with `now` timestamp.
  void log(
    EventCategory category,
    String type, {
    Map<String, Object?>? payload,
    String? sourceId,
  });

  /// Drops all accumulated events. Subscriptions remain active.
  void clear();

  /// Filtered view: events from a single category, oldest first.
  List<RecordedEvent> whereCategory(EventCategory category);

  /// Filtered view: events at or after [from], oldest first. Exclusive of
  /// the boundary is intentional — scenarios pass their own `started_at`.
  List<RecordedEvent> since(DateTime from);

  /// Releases all subscriptions and stream controllers. After dispose the
  /// recorder is unusable.
  Future<void> dispose();
}
