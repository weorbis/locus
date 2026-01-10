/// Diagnostics service implementation for v2.0 API.
library;

import 'dart:async';

import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/features/location/services/location_anomaly_detector.dart';
import 'package:locus/src/features/location/services/location_quality_analyzer.dart';
import 'package:locus/src/services/diagnostics_service.dart';

/// Implementation of [DiagnosticsService] that delegates to the core interface.
class DiagnosticsServiceImpl implements DiagnosticsService {
  /// Creates a diagnostics service with a factory for getting the interface.
  DiagnosticsServiceImpl(this._instanceFactory);

  final LocusInterface Function() _instanceFactory;

  LocusInterface get _instance => _instanceFactory();

  @override
  Future<DiagnosticsSnapshot> getDiagnostics() => _instance.getDiagnostics();

  @override
  Future<List<LogEntry>> getLog() => _instance.getLog();

  @override
  Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
  }) {
    return _instance.locationAnomalies(config: config);
  }

  @override
  StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config = const LocationAnomalyConfig(),
    Function? onError,
  }) {
    return _instance.onLocationAnomaly(
      callback,
      config: config,
      onError: onError,
    );
  }

  @override
  Stream<LocationQuality> locationQuality({
    LocationQualityConfig config = const LocationQualityConfig(),
  }) {
    return _instance.locationQuality(config: config);
  }

  @override
  StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config = const LocationQualityConfig(),
    Function? onError,
  }) {
    return _instance.onLocationQuality(
      callback,
      config: config,
      onError: onError,
    );
  }

  @override
  Future<bool> applyRemoteCommand(RemoteCommand command) =>
      _instance.applyRemoteCommand(command);
}
