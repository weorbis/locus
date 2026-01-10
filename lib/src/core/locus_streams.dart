import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/core/event_mapper.dart';
import 'package:locus/src/features/location/services/spoof_detection.dart';
import 'package:locus/src/features/diagnostics/services/error_recovery.dart';
import 'package:locus/src/features/geofencing/services/polygon_geofence_service.dart';
import 'package:locus/src/features/privacy/services/privacy_zone_service.dart';
import 'package:locus/src/core/locus_channels.dart';

/// Stream management for geolocation events.
class LocusStreams {
  static StreamController<GeolocationEvent<dynamic>>? _eventController;
  static StreamController<SpoofDetectionEvent>? _blockedEventsController;
  // ignore: cancel_subscriptions - cancelled in _maybeStopNativeStream() and stopNativeStream()
  static StreamSubscription<dynamic>? _nativeSubscription;
  static int _listenerCount = 0;
  static bool _isStarting = false;
  static bool _isStopping = false;
  static Completer<void>? _streamOperationLock;

  // Spoof detection integration
  static SpoofDetector? _spoofDetector;
  static bool _spoofDetectionEnabled = false;

  // Polygon geofence integration
  static PolygonGeofenceService? _polygonGeofenceService;

  // Privacy zone integration
  static PrivacyZoneService? _privacyZoneService;

  /// Stream of all geolocation events (after spoof filtering).
  static Stream<GeolocationEvent<dynamic>> get events {
    _eventController ??= StreamController<GeolocationEvent<dynamic>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    return _eventController!.stream;
  }

  /// Stream of blocked/spoofed events (for monitoring purposes).
  static Stream<SpoofDetectionEvent> get blockedEvents {
    _blockedEventsController ??=
        StreamController<SpoofDetectionEvent>.broadcast();
    return _blockedEventsController!.stream;
  }

  /// Enables spoof detection with the given configuration.
  /// When enabled, spoofed locations will be filtered from the events stream
  /// and emitted on the [blockedEvents] stream instead.
  static void enableSpoofDetection(SpoofDetectionConfig config) {
    _spoofDetector = SpoofDetector(config);
    _spoofDetectionEnabled = true;
    debugPrint(
        '[Locus] Spoof detection enabled, blocking: ${config.blockMockLocations}');
  }

  /// Disables spoof detection.
  static void disableSpoofDetection() {
    _spoofDetector?.reset();
    _spoofDetector = null;
    _spoofDetectionEnabled = false;
  }

  /// Whether spoof detection is currently enabled.
  static bool get isSpoofDetectionEnabled => _spoofDetectionEnabled;

  /// Sets the polygon geofence service for processing location updates.
  /// When set, location events will trigger polygon enter/exit detection.
  static void setPolygonGeofenceService(PolygonGeofenceService? service) {
    _polygonGeofenceService = service;
    debugPrint(
        '[Locus] Polygon geofence service ${service != null ? 'registered' : 'cleared'}');
  }

  /// Sets the privacy zone service for filtering location events.
  /// When set, locations in privacy zones will be obfuscated or excluded.
  static Future<void> setPrivacyZoneService(PrivacyZoneService? service) async {
    _privacyZoneService = service;
    debugPrint(
        '[Locus] Privacy zone service ${service != null ? 'registered' : 'cleared'}');

    // Inform native side to avoid persisting raw locations when privacy zones are active.
    try {
      await LocusChannels.methods.invokeMethod('setPrivacyMode', service != null);
    } catch (error) {
      debugPrint('[Locus] Failed to set privacy mode on native side: $error');
      // Non-critical, continue without propagating error
    }
  }

  static Future<void> _onListen() async {
    _listenerCount += 1;
    // Start asynchronously to avoid blocking, but use proper async handling
    await _ensureNativeStreamStarted().catchError((error) {
      debugPrint('[Locus] Error starting native stream: $error');
    });
  }

  static Future<void> _onCancel() async {
    _listenerCount -= 1;
    if (_listenerCount < 0) _listenerCount = 0;
    // Stop asynchronously with proper error handling
    await _maybeStopNativeStream().catchError((error) {
      debugPrint('[Locus] Error stopping native stream: $error');
    });
  }

  /// Acquires the stream operation lock, waiting if necessary.
  /// Returns a function to release the lock when done.
  static Future<void Function()> _acquireLock() async {
    // Wait for any in-progress operation to complete
    while (_streamOperationLock != null) {
      await _streamOperationLock!.future;
    }

    // Create new lock
    final lock = Completer<void>();
    _streamOperationLock = lock;

    // Return release function
    return () {
      if (_streamOperationLock == lock) {
        lock.complete();
        _streamOperationLock = null;
      }
    };
  }

  /// Ensures the native stream is started.
  static Future<void> _ensureNativeStreamStarted() async {
    // Acquire lock to prevent concurrent initialization
    final releaseLock = await _acquireLock();

    try {
      // Double-check inside lock: already running or no listeners
      if (_nativeSubscription != null || _isStarting || _listenerCount <= 0) {
        return;
      }

      _isStarting = true;

      try {
        _nativeSubscription =
            LocusChannels.events.receiveBroadcastStream().listen(
          (event) async {
            try {
              final mapped = EventMapper.mapToEvent(event);
              _processEvent(mapped);
            } catch (e, stack) {
              debugPrint('[Locus] Event mapping error: $e');
              await _handleStreamError(e, stack, 'event_mapping');
            }
          },
          onError: (Object error, StackTrace stackTrace) async {
            debugPrint('[Locus] Stream error: $error');
            await _handleStreamError(error, stackTrace, 'stream');
          },
        );
      } catch (e) {
        debugPrint('[Locus] Failed to start native stream: $e');
      } finally {
        _isStarting = false;
      }
    } finally {
      releaseLock();
    }
  }

  /// Processes a mapped event, applying spoof detection, privacy zones,
  /// and polygon geofence detection if enabled.
  static void _processEvent(GeolocationEvent<dynamic> event) {
    // Only apply location processing to location-type events
    if (event.type == EventType.location && event.data is Location) {
      var location = event.data as Location;

      // 1. Spoof detection (may block the event entirely)
      if (_spoofDetectionEnabled && _spoofDetector != null) {
        final spoofResult = _spoofDetector!.analyze(location);

        if (spoofResult != null) {
          if (spoofResult.wasBlocked) {
            _blockedEventsController?.add(spoofResult);
            debugPrint(
                '[Locus] Blocked spoofed location: ${spoofResult.factors}');
            return; // Don't process further
          }
          debugPrint(
              '[Locus] Spoofed location detected (not blocked): ${spoofResult.factors}');
          location = location.copyWith(isMock: true);
        }
      }

      // 2. Privacy zone processing (may exclude or obfuscate location)
      Location processedLocation = location;
      if (_privacyZoneService != null &&
          _privacyZoneService!.enabledZones.isNotEmpty) {
        final result = _privacyZoneService!.processLocation(location);

        if (result.wasExcluded) {
          debugPrint('[Locus] Location excluded by privacy zone');
          return; // Don't emit excluded locations
        }

        if (result.wasObfuscated && result.processedLocation != null) {
          processedLocation = result.processedLocation!;
          debugPrint('[Locus] Location obfuscated by privacy zone');
        }
      }

      // 3. Polygon geofence detection (triggers enter/exit events)
      if (_polygonGeofenceService != null &&
          _polygonGeofenceService!.count > 0) {
        _polygonGeofenceService!.processLocationUpdate(
          processedLocation.coords.latitude,
          processedLocation.coords.longitude,
        );
      }

      // Emit the (possibly modified) location event
      if (processedLocation != location) {
        _eventController?.add(GeolocationEvent<Location>(
          type: event.type,
          data: processedLocation,
        ));
      } else {
        _eventController?.add(event);
      }
      return;
    }

    // Non-location events pass through unchanged
    _eventController?.add(event);
  }

  /// Handles stream errors through the error recovery system.
  static Future<void> _handleStreamError(
      Object error, StackTrace stackTrace, String operation) async {
    // Import and use error recovery if configured
    final errorManager = _errorRecoveryManager;

    if (errorManager != null) {
      final locusError = LocusError(
        type: _classifyError(error),
        message: error.toString(),
        originalError: error,
        stackTrace: stackTrace,
        operation: operation,
        isRecoverable: true,
      );

      // Handle error with proper async chain for immediate recovery
      await errorManager.handleError(locusError).then((action) {
        debugPrint('[Locus] Error recovery action: $action');

        // If action is not 'ignore', propagate to listeners
        if (action != RecoveryAction.ignore) {
          _eventController?.addError(error, stackTrace);
        }
      }).catchError((recoveryError) {
        debugPrint('[Locus] Error during error recovery: $recoveryError');
        // Propagate original error if recovery fails
        _eventController?.addError(error, stackTrace);
      });
    } else {
      // No error recovery configured, just propagate
      _eventController?.addError(error, stackTrace);
    }
  }

  /// Classifies an error into a LocusErrorType.
  static LocusErrorType _classifyError(Object error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('permission')) {
      return LocusErrorType.permissionDenied;
    } else if (errorStr.contains('timeout')) {
      return LocusErrorType.locationTimeout;
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return LocusErrorType.networkError;
    } else if (errorStr.contains('service')) {
      return LocusErrorType.serviceDisconnected;
    } else if (errorStr.contains('provider') || errorStr.contains('disabled')) {
      return LocusErrorType.servicesDisabled;
    } else if (errorStr.contains('config')) {
      return LocusErrorType.configError;
    } else if (errorStr.contains('geofence')) {
      return LocusErrorType.geofenceError;
    }
    return LocusErrorType.unknown;
  }

  // Error recovery integration
  static ErrorRecoveryManager? _errorRecoveryManager;

  /// Sets the error recovery manager for handling stream errors.
  static void setErrorRecoveryManager(ErrorRecoveryManager? manager) {
    _errorRecoveryManager = manager;
  }

  /// Resets all static state. Called by Locus.destroy() to ensure
  /// clean state for re-initialization.
  static void reset() {
    // Reset listener count and operation flags
    _listenerCount = 0;
    _isStarting = false;
    _isStopping = false;
    _streamOperationLock = null;

    // Clear subscription reference (already cancelled by stopNativeStream)
    _nativeSubscription = null;

    // Clear controllers (already closed by stopNativeStream)
    _eventController = null;
    _blockedEventsController = null;

    // Reset spoof detection state
    _spoofDetector = null;
    _spoofDetectionEnabled = false;

    // Clear service references
    _polygonGeofenceService = null;
    _privacyZoneService = null;
    _errorRecoveryManager = null;
  }

  /// Maybe stops the native stream if no listeners remain.
  static Future<void> _maybeStopNativeStream() async {
    // Acquire lock to prevent concurrent stop operations
    final releaseLock = await _acquireLock();

    try {
      // Double-check inside lock: should we stop?
      if (_listenerCount > 0 || _nativeSubscription == null || _isStopping) {
        return;
      }

      _isStopping = true;

      try {
        final subscription = _nativeSubscription;
        _nativeSubscription = null;
        await subscription?.cancel();
      } finally {
        _isStopping = false;
      }
    } finally {
      releaseLock();
    }
  }

  /// Starts the native event stream (legacy - now handled automatically).
  @Deprecated('Use events getter instead, streams are managed automatically')
  static Future<void> startNativeStream() async {
    _listenerCount += 1;
    await Future.microtask(() => _ensureNativeStreamStarted());
  }

  /// Stops the native event stream.
  static Future<void> stopNativeStream({bool force = false}) async {
    // Non-forced stop should use the standard mechanism
    if (!force) {
      _listenerCount -= 1;
      if (_listenerCount < 0) _listenerCount = 0;
      await _maybeStopNativeStream();
      return;
    }

    // Forced stop - acquire lock and clean up everything
    final releaseLock = await _acquireLock();

    try {
      // Cancel subscription
      final subscription = _nativeSubscription;
      _nativeSubscription = null;
      await subscription?.cancel();

      // Close controllers
      final controller = _eventController;
      _eventController = null;
      _listenerCount = 0;
      await controller?.close();

      final blockedController = _blockedEventsController;
      _blockedEventsController = null;
      await blockedController?.close();

      // Reset spoof detection
      disableSpoofDetection();
    } finally {
      releaseLock();
    }
  }
}
