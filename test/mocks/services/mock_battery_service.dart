/// Mock implementation of BatteryService for testing.
library;

import 'dart:async';

import 'package:locus/locus.dart';

/// Mock battery service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockBatteryService();
///
/// // Simulate low battery
/// mock.setLevel(15);
/// mock.setPowerSaveMode(true);
///
/// // Trigger events
/// mock.emitPowerStateChange(PowerState.lowPower);
///
/// // Verify stats
/// final stats = await mock.getStats();
/// expect(stats.level, 15);
/// ```
class MockBatteryService implements BatteryService {
  MockBatteryService({
    int initialLevel = 100,
    bool initialCharging = false,
    bool initialPowerSave = false,
  })  : _level = initialLevel,
        _isCharging = initialCharging,
        _isPowerSaveMode = initialPowerSave;

  int _level;
  bool _isCharging;
  bool _isPowerSaveMode;
  AdaptiveTrackingConfig? _adaptiveConfig;
  DateTime? _benchmarkStartTime;
  int _benchmarkLocationCount = 0;
  int _benchmarkSyncCount = 0;
  double _benchmarkStartLevel = 100;

  final _powerStateController =
      StreamController<PowerStateChangeEvent>.broadcast();
  final _powerSaveController = StreamController<bool>.broadcast();

  /// Sets the battery level (0-100).
  void setLevel(int level) {
    if (level < 0 || level > 100) {
      throw ArgumentError('Battery level must be between 0 and 100');
    }
    _level = level;
  }

  /// Sets the charging state.
  void setCharging(bool charging) {
    _isCharging = charging;
  }

  /// Sets the power save mode.
  void setPowerSaveMode(bool enabled) {
    final previous = _isPowerSaveMode;
    _isPowerSaveMode = enabled;
    if (previous != enabled) {
      _powerSaveController.add(enabled);
    }
  }

  /// Emits a power state change event.
  void emitPowerStateChange(PowerState newState) {
    final event = PowerStateChangeEvent(
      current: newState,
      previous: PowerState.unknown,
      changeType: PowerStateChangeType.batteryLevel,
      timestamp: DateTime.now(),
    );
    _powerStateController.add(event);
  }

  /// Simulates battery drain over time.
  Future<void> simulateDrain({
    required int drainPercent,
    required Duration duration,
  }) async {
    final steps = drainPercent;
    final interval = duration ~/ steps;

    for (var i = 0; i < steps; i++) {
      await Future.delayed(interval);
      _level = (_level - 1).clamp(0, 100);

      if (_level <= 20 && !_isPowerSaveMode) {
        setPowerSaveMode(true);
      }
    }
  }

  @override
  Stream<PowerStateChangeEvent> get powerStateEvents =>
      _powerStateController.stream;

  @override
  Stream<bool> get powerSaveChanges => _powerSaveController.stream;

  @override
  Future<BatteryStats> getStats() async {
    return BatteryStats(
      currentBatteryLevel: _level,
      isCharging: _isCharging,
      gpsOnTimePercent: 0,
      locationUpdatesCount: _benchmarkLocationCount,
      syncRequestsCount: _benchmarkSyncCount,
      averageAccuracyMeters: 0,
      trackingDurationMinutes: 0,
    );
  }

  @override
  Future<PowerState> getPowerState() async {
    return PowerState(
      batteryLevel: _level,
      isCharging: _isCharging,
      chargingType: _isCharging ? ChargingType.ac : ChargingType.none,
      isPowerSaveMode: _isPowerSaveMode,
    );
  }

  @override
  Future<BatteryRunway> estimateRunway() async {
    // Simple estimation: assume 1% per hour at current drain rate
    final hoursRemaining = _level.toDouble();
    final lowPowerHoursRemaining = _level * 1.5;

    return BatteryRunway(
      duration: Duration(hours: hoursRemaining.toInt()),
      lowPowerDuration: Duration(hours: lowPowerHoursRemaining.toInt()),
      recommendation: 'Battery level: $_level%',
      currentLevel: _level,
      isCharging: _isCharging,
      drainRatePerHour: 1.0,
      lowPowerDrainRatePerHour: 0.67,
      confidence: 0.8,
    );
  }

  @override
  Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) async {
    _adaptiveConfig = config;
  }

  @override
  AdaptiveTrackingConfig? get adaptiveTrackingConfig => _adaptiveConfig;

  @override
  Future<AdaptiveSettings> calculateAdaptiveSettings() async {
    // Calculate settings based on current battery level
    final accuracy = _level > 50
        ? DesiredAccuracy.high
        : _level > 20
            ? DesiredAccuracy.medium
            : DesiredAccuracy.low;

    return AdaptiveSettings(
      desiredAccuracy: accuracy,
      distanceFilter: _level > 50 ? 10 : 50,
      heartbeatInterval: _level > 50 ? 60 : 300,
      gpsEnabled: _level > 20,
      reason: 'Battery level: $_level%',
    );
  }

  @override
  Future<void> startBenchmark() async {
    _benchmarkStartTime = DateTime.now();
    _benchmarkStartLevel = _level.toDouble();
    _benchmarkLocationCount = 0;
    _benchmarkSyncCount = 0;
  }

  @override
  Future<BenchmarkResult?> stopBenchmark() async {
    if (_benchmarkStartTime == null) return null;

    final duration = DateTime.now().difference(_benchmarkStartTime!);
    final batteryUsed = _benchmarkStartLevel - _level;

    final result = BenchmarkResult(
      duration: duration,
      drainPercent: batteryUsed,
      locationUpdates: _benchmarkLocationCount,
      syncRequests: _benchmarkSyncCount,
      gpsOnPercent: 75.0,
      averageAccuracy: 15.0,
      timeByState: {
        'stationary': const Duration(minutes: 10),
        'walking': const Duration(minutes: 20),
      },
    );

    _benchmarkStartTime = null;
    return result;
  }

  @override
  void recordBenchmarkLocationUpdate({double? accuracy}) {
    if (_benchmarkStartTime != null) {
      _benchmarkLocationCount++;
    }
  }

  @override
  void recordBenchmarkSync() {
    if (_benchmarkStartTime != null) {
      _benchmarkSyncCount++;
    }
  }

  @override
  StreamSubscription<PowerStateChangeEvent> onPowerStateChange(
    void Function(PowerStateChangeEvent event) callback, {
    Function? onError,
  }) {
    return _powerStateController.stream.listen(
      callback,
      onError: onError,
    );
  }

  @override
  StreamSubscription<bool> onPowerSaveChange(
    void Function(bool) callback, {
    Function? onError,
  }) {
    return _powerSaveController.stream.listen(
      callback,
      onError: onError,
    );
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _powerStateController.close();
    await _powerSaveController.close();
  }
}
