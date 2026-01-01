import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:locus/src/events/events.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/event_mapper.dart';
import 'package:locus/src/services/spoof_detection.dart';
import 'package:locus/src/services/error_recovery.dart';
import 'locus_channels.dart';

/// Stream management for geolocation events.
class LocusStreams {
  static StreamController<GeolocationEvent<dynamic>>? _eventController;
  static StreamController<SpoofDetectionEvent>? _blockedEventsController;
  static StreamSubscription<dynamic>? _nativeSubscription;
  static int _listenerCount = 0;
  static bool _isStarting = false;
  static bool _isStopping = false;
  static Completer<void>? _streamOperationLock;

  // Spoof detection integration
  static SpoofDetector? _spoofDetector;
  static bool _spoofDetectionEnabled = false;

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

  static void _onListen() {
    _listenerCount += 1;
    // Schedule start asynchronously to avoid blocking
    Future.microtask(() => _ensureNativeStreamStarted());
  }

  static void _onCancel() {
    _listenerCount -= 1;
    if (_listenerCount < 0) _listenerCount = 0;
    // Schedule stop asynchronously
    Future.microtask(() => _maybeStopNativeStream());
  }

  /// Ensures the native stream is started.
  static Future<void> _ensureNativeStreamStarted() async {
    // Wait for any in-progress operation
    while (_streamOperationLock != null) {
      await _streamOperationLock!.future;
    }

    // Check if already running or no listeners
    if (_nativeSubscription != null || _isStarting || _listenerCount <= 0) {
      return;
    }

    _streamOperationLock = Completer<void>();
    _isStarting = true;

    try {
      _nativeSubscription =
          LocusChannels.events.receiveBroadcastStream().listen(
        (event) {
          try {
            final mapped = EventMapper.mapToEvent(event);
            _processEvent(mapped);
          } catch (e, stack) {
            debugPrint('[Locus] Event mapping error: $e');
            _handleStreamError(e, stack, 'event_mapping');
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[Locus] Stream error: $error');
          _handleStreamError(error, stackTrace, 'stream');
        },
      );
    } catch (e) {
      debugPrint('[Locus] Failed to start native stream: $e');
    } finally {
      _isStarting = false;
      _streamOperationLock?.complete();
      _streamOperationLock = null;
    }
  }

  /// Processes a mapped event, applying spoof detection if enabled.
  static void _processEvent(GeolocationEvent<dynamic> event) {
    // Only apply spoof detection to location-type events
    if (_spoofDetectionEnabled &&
        _spoofDetector != null &&
        event.type == EventType.location &&
        event.data is Location) {
      final location = event.data as Location;
      final spoofResult = _spoofDetector!.analyze(location);

      // If spoof detection returned a result (something was detected)
      if (spoofResult != null) {
        if (spoofResult.wasBlocked) {
          // Emit to blocked events stream for monitoring
          _blockedEventsController?.add(spoofResult);
          debugPrint(
              '[Locus] Blocked spoofed location: ${spoofResult.factors}');
          return; // Don't add to main event stream
        }

        // Detected but not blocked, log but still emit
        debugPrint(
            '[Locus] Spoofed location detected (not blocked): ${spoofResult.factors}');
      }
    }

    // Add to main event stream
    _eventController?.add(event);
  }

  /// Handles stream errors through the error recovery system.
  static void _handleStreamError(
      Object error, StackTrace stackTrace, String operation) {
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

      // Handle error asynchronously
      Future.microtask(() async {
        final action = await errorManager.handleError(locusError);
        debugPrint('[Locus] Error recovery action: $action');

        // If action is not 'ignore', propagate to listeners
        if (action != RecoveryAction.ignore) {
          _eventController?.addError(error, stackTrace);
        }
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

  /// Maybe stops the native stream if no listeners remain.
  static Future<void> _maybeStopNativeStream() async {
    // Wait for any in-progress operation
    while (_streamOperationLock != null) {
      await _streamOperationLock!.future;
    }

    // Check if we should stop
    if (_listenerCount > 0 || _nativeSubscription == null || _isStopping) {
      return;
    }

    _streamOperationLock = Completer<void>();
    _isStopping = true;

    try {
      final subscription = _nativeSubscription;
      _nativeSubscription = null;
      await subscription?.cancel();
    } finally {
      _isStopping = false;
      _streamOperationLock?.complete();
      _streamOperationLock = null;
    }
  }

  /// Starts the native event stream (legacy - now handled automatically).
  @Deprecated('Use events getter instead, streams are managed automatically')
  static void startNativeStream() {
    _listenerCount += 1;
    Future.microtask(() => _ensureNativeStreamStarted());
  }

  /// Stops the native event stream.
  static Future<void> stopNativeStream({bool force = false}) async {
    // Wait for any in-progress operation
    while (_streamOperationLock != null) {
      await _streamOperationLock!.future;
    }

    // Non-forced stop should use the standard mechanism
    if (!force) {
      _listenerCount -= 1;
      if (_listenerCount < 0) _listenerCount = 0;
      await _maybeStopNativeStream();
      return;
    }

    // Forced stop - clean up everything
    _streamOperationLock = Completer<void>();

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
      _streamOperationLock?.complete();
      _streamOperationLock = null;
    }
  }
}
