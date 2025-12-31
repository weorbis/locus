library;

import 'package:locus/src/config/geolocation_config.dart';
import 'package:locus/src/config/config_enums.dart';

/// Ready-to-use configuration presets for common tracking scenarios.
class ConfigPresets {
  const ConfigPresets._();

  /// Lowest power usage with coarse updates.
  static const Config lowPower = Config(
    desiredAccuracy: DesiredAccuracy.low,
    distanceFilter: 200,
    stopTimeout: 15,
    heartbeatInterval: 300,
    autoSync: true,
    batchSync: true,
  );

  /// Balanced accuracy and battery usage.
  static const Config balanced = Config(
    desiredAccuracy: DesiredAccuracy.medium,
    distanceFilter: 50,
    stopTimeout: 8,
    heartbeatInterval: 120,
    autoSync: true,
    batchSync: true,
  );

  /// High accuracy for active tracking.
  static const Config tracking = Config(
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10,
    stopTimeout: 5,
    heartbeatInterval: 60,
    autoSync: true,
    batchSync: true,
  );

  /// Highest accuracy, frequent updates (fitness/trails).
  static const Config trail = Config(
    desiredAccuracy: DesiredAccuracy.navigation,
    distanceFilter: 5,
    stopTimeout: 2,
    activityRecognitionInterval: 5000,
    heartbeatInterval: 30,
    autoSync: true,
    batchSync: false,
  );
}
