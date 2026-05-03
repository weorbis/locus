/// Default in-process implementation of [EventRecorder].
///
/// Subscribes to every public Locus stream the harness cares about, normalises
/// each entry into a [RecordedEvent], and keeps a fixed-size FIFO history that
/// is safe to read during a widget rebuild.
///
/// The recorder satisfies [Listenable] (delegated to a private
/// [ChangeNotifier]) so widgets can rebuild via
/// `AnimatedBuilder(animation: recorder, ...)` without subscribing to the
/// broadcast `appended` stream. Both surfaces fire on the same single
/// append path; either is a valid integration choice.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/recorded_event.dart';

/// Concrete [EventRecorder] used by the example app and integration tests.
///
/// Constructed once at app entry and shared down through the widget tree.
/// Call [start] before the first scenario runs and [dispose] when the app
/// shuts down. Both methods are idempotent.
///
/// Implements [Listenable] via a private [ChangeNotifier] delegate rather
/// than mixing in `ChangeNotifier` directly: the abstract interface requires
/// `Future<void> dispose()`, but `ChangeNotifier.dispose()` is `void` — the
/// signatures are incompatible, so we compose instead of inherit.
class DefaultEventRecorder implements EventRecorder {
  /// Creates a recorder with the given [capacity] (default 5000).
  ///
  /// [capacity] must be positive. Older entries are evicted in FIFO order
  /// once the buffer fills.
  DefaultEventRecorder({this.capacity = 5000})
      : assert(capacity > 0, 'capacity must be positive');

  @override
  final int capacity;

  // Listenable delegate. Forwarded explicitly via [addListener] /
  // [removeListener]; we never expose this object outside the class.
  // Subclassing exposes `notifyListeners` (which is `@protected` on the
  // base) so the recorder can fire it from within the same library.
  final _RecorderNotifier _notifier = _RecorderNotifier();

  // Plain `List` so `events` returns indexable order without copying. Using
  // `Queue` would force `toList()` per render.
  final List<RecordedEvent> _buffer = <RecordedEvent>[];

  final StreamController<RecordedEvent> _appended =
      StreamController<RecordedEvent>.broadcast();

  // Type-erased to `dynamic` because Dart generic streams are invariant —
  // `StreamSubscription<Location>` is not assignable to
  // `StreamSubscription<Object?>`. We only ever call `.cancel()` on these,
  // so the lost type information is harmless.
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  int _totalRecorded = 0;
  bool _started = false;
  bool _disposed = false;

  // Listenable forwarding ----------------------------------------------------

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);

  @override
  int get totalRecorded => _totalRecorded;

  @override
  List<RecordedEvent> get events =>
      List<RecordedEvent>.unmodifiable(_buffer);

  @override
  Stream<RecordedEvent> get appended => _appended.stream;

  // ============================================================
  // Lifecycle
  // ============================================================

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('DefaultEventRecorder.start() after dispose()');
    }
    if (_started) return;
    _started = true;

    _subscribe<Location>(
      streamName: 'Locus.location.stream',
      stream: () => Locus.location.stream,
      handler: (loc) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.location,
          type: 'location_update',
          payload: _locationPayload(loc),
        ),
      ),
    );

    _subscribe<GeofenceEvent>(
      streamName: 'Locus.geofencing.events',
      stream: () => Locus.geofencing.events,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.geofence,
          type: 'geofence_${event.action.name}',
          payload: _safeMap(event.toMap),
        ),
      ),
    );

    _subscribe<PolygonGeofenceEvent>(
      streamName: 'Locus.geofencing.polygonEvents',
      stream: () => Locus.geofencing.polygonEvents,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.geofence,
          type: 'polygon_${event.type.name}',
          payload: _safeMap(event.toMap),
        ),
      ),
    );

    // `Locus.dataSync.events` is `Stream<HttpEvent>`. The SDK does not emit a
    // separate "queue" variant on this surface in the current branch — every
    // event here corresponds to an HTTP request/response. Categorise as
    // `http`. If the SDK later splits the stream, this is the place to add
    // the discriminator.
    _subscribe<HttpEvent>(
      streamName: 'Locus.dataSync.events',
      stream: () => Locus.dataSync.events,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.http,
          type: event.ok ? 'http_response_ok' : 'http_response_error',
          payload: _safeMap(event.toMap),
        ),
      ),
    );

    _subscribe<ConnectivityChangeEvent>(
      streamName: 'Locus.dataSync.connectivityEvents',
      stream: () => Locus.dataSync.connectivityEvents,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.sync,
          type: 'connectivity_${event.connected ? 'online' : 'offline'}',
          payload: _safeMap(event.toMap),
        ),
      ),
    );

    _subscribe<SyncPauseState>(
      streamName: 'Locus.dataSync.pauseChanges',
      stream: () => Locus.dataSync.pauseChanges,
      handler: (state) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.sync,
          type: 'pause_state_changed',
          payload: <String, Object?>{
            'isPaused': state.isPaused,
            if (state.reason != null) 'reason': state.reason,
          },
        ),
      ),
    );

    _subscribe<PowerStateChangeEvent>(
      streamName: 'Locus.battery.powerStateEvents',
      stream: () => Locus.battery.powerStateEvents,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.lifecycle,
          type: 'power_state_${event.changeType.name}',
          payload: _safeMap(event.toMap),
        ),
      ),
    );

    _subscribe<LocusReliabilityEvent>(
      streamName: 'Locus.reliability',
      stream: () => Locus.reliability,
      handler: (event) => record(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.error,
          type: 'reliability_${event.runtimeType}',
          payload: _reliabilityPayload(event),
        ),
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    final pending = List<StreamSubscription<dynamic>>.from(_subs);
    _subs.clear();
    for (final sub in pending) {
      await sub.cancel();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    if (!_appended.isClosed) {
      await _appended.close();
    }
    _notifier.dispose();
  }

  // ============================================================
  // Public mutation API — all paths funnel through `_append`.
  // ============================================================

  @override
  void record(RecordedEvent event) => _append(event);

  @override
  void log(
    EventCategory category,
    String type, {
    Map<String, Object?>? payload,
    String? sourceId,
  }) {
    _append(
      RecordedEvent(
        at: DateTime.now(),
        category: category,
        type: type,
        payload: payload,
        sourceId: sourceId,
      ),
    );
  }

  @override
  void clear() {
    if (_buffer.isEmpty) return;
    _buffer.clear();
    _notifier.notify();
  }

  // ============================================================
  // Filtered views — return fresh lists so callers can iterate safely
  // even while the buffer is being mutated by an inbound stream event.
  // ============================================================

  @override
  List<RecordedEvent> whereCategory(EventCategory category) {
    final out = <RecordedEvent>[];
    for (final event in _buffer) {
      if (event.category == category) out.add(event);
    }
    return out;
  }

  @override
  List<RecordedEvent> since(DateTime from) {
    final out = <RecordedEvent>[];
    for (final event in _buffer) {
      if (event.at.isAfter(from)) out.add(event);
    }
    return out;
  }

  // ============================================================
  // Internals
  // ============================================================

  /// Single append path — handles eviction, broadcast, and notification.
  /// All public mutators must funnel through here.
  void _append(RecordedEvent event) {
    if (_disposed) return;
    _buffer.add(event);
    _totalRecorded++;
    if (_buffer.length > capacity) {
      _buffer.removeRange(0, _buffer.length - capacity);
    }
    if (!_appended.isClosed) {
      _appended.add(event);
    }
    _notifier.notify();
  }

  /// Subscribes to [stream]. If the getter throws (e.g. the SDK build does
  /// not expose this stream on this branch), records a single warn-level
  /// `subscription_failed` event and continues — a missing stream must not
  /// crash recorder construction.
  void _subscribe<T>({
    required String streamName,
    required Stream<T> Function() stream,
    required void Function(T event) handler,
  }) {
    Stream<T> resolved;
    try {
      resolved = stream();
    } on Object catch (error, stack) {
      _append(
        RecordedEvent(
          at: DateTime.now(),
          category: EventCategory.error,
          type: 'subscription_failed',
          payload: <String, Object?>{
            'stream': streamName,
            'error': error.toString(),
            'stack': stack.toString(),
          },
          sourceId: 'event_recorder',
        ),
      );
      return;
    }

    final sub = resolved.listen(
      handler,
      onError: (Object error, StackTrace stack) {
        _append(
          RecordedEvent(
            at: DateTime.now(),
            category: EventCategory.error,
            type: 'stream_error',
            payload: <String, Object?>{
              'stream': streamName,
              'error': error.toString(),
              'stack': stack.toString(),
            },
            sourceId: 'event_recorder',
          ),
        );
      },
      cancelOnError: false,
    );
    _subs.add(sub);
  }

  /// Builds a JSON-friendly payload for a [Location].
  Map<String, Object?> _locationPayload(Location loc) {
    final map = _safeMap(loc.toMap);
    if (map.isNotEmpty) return map;
    // Hand-built fallback if the SDK ever changes shape unexpectedly.
    return <String, Object?>{
      'uuid': loc.uuid,
      'timestamp': loc.timestamp.toIso8601String(),
      'latitude': loc.coords.latitude,
      'longitude': loc.coords.longitude,
      'accuracy': loc.coords.accuracy,
      'isMoving': loc.isMoving,
    };
  }

  /// Pulls a JSON map for a sealed reliability event without depending on a
  /// `toMap` (none is exposed on the public type at the time of writing).
  Map<String, Object?> _reliabilityPayload(LocusReliabilityEvent event) {
    final base = <String, Object?>{
      'occurredAt': event.occurredAt.toIso8601String(),
    };
    switch (event) {
      case PointsEvicted(:final count, :final reason):
        base['count'] = count;
        base['reason'] = reason.name;
      case QuarantineGrew(:final totalQuarantined, :final reasonHint):
        base['totalQuarantined'] = totalQuarantined;
        if (reasonHint != null) base['reasonHint'] = reasonHint;
      case QuarantinePurged(:final count, :final olderThan):
        base['count'] = count;
        base['olderThanSeconds'] = olderThan.inSeconds;
      case SyncStalled(
          :final sinceLastSuccess,
          :final consecutiveFailures,
          :final lastHttpStatus,
          :final lastErrorClass,
        ):
        base['sinceLastSuccessSeconds'] = sinceLastSuccess.inSeconds;
        base['consecutiveFailures'] = consecutiveFailures;
        if (lastHttpStatus != null) base['lastHttpStatus'] = lastHttpStatus;
        base['lastErrorClass'] = lastErrorClass.name;
      case SyncUnrecoverable(
          :final sinceLastSuccess,
          :final consecutiveFailures,
          :final lastHttpStatus,
          :final lastErrorClass,
        ):
        base['sinceLastSuccessSeconds'] = sinceLastSuccess.inSeconds;
        base['consecutiveFailures'] = consecutiveFailures;
        if (lastHttpStatus != null) base['lastHttpStatus'] = lastHttpStatus;
        base['lastErrorClass'] = lastErrorClass.name;
      case PersistenceFailure(:final operation, :final message):
        base['operation'] = operation;
        base['message'] = message;
    }
    return base;
  }

  /// Calls a `toMap()` defensively — the harness must never crash on a
  /// malformed SDK payload. The SDK boundary returns
  /// `Map<String, dynamic>` (its `JsonMap` typedef); we widen it to
  /// `Map<String, Object?>` once, here, and the rest of the harness stays
  /// strict. Falls back to a single-entry error map on failure.
  Map<String, Object?> _safeMap(Map<String, dynamic> Function() toMap) {
    try {
      final raw = toMap();
      return <String, Object?>{
        for (final entry in raw.entries) entry.key: entry.value as Object?,
      };
    } on Object catch (error) {
      return <String, Object?>{
        'serializationError': error.toString(),
      };
    }
  }
}

/// Private subclass that re-exposes [ChangeNotifier.notifyListeners] under
/// the public name [notify] so [DefaultEventRecorder] can fire it via the
/// composed delegate without bumping into the `@protected` annotation on
/// the base method.
class _RecorderNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
