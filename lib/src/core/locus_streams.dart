import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:locus/src/events/events.dart';
import 'package:locus/src/services/event_mapper.dart'; // Corrected import
import 'locus_channels.dart';

/// Stream management for geolocation events.
class LocusStreams {
  static StreamController<GeolocationEvent<dynamic>>? _eventController;
  static StreamSubscription<dynamic>? _nativeSubscription;
  static int _listenerCount = 0;
  static bool _isStarting = false;
  static Completer<void>? _streamOperationLock;

  /// Stream of all geolocation events.
  static Stream<GeolocationEvent<dynamic>> get events {
    _eventController ??= StreamController<GeolocationEvent<dynamic>>.broadcast(
      onListen: startNativeStream,
      onCancel: () => stopNativeStream(),
    );
    return _eventController!.stream;
  }

  /// Starts the native event stream.
  static void startNativeStream() {
    _listenerCount += 1;
    if (_nativeSubscription != null || _isStarting) {
      return;
    }
    _isStarting = true;
    try {
      _nativeSubscription =
          LocusChannels.events.receiveBroadcastStream().listen(
        (event) {
          try {
            _eventController?.add(EventMapper.mapToEvent(event));
          } catch (e, stack) {
            debugPrint('[Locus] Event mapping error: $e');
            _eventController?.addError(e, stack);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[Locus] Stream error: $error');
          _eventController?.addError(error, stackTrace);
        },
      );
    } finally {
      _isStarting = false;
    }
  }

  /// Stops the native event stream.
  static Future<void> stopNativeStream({bool force = false}) async {
    // Wait for any in-progress operation to complete
    if (_streamOperationLock != null) {
      await _streamOperationLock!.future;
    }

    // Create a new lock for this operation
    _streamOperationLock = Completer<void>();

    try {
      _listenerCount -= 1;

      // Ensure count doesn't go below zero
      if (_listenerCount < 0) _listenerCount = 0;

      // Only proceed with cleanup if force is set or no listeners remain
      if (_listenerCount > 0 && !force) {
        return;
      }

      // Capture subscription reference before nulling
      final subscription = _nativeSubscription;
      _nativeSubscription = null;

      // Cancel the native subscription
      if (subscription != null) {
        await subscription.cancel();
      }

      // Check if a new listener was added during the await
      // This is the key race condition fix
      if (!force && _listenerCount > 0) {
        // A listener was added while we were cancelling, restart immediately
        startNativeStream();
        return;
      }

      // Full cleanup only when truly done
      if (force || _listenerCount == 0) {
        final controller = _eventController;
        _eventController = null;
        _listenerCount = 0;
        await controller?.close();
      }
    } finally {
      // Release the lock
      _streamOperationLock?.complete();
      _streamOperationLock = null;
    }
  }
}
