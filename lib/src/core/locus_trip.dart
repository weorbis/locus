import 'dart:async';
import 'package:locus/src/events/events.dart';
// import 'package:flutter/services.dart'; // Unused
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'locus_channels.dart';
import 'locus_streams.dart';

// Private implementation of TripStore using MethodChannel
class _MethodChannelTripStore implements TripStore {
  @override
  Future<void> save(TripState state) async {
    // Renamed from saveTripState
    await LocusChannels.methods.invokeMethod('storeTripState', state.toMap());
  }

  @override
  Future<TripState?> load() async {
    // Renamed from loadTripState
    final result = await LocusChannels.methods.invokeMethod('readTripState');
    if (result is Map) {
      return TripState.fromMap(Map<String, dynamic>.from(result));
    }
    return null;
  }

  @override
  Future<void> clear() async {
    // Renamed from clearTripState
    await LocusChannels.methods.invokeMethod('clearTripState');
  }
}

/// Trip lifecycle management.
class LocusTrip {
  static TripEngine? _tripEngine;
  static final TripStore _tripStore = _MethodChannelTripStore();

  /// Starts a trip lifecycle engine with the provided config.
  static Future<void> startTrip(TripConfig config) async {
    _tripEngine ??= TripEngine(store: _tripStore);
    await _tripEngine!.start(config, _tripLocationStream());
  }

  /// Stops the active trip and returns a summary if available.
  static TripSummary? stopTrip() {
    return _tripEngine?.stop();
  }

  /// Returns the current trip state if a trip is active.
  static TripState? getTripState() => _tripEngine?.state;

  /// Stream of trip lifecycle events.
  static Stream<TripEvent> get tripEvents {
    _tripEngine ??= TripEngine(store: _tripStore);
    return _tripEngine!.events;
  }

  static Stream<Location> _tripLocationStream() {
    return LocusStreams.events
        .where((event) =>
            event.type == EventType.location ||
            event.type == EventType.motionChange ||
            event.type == EventType.heartbeat ||
            event.type == EventType.schedule)
        .map((event) => event.data)
        .where((data) => data is Location)
        .cast<Location>();
  }

  /// Disposes resources.
  static Future<void> dispose() async {
    await _tripEngine?.dispose();
    _tripEngine = null;
  }
}
