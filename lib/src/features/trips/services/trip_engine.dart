library;

import 'dart:async';
import 'dart:math';
import 'package:locus/src/models.dart';
import 'package:locus/src/features/trips/services/trip_store.dart';
import 'package:locus/src/shared/location_utils.dart';

class TripEngine {
  TripEngine({TripStore? store}) : _store = store;

  final TripStore? _store;
  StreamSubscription<Location>? _subscription;
  final StreamController<TripEvent> _controller =
      StreamController<TripEvent>.broadcast();

  TripConfig? _config;
  TripState? _state;
  Location? _pendingStartLocation;
  DateTime? _lastUpdateAt;
  DateTime? _lastDeviationAt;
  DateTime? _lastStationaryAt;
  DateTime? _lastPersistAt;
  bool _dwellEmitted = false;

  Stream<TripEvent> get events => _controller.stream;
  TripState? get state => _state;

  Future<void> start(TripConfig config, Stream<Location> source) async {
    // Load persisted state first to decide if we can restore
    TripState? restored;
    if (_store != null) {
      restored = await _store!.load();
    }

    final shouldRestore = restored != null &&
        !restored.ended &&
        (config.tripId == null || config.tripId == restored.tripId);

    // If we are NOT restoring, we clean up any existing session fully
    if (!shouldRestore) {
      await stop();
    } else {
      // If restoring, just cancel the previous stream so we can re-bind
      await _subscription?.cancel();
      _subscription = null;
    }

    _config = config;

    if (shouldRestore) {
      _state = restored;
      // Preserve timing context from restored state to avoid losing
      // stationary duration and emitting duplicate dwell events.
      _lastUpdateAt = restored.lastLocation?.timestamp;
      _lastDeviationAt = null;
      _lastStationaryAt = null;
      _lastPersistAt = restored.lastLocation?.timestamp;
      _pendingStartLocation = null;
      // Keep _dwellEmitted false so dwell can still fire if threshold is met
      // after restore, but _lastStationaryAt being null means it won't
      // incorrectly fire until the device is actually detected stationary again.
      _dwellEmitted = false;
    } else {
      _pendingStartLocation = null;
      _lastUpdateAt = null;
      _lastDeviationAt = null;
      _lastStationaryAt = null;
      _lastPersistAt = null;
      _dwellEmitted = false;
      final tripId = config.tripId ?? _generateTripId();
      _state = TripState(
        tripId: tripId,
        createdAt: DateTime.now().toUtc(),
        startedAt: null,
        startLocation: null,
        lastLocation: null,
        distanceMeters: 0,
        idleSeconds: 0,
        maxSpeedKph: 0,
        started: false,
        ended: false,
      );
      await _persistState(force: true);
    }
    _subscription = source.listen(_handleLocation);
  }

  Future<TripSummary?> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final state = _state;
    _state = state == null
        ? null
        : TripState(
            tripId: state.tripId,
            createdAt: state.createdAt,
            startedAt: state.startedAt,
            startLocation: state.startLocation,
            lastLocation: state.lastLocation,
            distanceMeters: state.distanceMeters,
            idleSeconds: state.idleSeconds,
            maxSpeedKph: state.maxSpeedKph,
            started: state.started,
            ended: true,
          );
    if (state == null || !state.started) {
      return null;
    }
    final endedAt = DateTime.now().toUtc();
    final summary = state.toSummary(endedAt);
    if (summary != null) {
      _controller.add(TripEvent(
        type: TripEventType.tripEnd,
        tripId: state.tripId,
        timestamp: endedAt,
        location: state.lastLocation,
        summary: summary,
        isMoving: false,
      ));
    }
    await _store?.clear();
    return summary;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _handleLocation(Location location) async {
    final config = _config;
    final state = _state;
    if (config == null || state == null || state.ended) {
      return;
    }

    if (!state.started) {
      await _processStart(location, state, config);
      return;
    }

    await _processUpdate(location, state, config);
  }

  Future<void> _processStart(
    Location location,
    TripState state,
    TripConfig config,
  ) async {
    if (!config.startOnMoving) {
      await _beginTrip(location, state);
      return;
    }

    if (_pendingStartLocation == null) {
      _pendingStartLocation = location;
      return;
    }

    final previous = _pendingStartLocation!;
    final distance =
        LocationUtils.calculateDistance(previous.coords, location.coords);
    final speedKph = LocationUtils.calculateSpeedKph(
        distance, location.timestamp.difference(previous.timestamp));

    if (distance >= config.startDistanceMeters ||
        speedKph >= config.startSpeedKph) {
      await _beginTrip(location, state,
          startLocation: previous, initialDistance: distance);
      _pendingStartLocation = null;
      return;
    }

    _pendingStartLocation = location;
  }

  Future<void> _beginTrip(
    Location location,
    TripState state, {
    Location? startLocation,
    double initialDistance = 0,
  }) async {
    final startedAt = location.timestamp;
    final start = startLocation ?? location;
    _state = TripState(
      tripId: state.tripId,
      createdAt: state.createdAt,
      startedAt: startedAt,
      startLocation: start,
      lastLocation: location,
      distanceMeters: initialDistance,
      idleSeconds: 0,
      maxSpeedKph: 0,
      started: true,
      ended: false,
    );
    _lastUpdateAt = startedAt;
    _lastStationaryAt = null;
    _dwellEmitted = false;
    await _persistState(force: true);

    _controller.add(TripEvent(
      type: TripEventType.tripStart,
      tripId: state.tripId,
      timestamp: startedAt,
      location: location,
      isMoving: true,
    ));
  }

  Future<void> _processUpdate(
    Location location,
    TripState state,
    TripConfig config,
  ) async {
    final lastLocation = state.lastLocation ?? location;
    final deltaTime = location.timestamp.difference(lastLocation.timestamp);

    // Guard against out-of-order timestamps (e.g., device time changes)
    // Skip this update if timestamp is not newer than last location
    if (deltaTime.isNegative || deltaTime == Duration.zero) {
      // Emit diagnostic event for clock anomaly
      _controller.add(TripEvent.diagnostic(
        tripId: state.tripId,
        message: 'Clock anomaly detected',
        data: {
          'lastTimestamp': lastLocation.timestamp.toIso8601String(),
          'currentTimestamp': location.timestamp.toIso8601String(),
          'deltaMs': deltaTime.inMilliseconds,
          'action': 'skipped_update',
        },
      ));

      // If clock jumped backwards significantly (>1 hour), reset the trip's
      // last location timestamp to the current location to allow recovery
      if (deltaTime.inHours < -1) {
        _state = TripState(
          tripId: state.tripId,
          createdAt: state.createdAt,
          startedAt: state.startedAt,
          startLocation: state.startLocation,
          lastLocation: location, // Reset to current location
          distanceMeters: state.distanceMeters,
          idleSeconds: state.idleSeconds,
          maxSpeedKph: state.maxSpeedKph,
          started: state.started,
          ended: state.ended,
        );
        _controller.add(TripEvent.diagnostic(
          tripId: state.tripId,
          message: 'Trip state reset due to significant clock change',
          data: {'newBaseline': location.timestamp.toIso8601String()},
        ));
      }
      return;
    }

    final deltaDistance =
        LocationUtils.calculateDistance(lastLocation.coords, location.coords);
    final speedKph = LocationUtils.calculateSpeedKph(deltaDistance, deltaTime);
    final isMoving = location.isMoving ?? speedKph >= config.stationarySpeedKph;

    var idleSeconds = state.idleSeconds;
    if (!isMoving) {
      idleSeconds += max(0, deltaTime.inSeconds);
      _lastStationaryAt ??= location.timestamp;
    } else {
      _lastStationaryAt = null;
      _dwellEmitted = false;
    }

    final maxSpeed = max(state.maxSpeedKph, speedKph);
    final distanceMeters = state.distanceMeters + deltaDistance;

    _state = TripState(
      tripId: state.tripId,
      createdAt: state.createdAt,
      startedAt: state.startedAt,
      startLocation: state.startLocation,
      lastLocation: location,
      distanceMeters: distanceMeters,
      idleSeconds: idleSeconds,
      maxSpeedKph: maxSpeed,
      started: true,
      ended: false,
    );
    await _persistState();

    _emitTripUpdateIfNeeded(location, state.tripId, isMoving, config);
    _emitDwellIfNeeded(location, state.tripId, config);
    _emitRouteDeviationIfNeeded(location, state.tripId, config);

    if (config.stopOnStationary) {
      await _maybeStopOnStationary(location, state.tripId, config);
    }
  }

  void _emitTripUpdateIfNeeded(
    Location location,
    String tripId,
    bool isMoving,
    TripConfig config,
  ) {
    final lastUpdate = _lastUpdateAt;
    if (lastUpdate != null &&
        location.timestamp.difference(lastUpdate).inSeconds <
            config.updateIntervalSeconds) {
      return;
    }
    _lastUpdateAt = location.timestamp;
    _controller.add(TripEvent(
      type: TripEventType.tripUpdate,
      tripId: tripId,
      timestamp: location.timestamp,
      location: location,
      isMoving: isMoving,
    ));
  }

  void _emitDwellIfNeeded(Location location, String tripId, TripConfig config) {
    if (_dwellEmitted || config.dwellMinutes <= 0) {
      return;
    }
    final stationarySince = _lastStationaryAt;
    if (stationarySince == null) {
      return;
    }
    if (location.timestamp.difference(stationarySince).inMinutes >=
        config.dwellMinutes) {
      _dwellEmitted = true;
      _controller.add(TripEvent(
        type: TripEventType.dwell,
        tripId: tripId,
        timestamp: location.timestamp,
        location: location,
        isMoving: false,
      ));
    }
  }

  void _emitRouteDeviationIfNeeded(
    Location location,
    String tripId,
    TripConfig config,
  ) {
    if (config.route.isEmpty) {
      return;
    }
    final distance = _distanceToRouteMeters(location.coords, config.route);
    if (distance < config.routeDeviationThresholdMeters) {
      return;
    }
    final lastDeviation = _lastDeviationAt;
    if (lastDeviation != null &&
        location.timestamp.difference(lastDeviation).inSeconds <
            config.routeDeviationCooldownSeconds) {
      return;
    }
    _lastDeviationAt = location.timestamp;
    _controller.add(TripEvent(
      type: TripEventType.routeDeviation,
      tripId: tripId,
      timestamp: location.timestamp,
      location: location,
      distanceFromRouteMeters: distance,
      isMoving: true,
    ));
  }

  Future<void> _maybeStopOnStationary(
    Location location,
    String tripId,
    TripConfig config,
  ) async {
    final stationarySince = _lastStationaryAt;
    if (stationarySince == null) {
      return;
    }
    if (location.timestamp.difference(stationarySince).inMinutes >=
        config.stopTimeoutMinutes) {
      await stop();
    }
  }

  double _distanceToRouteMeters(Coords point, List<RoutePoint> route) {
    if (route.length < 2) {
      return LocationUtils.calculateDistance(
          point,
          Coords(
            latitude: route.first.latitude,
            longitude: route.first.longitude,
            accuracy: 0,
          ));
    }

    var minDistance = double.infinity;
    for (var i = 0; i < route.length - 1; i++) {
      final start = route[i];
      final end = route[i + 1];
      final distance = _distanceToSegmentMeters(
        point,
        start,
        end,
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _distanceToSegmentMeters(
    Coords point,
    RoutePoint start,
    RoutePoint end,
  ) {
    // 1. Convert start to vector
    final startLat = start.latitude * pi / 180.0;
    final startLng = start.longitude * pi / 180.0;
    final sx = cos(startLat) * cos(startLng);
    final sy = cos(startLat) * sin(startLng);
    final sz = sin(startLat);

    // 2. Convert end to vector
    final endLat = end.latitude * pi / 180.0;
    final endLng = end.longitude * pi / 180.0;
    final ex = cos(endLat) * cos(endLng);
    final ey = cos(endLat) * sin(endLng);
    final ez = sin(endLat);

    // 3. Convert point to vector
    final pointLat = point.latitude * pi / 180.0;
    final pointLng = point.longitude * pi / 180.0;
    final px = cos(pointLat) * cos(pointLng);
    final py = cos(pointLat) * sin(pointLng);
    final pz = sin(pointLat);

    // 4. segment = endVec - startVec
    final segX = ex - sx;
    final segY = ey - sy;
    final segZ = ez - sz;

    // 5. lengthSquared = dot(segment, segment)
    final lengthSquared = segX * segX + segY * segY + segZ * segZ;

    if (lengthSquared == 0) {
      return LocationUtils.calculateDistance(
        point,
        Coords(
          latitude: start.latitude,
          longitude: start.longitude,
          accuracy: 0,
        ),
      );
    }

    // 6. t = dot(pointVec - startVec, segment) / lengthSquared
    final pointMinusStartX = px - sx;
    final pointMinusStartY = py - sy;
    final pointMinusStartZ = pz - sz;

    final t = (pointMinusStartX * segX +
            pointMinusStartY * segY +
            pointMinusStartZ * segZ) /
        lengthSquared;

    final clampedT = t.clamp(0.0, 1.0);

    // 7. projection = startVec + segment * clampedT
    final projX = sx + segX * clampedT;
    final projY = sy + segY * clampedT;
    final projZ = sz + segZ * clampedT;

    // 8. projectedCoords = _fromVector(projection)
    final projLatRad = atan2(projZ, sqrt(projX * projX + projY * projY));
    final projLngRad = atan2(projY, projX);

    final projectedCoords = Coords(
      latitude: projLatRad * 180.0 / pi,
      longitude: projLngRad * 180.0 / pi,
      accuracy: 0,
    );

    return LocationUtils.calculateDistance(point, projectedCoords);
  }

  String _generateTripId() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seed = now.microsecondsSinceEpoch;
    final random = Random.secure().nextInt(1000000);
    return 'trip-$dateStr-$seed-$random';
  }

  Future<void> _persistState({bool force = false}) async {
    if (_store == null) {
      return;
    }
    final state = _state;
    if (state == null) {
      return;
    }
    if (!force && _shouldThrottlePersist(state.lastLocation?.timestamp)) {
      return;
    }
    await _store!.save(state);
  }

  bool _shouldThrottlePersist(DateTime? timestamp) {
    if (timestamp == null) {
      return true;
    }
    final lastPersist = _lastPersistAt;
    if (lastPersist != null &&
        timestamp.difference(lastPersist).inSeconds <
            (_config?.updateIntervalSeconds ?? 60)) {
      return true;
    }
    _lastPersistAt = timestamp;
    return false;
  }
}
