import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:locus/src/features/battery/battery.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/core/locus_config.dart';
import 'package:locus/src/core/locus_lifecycle.dart';
import 'package:locus/src/core/locus_streams.dart';
import 'package:locus/src/core/locus_channels.dart';

/// Adaptive Tracking Logic.
class LocusAdaptive {
  static AdaptiveTrackingConfig? _adaptiveConfig;
  static AdaptiveSettings? _currentAdaptiveSettings;
  static bool _isEvaluatingAdaptiveSettings = false;
  static StreamSubscription? _adaptiveSubscription;
  static DateTime? _stationarySince;
  static bool _lastKnownMovingState = true;

  /// Sets adaptive tracking configuration.
  static Future<void> setAdaptiveTracking(AdaptiveTrackingConfig config) async {
    _adaptiveConfig = config;
    await LocusChannels.methods.invokeMethod(
      'setAdaptiveTracking',
      config.toMap(),
    );
    if (config.enabled) {
      final isTracking = await LocusLifecycle.isTracking();
      if (isTracking) {
        await startAdaptiveTracking();
      }
    } else {
      await stopAdaptiveTracking();
    }
  }

  /// Gets the current adaptive tracking configuration.
  static AdaptiveTrackingConfig? get adaptiveTrackingConfig => _adaptiveConfig;

  static bool get isEnabled => _adaptiveConfig?.enabled == true;

  static Future<void> startAdaptiveTracking() async {
    await _adaptiveSubscription?.cancel();
    _adaptiveSubscription = LocusStreams.events.listen((event) async {
      if (event.type == EventType.location ||
          event.type == EventType.activityChange ||
          event.type == EventType.motionChange) {
        await evaluateAdaptiveSettings();
      }
    });
    // Evaluate immediately
    await evaluateAdaptiveSettings();
  }

  static Future<void> stopAdaptiveTracking() async {
    await _adaptiveSubscription?.cancel();
    _adaptiveSubscription = null;
    _currentAdaptiveSettings = null;
    _stationarySince = null;
    _lastKnownMovingState = true;
  }

  /// Evaluates current conditions and updates tracking settings if needed.
  ///
  /// This method:
  /// 1. Checks if adaptive tracking is enabled
  /// 2. Prevents re-entrancy during evaluation
  /// 3. Calculates optimal settings based on speed, battery, location, etc.
  /// 4. Applies settings only if they differ from current (debouncing)
  /// 5. Updates the native config via [LocusConfig.setConfig]
  ///
  /// Called automatically on location/activity/motion events.
  static Future<void> evaluateAdaptiveSettings() async {
    if (_adaptiveConfig == null || !_adaptiveConfig!.enabled) {
      // Only log once, not on every evaluation attempt
      return;
    }
    if (_isEvaluatingAdaptiveSettings) return;

    _isEvaluatingAdaptiveSettings = true;
    try {
      final settings = await calculateAdaptiveSettings();

      // Debounce: only update if settings changed significantly
      if (_currentAdaptiveSettings?.distanceFilter == settings.distanceFilter &&
          _currentAdaptiveSettings?.desiredAccuracy ==
              settings.desiredAccuracy &&
          _currentAdaptiveSettings?.heartbeatInterval ==
              settings.heartbeatInterval &&
          _currentAdaptiveSettings?.gpsEnabled == settings.gpsEnabled) {
        return;
      }

      _currentAdaptiveSettings = settings;

      // Update config
      debugPrint('[Locus] Applying adaptive settings: $settings');
      await LocusConfig.setConfig(Config(
        desiredAccuracy: settings.desiredAccuracy,
        distanceFilter: settings.distanceFilter,
        locationUpdateInterval: settings.heartbeatInterval * 1000,
        // Also update heartbeat interval itself if using heartbeat mechanism
        heartbeatInterval: settings.heartbeatInterval,
      ));
    } catch (e) {
      // Only log for unexpected errors, not MissingPluginException in tests
      if (!e.toString().contains('MissingPluginException')) {
        debugPrint('[Locus] Adaptive tracking error: $e');
      }
    } finally {
      _isEvaluatingAdaptiveSettings = false;
    }
  }

  /// Calculates optimal settings based on current conditions.
  static Future<AdaptiveSettings> calculateAdaptiveSettings() async {
    final config = _adaptiveConfig ?? AdaptiveTrackingConfig.balanced;
    final state = await LocusLifecycle.getState();
    final result = await LocusChannels.methods.invokeMethod('getPowerState');
    final power = result is Map
        ? PowerState.fromMap(Map<String, dynamic>.from(result))
        : PowerState.unknown;

    final location = state.location;
    final isInGeofence = await LocusLifecycle.isInActiveGeofence();

    // Track stationary time for stationaryDelay feature
    if (state.isMoving) {
      _stationarySince = null;
      _lastKnownMovingState = true;
    } else if (_lastKnownMovingState) {
      // Just became stationary
      _stationarySince = DateTime.now();
      _lastKnownMovingState = false;
    }

    Duration? timeSinceStationary;
    if (_stationarySince != null) {
      timeSinceStationary = DateTime.now().difference(_stationarySince!);
    }

    return config.calculateSettings(
      speedMps: location?.coords.speed ?? 0,
      batteryPercent: power.batteryLevel,
      isCharging: power.isCharging,
      isMoving: state.isMoving,
      activity: location?.activity?.type,
      isInGeofence: isInGeofence,
      timeSinceStationary: timeSinceStationary,
    );
  }
}
