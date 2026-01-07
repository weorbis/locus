import 'dart:async';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_lifecycle.dart';
import 'package:locus/src/core/locus_streams.dart';

/// Advanced Features (Spoof, Significant Change, Error Recovery).
class LocusFeatures {
  static SpoofDetector? _spoofDetector;
  static SignificantChangeManager? _significantChangeManager;
  static ErrorRecoveryManager? _errorRecoveryManager;

  // --- Spoof Detection ---

  /// Sets spoof detection configuration.
  ///
  /// When `config.blockMockLocations` is true, spoofed locations will be
  /// filtered from the event stream and available via [blockedLocationEvents].
  static Future<void> setSpoofDetection(SpoofDetectionConfig config) async {
    _spoofDetector = SpoofDetector(config);

    // Enable spoof detection in the event stream
    if (config.enabled) {
      LocusStreams.enableSpoofDetection(config);
    } else {
      LocusStreams.disableSpoofDetection();
    }

    await LocusChannels.methods
        .invokeMethod('setSpoofDetection', config.toMap());
  }

  static SpoofDetectionConfig? get spoofDetectionConfig =>
      _spoofDetector?.config;

  /// Stream of blocked/spoofed location events.
  /// Listen to this to monitor locations that were blocked by spoof detection.
  static Stream<SpoofDetectionEvent> get blockedLocationEvents =>
      LocusStreams.blockedEvents;

  static SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) {
    return _spoofDetector?.analyze(location, isMockProvider: isMockProvider);
  }

  static void resetSpoofDetector() {
    _spoofDetector?.reset();
    _spoofDetector = null;
    LocusStreams.disableSpoofDetection();
  }

  // --- Significant Change ---

  static Future<void> startSignificantChangeMonitoring([
    SignificantChangeConfig config = const SignificantChangeConfig(),
  ]) async {
    _significantChangeManager ??= SignificantChangeManager();
    _significantChangeManager!.start(config);
    await LocusChannels.methods.invokeMethod(
      'startSignificantChangeMonitoring',
      config.toMap(),
    );
  }

  static Future<void> stopSignificantChangeMonitoring() async {
    _significantChangeManager?.stop();
    await LocusChannels.methods.invokeMethod('stopSignificantChangeMonitoring');
  }

  static bool get isSignificantChangeMonitoringActive =>
      _significantChangeManager?.isMonitoring ?? false;

  static Stream<SignificantChangeEvent>? get significantChangeStream =>
      _significantChangeManager?.events;

  static Future<void> disposeSignificantChangeManager() async {
    await _significantChangeManager?.dispose();
    _significantChangeManager = null;
  }

  // --- Error Recovery ---

  /// Sets the error recovery configuration.
  ///
  /// When configured, stream errors will be handled through the
  /// error recovery system, respecting retry policies and callbacks.
  static void setErrorHandler(ErrorRecoveryConfig config) {
    _errorRecoveryManager ??= ErrorRecoveryManager();
    _errorRecoveryManager!.configure(config);

    // Wire error recovery into stream error handling
    LocusStreams.setErrorRecoveryManager(_errorRecoveryManager);
  }

  static ErrorRecoveryManager? get errorRecoveryManager =>
      _errorRecoveryManager;

  static Stream<LocusError>? get errorStream => _errorRecoveryManager?.errors;

  static Future<RecoveryAction> handleError(LocusError error) async {
    if (_errorRecoveryManager == null) {
      return RecoveryAction.propagate;
    }

    final power = await LocusBattery.getPowerState();
    // Using LocusChannels to avoid circle with Lifecycle if possible,
    // but we need isTracking.
    // We can assume we can import LocusLifecycle.
    final isActive = await LocusLifecycle.isTracking();
    final networkType = await _getNetworkType();

    return _errorRecoveryManager!.handleError(
      error,
      isTrackingActive: isActive,
      batteryLevel: power.batteryLevel,
      isCharging: power.isCharging,
      networkAvailable: networkType != NetworkType.none,
    );
  }

  static Future<void> disposeErrorRecoveryManager() async {
    // Disconnect from LocusStreams
    LocusStreams.setErrorRecoveryManager(null);
    await _errorRecoveryManager?.dispose();
    _errorRecoveryManager = null;
  }

  static Future<NetworkType> _getNetworkType() async {
    final result = await LocusChannels.methods.invokeMethod('getNetworkType');
    if (result is String) {
      return NetworkType.values.firstWhere(
        (e) => e.name == result,
        orElse: () => NetworkType.none,
      );
    }
    return NetworkType.none;
  }
}
