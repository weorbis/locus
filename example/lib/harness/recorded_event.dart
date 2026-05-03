import 'package:flutter/foundation.dart';

/// Coarse classification used to filter and color the in-app event panel.
///
/// Kept intentionally small — these are display categories, not a typed
/// representation of the SDK's event surface. The narrower [RecordedEvent.type]
/// is what callers should match on programmatically.
enum EventCategory {
  /// Location updates and tracking lifecycle (`tracking_started`, `location`).
  location,

  /// Geofence enter/exit/dwell + polygon + workflow events.
  geofence,

  /// Sync-level events: queue activity, pause/resume, drain progression.
  sync,

  /// Per-request HTTP events emitted by the sync layer.
  http,

  /// Lifecycle/state-machine events (config applied, isolate boot, …).
  lifecycle,

  /// Anything raised by the SDK as a recoverable or fatal error, including
  /// reliability events (stalls, evictions, persistence failures).
  error,

  /// Events emitted *by* a scenario itself (`scenario_started`,
  /// `manual_step_acknowledged`). Distinguishes user intent from SDK output.
  scenario,
}

/// A single, fully-resolved entry in the in-app event log.
///
/// `RecordedEvent` is intentionally shape-agnostic about the SDK payload it
/// wraps — the harness consumes many disjoint streams (`Locus.location`,
/// `Locus.geofencing.events`, `Locus.dataSync.events`, …) and the only common
/// operations are: append, filter by time/category, export as JSON. A sealed
/// hierarchy across every SDK event type would be churn for no benefit at
/// this layer.
///
/// The `payload` map is the boundary between SDK-typed data and harness-
/// generic display: keys/values must be JSON-encodable so [toJson] is total.
@immutable
class RecordedEvent {
  RecordedEvent({
    required this.at,
    required this.category,
    required this.type,
    Map<String, Object?>? payload,
    this.sourceId,
  }) : payload = Map.unmodifiable(payload ?? const <String, Object?>{});

  /// When the event was observed by the harness (not the SDK's own
  /// timestamp, if any — that lives inside [payload] when relevant).
  final DateTime at;

  /// Display category. See [EventCategory] for the bucket meanings.
  final EventCategory category;

  /// Narrow event type. Conventionally `snake_case` so log diffs stay
  /// stable across emoji/casing fashions. Examples: `tracking_started`,
  /// `http_request`, `sync_paused`, `geofence_enter`.
  final String type;

  /// SDK-provided payload, JSON-encodable. Empty map when there's nothing
  /// useful to record beyond the type.
  final Map<String, Object?> payload;

  /// Optional identifier of the scenario or harness component that produced
  /// the event. Lets the UI / exporter group entries by emitter.
  final String? sourceId;

  /// Stable JSON shape for export and comparison (used in scenario verify).
  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'category': category.name,
        'type': type,
        if (sourceId != null) 'sourceId': sourceId,
        'payload': payload,
      };

  @override
  String toString() => 'RecordedEvent(${at.toIso8601String()} '
      '${category.name}/$type ${payload.isEmpty ? "" : payload})';
}
