import 'dart:async';
import 'package:locus/src/battery/battery.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'locus_channels.dart';
import 'locus_battery.dart'; // For getPowerState
import 'locus_lifecycle.dart'; // For isTracking

/// Advanced Features (Spoof, Significant Change, Error Recovery).
class LocusFeatures {
  static SpoofDetector? _spoofDetector;
  static SignificantChangeManager? _significantChangeManager;
  static ErrorRecoveryManager? _errorRecoveryManager;

  // --- Spoof Detection ---

  static Future<void> setSpoofDetection(SpoofDetectionConfig config) async {
    _spoofDetector = SpoofDetector(config);
    await LocusChannels.methods
        .invokeMethod('setSpoofDetection', config.toMap());
  }

  static SpoofDetectionConfig? get spoofDetectionConfig =>
      _spoofDetector?.config;

  static SpoofDetectionEvent? analyzeForSpoofing(
    Location location, {
    bool? isMockProvider,
  }) {
    return _spoofDetector?.analyze(location, isMockProvider: isMockProvider);
  }

  static void resetSpoofDetector() {
    _spoofDetector?.reset();
    _spoofDetector = null;
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

  static void disposeSignificantChangeManager() {
    _significantChangeManager?.dispose();
    _significantChangeManager = null;
  }

  // --- Error Recovery ---

  static void setErrorHandler(ErrorRecoveryConfig config) {
    _errorRecoveryManager ??= ErrorRecoveryManager();
    _errorRecoveryManager!.configure(config);
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

  static void disposeErrorRecoveryManager() {
    _errorRecoveryManager?.dispose();
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
