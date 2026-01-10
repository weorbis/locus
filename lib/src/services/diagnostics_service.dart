/// Diagnostics service interface for v2.0 API.
///
/// Provides a clean, organized API for debugging and diagnostics.
/// Access via `Locus.diagnostics`.
library;

import 'dart:async';

import 'package:locus/src/models.dart';
import 'package:locus/src/features/location/services/location_anomaly_detector.dart';
import 'package:locus/src/features/location/services/location_quality_analyzer.dart';

/// Service interface for diagnostics and debugging operations.
///
/// Provides tools for debugging location issues, analyzing data quality,
/// and monitoring SDK health.
///
/// Example:
/// ```dart
/// // Get full diagnostics snapshot
/// final snapshot = await Locus.diagnostics.getDiagnostics();
/// print('SDK State: ${snapshot.state}');
/// print('Pending locations: ${snapshot.pendingCount}');
///
/// // Get SDK logs
/// final logs = await Locus.diagnostics.getLog();
/// for (final entry in logs) {
///   print('[${entry.level}] ${entry.message}');
/// }
///
/// // Monitor location anomalies
/// Locus.diagnostics.locationAnomalies().listen((anomaly) {
///   print('Anomaly detected: ${anomaly.type}');
/// });
///
/// // Monitor location quality
/// Locus.diagnostics.locationQuality().listen((quality) {
///   if (quality.score < 0.5) {
///     print('Poor location quality: ${quality.issues}');
///   }
/// });
/// ```
abstract class DiagnosticsService {
  /// Gets a comprehensive diagnostics snapshot.
  ///
  /// Returns information about:
  /// - Current SDK state
  /// - Pending location count
  /// - Last sync status
  /// - Configuration details
  /// - Active geofences
  /// - Error history
  Future<DiagnosticsSnapshot> getDiagnostics();

  /// Gets structured log entries from the SDK.
  ///
  /// Returns recent log entries useful for debugging.
  Future<List<LogEntry>> getLog();

  /// Stream of detected location anomalies.
  ///
  /// Anomalies include:
  /// - GPS jumps (sudden large position changes)
  /// - Mock locations (if detection is enabled)
  /// - Unrealistic speeds
  /// - Poor accuracy readings
  ///
  /// [config] - Optional configuration for anomaly detection thresholds.
  Stream<LocationAnomaly> locationAnomalies({
    LocationAnomalyConfig config,
  });

  /// Subscribes to location anomaly events.
  StreamSubscription<LocationAnomaly> onLocationAnomaly(
    void Function(LocationAnomaly anomaly) callback, {
    LocationAnomalyConfig config,
    Function? onError,
  });

  /// Stream of location quality assessments.
  ///
  /// Quality metrics include:
  /// - Accuracy score
  /// - Signal strength indicators
  /// - Provider reliability
  /// - Environmental factors
  ///
  /// [config] - Optional configuration for quality thresholds.
  Stream<LocationQuality> locationQuality({
    LocationQualityConfig config,
  });

  /// Subscribes to location quality events.
  StreamSubscription<LocationQuality> onLocationQuality(
    void Function(LocationQuality quality) callback, {
    LocationQualityConfig config,
    Function? onError,
  });

  /// Applies a remote command for debugging purposes.
  ///
  /// Remote commands allow server-side control for debugging:
  /// - Force sync
  /// - Update configuration
  /// - Trigger diagnostics
  /// - Enable verbose logging
  Future<bool> applyRemoteCommand(RemoteCommand command);
}
