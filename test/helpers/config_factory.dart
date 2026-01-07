/// Factory methods for creating test configurations.
///
/// Provides convenient builder-style API for creating Config objects
/// with sensible defaults for testing.
library;

import 'package:locus/locus.dart';

/// Factory for creating test configurations with a builder pattern.
///
/// Example:
/// ```dart
/// final config = ConfigFactory()
///   .withAccuracy(DesiredAccuracy.high)
///   .withDistanceFilter(10)
///   .withStopTimeout(5)
///   .enableHeadless()
///   .build();
/// ```
class ConfigFactory {
  DesiredAccuracy? _desiredAccuracy;
  double? _distanceFilter;
  int? _locationUpdateInterval;
  int? _stopTimeout;
  bool? _enableHeadless;
  bool? _stopOnTerminate;
  bool? _useSignificantChangesOnly;
  bool? _disableMotionActivityUpdates;
  bool? _disableStopDetection;
  String? _url;
  Map<String, String>? _headers;
  Map<String, dynamic>? _params;
  bool? _autoSync;
  bool? _batchSync;
  int? _maxBatchSize;

  /// Sets desired accuracy.
  ConfigFactory withAccuracy(DesiredAccuracy accuracy) {
    _desiredAccuracy = accuracy;
    return this;
  }

  /// Sets distance filter in meters.
  ConfigFactory withDistanceFilter(double meters) {
    _distanceFilter = meters;
    return this;
  }

  /// Sets location update interval in milliseconds.
  ConfigFactory withUpdateInterval(int milliseconds) {
    _locationUpdateInterval = milliseconds;
    return this;
  }

  /// Sets stop timeout in minutes.
  ConfigFactory withStopTimeout(int minutes) {
    _stopTimeout = minutes;
    return this;
  }

  /// Enables headless mode.
  ConfigFactory enableHeadless([bool enable = true]) {
    _enableHeadless = enable;
    return this;
  }

  /// Sets stop on terminate behavior.
  ConfigFactory stopOnTerminate([bool stop = true]) {
    _stopOnTerminate = stop;
    return this;
  }

  /// Enables significant changes only mode.
  ConfigFactory significantChangesOnly([bool enable = true]) {
    _useSignificantChangesOnly = enable;
    return this;
  }

  /// Disables motion activity updates.
  ConfigFactory disableMotionActivity([bool disable = true]) {
    _disableMotionActivityUpdates = disable;
    return this;
  }

  /// Disables stop detection.
  ConfigFactory disableStopDetection([bool disable = true]) {
    _disableStopDetection = disable;
    return this;
  }

  /// Sets HTTP sync URL.
  ConfigFactory withUrl(String url) {
    _url = url;
    return this;
  }

  /// Sets HTTP headers.
  ConfigFactory withHeaders(Map<String, String> headers) {
    _headers = headers;
    return this;
  }

  /// Sets HTTP params.
  ConfigFactory withParams(Map<String, dynamic> params) {
    _params = params;
    return this;
  }

  /// Enables auto sync.
  ConfigFactory autoSync([bool enable = true]) {
    _autoSync = enable;
    return this;
  }

  /// Enables batch sync.
  ConfigFactory batchSync({int maxBatchSize = 100}) {
    _batchSync = true;
    _maxBatchSize = maxBatchSize;
    return this;
  }

  /// Creates a high-accuracy configuration preset.
  ConfigFactory highAccuracy() {
    _desiredAccuracy = DesiredAccuracy.high;
    _distanceFilter = 10;
    _locationUpdateInterval = 5000;
    _stopTimeout = 5;
    return this;
  }

  /// Creates a balanced configuration preset.
  ConfigFactory balanced() {
    _desiredAccuracy = DesiredAccuracy.medium;
    _distanceFilter = 30;
    _locationUpdateInterval = 10000;
    _stopTimeout = 5;
    return this;
  }

  /// Creates a low-power configuration preset.
  ConfigFactory lowPower() {
    _desiredAccuracy = DesiredAccuracy.low;
    _distanceFilter = 100;
    _locationUpdateInterval = 60000;
    _stopTimeout = 15;
    return this;
  }

  /// Creates a passive configuration preset.
  ConfigFactory passive() {
    _desiredAccuracy = DesiredAccuracy.low;
    _distanceFilter = 500;
    _useSignificantChangesOnly = true;
    _disableMotionActivityUpdates = true;
    _disableStopDetection = true;
    return this;
  }

  /// Builds the Config object.
  Config build() {
    return Config(
      desiredAccuracy: _desiredAccuracy,
      distanceFilter: _distanceFilter,
      locationUpdateInterval: _locationUpdateInterval,
      stopTimeout: _stopTimeout,
      enableHeadless: _enableHeadless,
      stopOnTerminate: _stopOnTerminate,
      useSignificantChangesOnly: _useSignificantChangesOnly,
      disableMotionActivityUpdates: _disableMotionActivityUpdates,
      disableStopDetection: _disableStopDetection,
      url: _url,
      headers: _headers,
      params: _params,
      autoSync: _autoSync,
      batchSync: _batchSync,
      maxBatchSize: _maxBatchSize,
    );
  }
}
