import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/shared/location_utils.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/features/battery/services/locus_adaptive.dart';
import 'package:locus/src/core/locus_streams.dart';
import 'package:locus/src/features/trips/services/locus_trip.dart';
import 'package:locus/src/features/tracking/services/locus_profiles.dart';
import 'package:locus/src/features/geofencing/services/locus_workflows.dart';
import 'package:locus/src/core/locus_features.dart';
import 'package:locus/src/features/geofencing/services/locus_geofencing.dart';

/// Lifecycle management of the Locus SDK.
class LocusLifecycle {
  static bool _isForeground = true;
  static _LifecycleObserver? _lifecycleObserver;

  /// Initializes the plugin with the given configuration.
  static Future<GeolocationState> ready(
    Config config, {
    bool skipValidation = false,
  }) async {
    // Validate configuration unless explicitly skipped
    if (!skipValidation) {
      final validationResult = ConfigValidator.validate(config);

      // Log warnings
      for (final warning in validationResult.warnings) {
        debugPrint(
            '[Locus] Config warning: ${warning.field} - ${warning.message}');
        if (warning.suggestion != null) {
          debugPrint('[Locus]   Suggestion: ${warning.suggestion}');
        }
      }

      // Throw on errors
      if (!validationResult.isValid) {
        for (final error in validationResult.errors) {
          debugPrint('[Locus] Config error: ${error.field} - ${error.message}');
          if (error.suggestion != null) {
            debugPrint('[Locus]   Suggestion: ${error.suggestion}');
          }
        }
        throw ConfigValidationException(validationResult.errors);
      }
    }

    final result =
        await LocusChannels.methods.invokeMethod('ready', config.toMap());
    if (result is Map) {
      return GeolocationState.fromMap(Map<String, dynamic>.from(result));
    }
    return const GeolocationState(enabled: false, isMoving: false);
  }

  /// Starts the background geolocation service.
  static Future<GeolocationState> start() async {
    dynamic result;
    try {
      result = await LocusChannels.methods.invokeMethod('start');
    } on MissingPluginException {
      return const GeolocationState(enabled: false, isMoving: false);
    }

    // Start adaptive tracking if enabled
    if (LocusAdaptive.isEnabled) {
      await LocusAdaptive.startAdaptiveTracking();
    }

    if (result is Map) {
      return GeolocationState.fromMap(Map<String, dynamic>.from(result));
    }
    debugPrint('[Locus] start failed: unexpected result ${result.runtimeType}');
    return const GeolocationState(enabled: false, isMoving: false);
  }

  /// Stops the background geolocation service.
  static Future<GeolocationState> stop() async {
    await LocusAdaptive.stopAdaptiveTracking();
    final result = await LocusChannels.methods.invokeMethod('stop');
    if (result is Map) {
      return GeolocationState.fromMap(Map<String, dynamic>.from(result));
    }
    return const GeolocationState(enabled: false, isMoving: false);
  }

  /// Gets the current state of the service.
  static Future<GeolocationState> getState() async {
    final result = await LocusChannels.methods.invokeMethod('getState');
    if (result is Map) {
      return GeolocationState.fromMap(Map<String, dynamic>.from(result));
    }
    return const GeolocationState(enabled: false, isMoving: false);
  }

  /// Checks if tracking is currently active.
  static Future<bool> isTracking() async {
    final state = await getState();
    return state.enabled;
  }

  /// Destroys the SDK instance, cleaning up all resources and static state.
  static Future<void> destroy() async {
    await LocusAdaptive.stopAdaptiveTracking();
    await LocusStreams.stopNativeStream(force: true);

    // Attempt to stop and clean native state; ignore missing plugin in tests
    try {
      await LocusChannels.methods.invokeMethod('stop');
    } catch (_) {}
    try {
      await LocusChannels.methods.invokeMethod('removeGeofences');
    } catch (_) {}
    try {
      await LocusChannels.methods.invokeMethod('clearQueue');
    } catch (_) {}
    try {
      await LocusChannels.methods.invokeMethod('destroyLocations');
    } catch (_) {}

    await LocusTrip.dispose();
    await LocusProfiles.clearTrackingProfiles();
    await LocusWorkflows.dispose();
    await LocusFeatures.disposeSignificantChangeManager();
    await LocusFeatures.disposeErrorRecoveryManager();
    LocusFeatures.resetSpoofDetector();

    // Reset LocusStreams static state
    LocusStreams.reset();

    // Reset lifecycle static state
    stopLifecycleObserving();
    _isForeground = true;
  }

  /// Whether the app is currently in the foreground.
  static bool get isForeground => _isForeground;

  /// Starts observing app lifecycle changes.
  static void startLifecycleObserving() {
    if (_lifecycleObserver != null) return;
    _lifecycleObserver = _LifecycleObserver((isForeground) {
      _isForeground = isForeground;
    });
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  /// Stops observing app lifecycle changes.
  static void stopLifecycleObserving() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  /// Checks if the current location is within any active geofence.
  static Future<bool> isInActiveGeofence() async {
    try {
      final geofences = await LocusGeofencing.getGeofences();
      if (geofences.isEmpty) return false;

      final state = await getState();
      final location = state.location;
      if (location == null) return false;

      for (final geofence in geofences) {
        final distance = LocationUtils.calculateDistance(
          location.coords,
          Coords(
            latitude: geofence.latitude,
            longitude: geofence.longitude,
            accuracy: 0,
          ),
        );
        if (distance <= geofence.radius) {
          return true;
        }
      }
      return false;
    } catch (e, stack) {
      // Only log verbose stack trace for unexpected errors
      if (e.toString().contains('MissingPluginException')) {
        // Expected in test environments - silently return false
      } else {
        debugPrint('[Locus] Error checking geofence status: $e');
        debugPrint('[Locus] Stack trace: $stack');
      }
      return false;
    }
  }
}

/// Internal lifecycle observer for tracking foreground/background state.
class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver(this.onStateChange);
  final void Function(bool isForeground) onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    onStateChange(isForeground);
  }
}
