import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/services/sync_service.dart';

/// Sync operations.
class LocusSync {
  // ============================================================
  // Sync Body Builder State
  // ============================================================

  /// The current sync body builder callback (foreground only).
  static SyncBodyBuilder? _syncBodyBuilder;

  /// Whether we have a registered headless builder.
  static bool _hasHeadlessBuilder = false;

  // ============================================================
  // Sync Pause State
  // ============================================================

  /// Whether sync is currently paused.
  static bool _isPaused = false;

  /// Whether sync is currently paused.
  static bool get isPaused => _isPaused;

  /// Pre-sync validator callback.
  static PreSyncValidator? _preSyncValidator;

  // ============================================================
  // Standard Sync Methods
  // ============================================================

  /// Pauses all sync operations.
  ///
  /// Locations will continue to be collected but won't be synced
  /// until [resumeSync] is called.
  static Future<void> pause() async {
    _isPaused = true;
    await LocusChannels.methods.invokeMethod('pauseSync');
  }

  /// Triggers an immediate sync of pending locations.
  static Future<bool> sync() async {
    if (_isPaused) return false;
    final result = await LocusChannels.methods.invokeMethod('sync');
    return result == true;
  }

  /// Resumes syncing after a pause (e.g., token refresh).
  static Future<bool> resumeSync() async {
    _isPaused = false;
    final result = await LocusChannels.methods.invokeMethod('resumeSync');
    return result == true;
  }

  /// Destroys all stored locations.
  static Future<bool> destroyLocations() async {
    final result = await LocusChannels.methods.invokeMethod('destroyLocations');
    return result == true;
  }

  // ============================================================
  // Pre-Sync Validation
  // ============================================================

  /// Sets a callback for pre-sync validation.
  ///
  /// The callback is invoked before each sync attempt. Return `true` to
  /// proceed with the sync, `false` to skip and keep locations queued.
  static void setPreSyncValidator(PreSyncValidator? validator) {
    _preSyncValidator = validator;
  }

  /// Clears the pre-sync validator callback.
  static void clearPreSyncValidator() {
    _preSyncValidator = null;
  }

  /// Validates sync with the registered validator.
  ///
  /// Called by native side before each sync attempt via method channel.
  /// Returns true if sync should proceed, false to skip.
  static Future<bool> validatePreSync(
    List<Location> locations,
    JsonMap extras,
  ) async {
    if (_preSyncValidator == null) return true;
    try {
      return await _preSyncValidator!(locations, extras);
    } catch (e) {
      debugPrint('[Locus] Pre-sync validator threw an error: $e');
      return false; // Skip sync on error
    }
  }

  /// Enqueues a custom payload for offline-first delivery.
  static Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) async {
    final result = await LocusChannels.methods.invokeMethod('enqueue', {
      'payload': payload,
      if (type != null) 'type': type,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
    if (result is String && result.isNotEmpty) {
      return result;
    }
    throw PlatformException(
      code: 'ENQUEUE_FAILED',
      message: 'Native enqueue did not return an id',
      details: result,
    );
  }

  /// Returns queued payloads.
  static Future<List<QueueItem>> getQueue({int? limit}) async {
    final result = await LocusChannels.methods.invokeMethod(
      'getQueue',
      limit == null ? null : {'limit': limit},
    );
    if (result is List) {
      return result
          .map(
            (item) => QueueItem.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    }
    return [];
  }

  /// Clears all queued payloads.
  static Future<void> clearQueue() async {
    await LocusChannels.methods.invokeMethod('clearQueue');
  }

  /// Attempts to sync queued payloads immediately.
  static Future<int> syncQueue({int? limit}) async {
    final result = await LocusChannels.methods.invokeMethod(
      'syncQueue',
      limit == null ? null : {'limit': limit},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  // ============================================================
  // Sync Body Builder
  // ============================================================

  /// Sets a callback to build custom HTTP sync body.
  static Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder) async {
    _setupSyncBodyChannel();

    // Notify native side that we have a Dart-side builder
    try {
      await LocusChannels.methods.invokeMethod(
        'setSyncBodyBuilderEnabled',
        builder != null,
      );
      // Only set the builder after successful native call
      _syncBodyBuilder = builder;
    } on PlatformException catch (e) {
      debugPrint(
        '[Locus] ERROR: Failed to set sync body builder on native side: $e',
      );
      // Ensure builder is not set on error
      _syncBodyBuilder = null;
      rethrow;
    } catch (e) {
      debugPrint(
        '[Locus] ERROR: Unexpected error setting sync body builder: $e',
      );
      _syncBodyBuilder = null;
      rethrow;
    }
  }

  /// Clears the sync body builder callback.
  static Future<void> clearSyncBodyBuilder() async {
    _syncBodyBuilder = null;
    await LocusChannels.methods.invokeMethod(
      'setSyncBodyBuilderEnabled',
      false,
    );
  }

  /// Registers a headless-compatible sync body builder.
  ///
  /// The builder must be a **top-level or static function** (not a closure).
  /// Closures capture state that cannot be serialized for background execution.
  static Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) async {
    final dispatcherHandle = PluginUtilities.getCallbackHandle(
      _headlessSyncBodyDispatcher,
    );
    final callbackHandle = PluginUtilities.getCallbackHandle(builder);

    if (dispatcherHandle == null || callbackHandle == null) {
      debugPrint(
        '[Locus] ERROR: Failed to register headless sync body builder.',
      );
      debugPrint('[Locus]   Could not obtain callback handles.');
      debugPrint(
        '[Locus]   Ensure your builder is a top-level or static function, not a closure.',
      );
      debugPrint('[Locus]   Example:');
      debugPrint('[Locus]     @pragma("vm:entry-point")');
      debugPrint(
        '[Locus]     Future<Map<String, dynamic>> buildSyncBody(SyncBodyContext ctx) async {',
      );
      debugPrint(
        '[Locus]       return {"locations": ctx.locations.map((l) => l.toJson()).toList()};',
      );
      debugPrint('[Locus]     }');
      return false;
    }

    final result = await LocusChannels.methods
        .invokeMethod('registerHeadlessSyncBodyBuilder', {
          'dispatcher': dispatcherHandle.toRawHandle(),
          'callback': callbackHandle.toRawHandle(),
        });

    _hasHeadlessBuilder = result == true;
    return _hasHeadlessBuilder;
  }

  /// Whether a sync body builder (foreground or headless) is available.
  static bool get hasSyncBodyBuilder =>
      _syncBodyBuilder != null || _hasHeadlessBuilder;

  /// Builds the sync body using the registered callback.
  /// Returns null if no builder is registered.
  static Future<JsonMap?> buildSyncBody(
    List<Location> locations,
    JsonMap extras,
  ) async {
    // Use null-aware call to prevent race condition
    return _syncBodyBuilder?.call(locations, extras);
  }

  // ============================================================
  // Channel Setup
  // ============================================================

  static bool _channelSetup = false;

  /// Sets up the method channel handler for sync body requests from native.
  static void _setupSyncBodyChannel() {
    if (_channelSetup) return;
    _channelSetup = true;

    LocusChannels.methods.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'buildSyncBody':
          if (_syncBodyBuilder == null) {
            return null;
          }

          final args = Map<String, dynamic>.from(call.arguments as Map);
          final context = SyncBodyContext.fromMap(args);

          try {
            final body = await _syncBodyBuilder!(
              context.locations,
              context.extras,
            );
            return body;
          } catch (e) {
            debugPrint('Locus: Error in sync body builder: $e');
            return null;
          }

        case 'validatePreSync':
          // Pre-sync validation call from native
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final context = SyncBodyContext.fromMap(args);
          return validatePreSync(context.locations, context.extras);

        default:
          return null;
      }
    });
  }

  // ============================================================
  // Headless Dispatcher
  // ============================================================

  /// Entry point for headless sync body building.
  @pragma('vm:entry-point')
  static void _headlessSyncBodyDispatcher() {
    WidgetsFlutterBinding.ensureInitialized();

    LocusChannels.headless.setMethodCallHandler((call) async {
      if (call.method != 'headlessBuildSyncBody') {
        return null;
      }

      final args = Map<String, dynamic>.from(call.arguments as Map);
      final rawHandle = args['callbackHandle'] as int?;

      if (rawHandle == null) {
        return null;
      }

      final handle = CallbackHandle.fromRawHandle(rawHandle);
      final callback =
          PluginUtilities.getCallbackFromHandle(handle)
              as Future<JsonMap> Function(SyncBodyContext)?;

      if (callback == null) {
        debugPrint('Locus: Could not resolve headless sync body callback');
        return null;
      }

      try {
        final context = SyncBodyContext.fromMap(args);
        final body = await callback(context);
        return body;
      } catch (e) {
        debugPrint('Locus: Error in headless sync body builder: $e');
        return null;
      }
    });
  }
}
