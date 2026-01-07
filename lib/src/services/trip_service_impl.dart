/// Trip service implementation for v2.0 API.
library;

import 'dart:async';

import 'package:locus/src/models.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/services/trip_service.dart';

/// Implementation of [TripService] using method channel.
class TripServiceImpl implements TripService {
  /// Creates a trip service with the given Locus interface provider.
  TripServiceImpl(this._instanceProvider);

  final LocusInterface Function() _instanceProvider;

  LocusInterface get _instance => _instanceProvider();

  @override
  Stream<TripEvent> get events => _instance.tripEvents;

  @override
  Future<void> start(TripConfig config) => _instance.startTrip(config);

  @override
  Future<TripSummary?>? stop() => _instance.stopTrip();

  @override
  TripState? getState() => _instance.getTripState();

  @override
  StreamSubscription<TripEvent> onEvent(
    void Function(TripEvent event) callback, {
    Function? onError,
  }) {
    return _instance.onTripEvent(callback, onError: onError);
  }
}
