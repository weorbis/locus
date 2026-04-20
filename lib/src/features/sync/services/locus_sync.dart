import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/core/locus_headless.dart' show headlessDispatcher;
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_streams.dart';
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
  ///
  /// Sync starts ACTIVE when Config.url is set. Pause is a transport-level state
  /// driven by the native side (401/403 auto-pause with cross-restart persistence)
  /// or by an explicit [pause] call from the host app. Domain gating belongs in
  /// [setPreSyncValidator], not here.
  ///
  /// This field is kept in sync with native via the `syncPauseChange` event on
  /// the main events stream — the native side is the single source of truth;
  /// this is just a cached projection for synchronous reads.
  static bool _isPaused = false;
  static String? _pauseReason;
  static StreamController<SyncPauseState>? _pauseChangesController;
  // ignore: cancel_subscriptions - lives for the lifetime of the plugin;
  // released explicitly in resetPauseState() called by Locus.destroy().
  static StreamSubscription<GeolocationEvent<dynamic>>? _pauseEventSubscription;

  /// Whether sync is currently paused, as of the most recent `syncPauseChange`
  /// event from native. The getter is synchronous so UI code can bind to it
  /// directly; use [pauseChanges] for reactive updates.
  static bool get isPaused => _isPaused;

  /// Why sync is paused, mirroring the `reason` emitted by native on the last
  /// transition. Null when unpaused. Values: `"app"` (explicit [pause]),
  /// `"http_401"`, `"http_403"`.
  static String? get pauseReason => _pauseReason;

  /// Broadcast stream that emits whenever the native pause state changes.
  /// Subscribe from UI to render a pause/auth-expired indicator without polling.
  /// A single initial event carrying the current state is emitted by native as
  /// soon as the events stream attaches (via `LocusContainer.replayInitialState`
  /// / `SwiftLocusPlugin.onListen`), so late subscribers always see the truth.
  static Stream<SyncPauseState> get pauseChanges {
    _pauseChangesController ??=
        StreamController<SyncPauseState>.broadcast(onListen: _ensurePauseBridge);
    _ensurePauseBridge();
    return _pauseChangesController!.stream;
  }

  /// Subscribes (once) to the main events stream, filters for `syncPauseChange`,
  /// updates the cached projection, and forwards to [pauseChanges] subscribers.
  /// Idempotent — safe to call from multiple entry points (pause, resume,
  /// pauseChanges getter).
  static void _ensurePauseBridge() {
    if (_pauseEventSubscription != null) return;
    _pauseEventSubscription = LocusStreams.events
        .where((e) => e.type == EventType.syncPauseChange)
        .listen((event) {
      final state = event.data;
      if (state is! SyncPauseState) return;
      _isPaused = state.isPaused;
      _pauseReason = state.reason;
      _pauseChangesController?.add(state);
    });
  }

  /// Tears down pause-state infrastructure. Called by `Locus.destroy()` via
  /// `LocusLifecycle.destroy` so static state doesn't leak across host-app
  /// test setUp/tearDown cycles.
  static Future<void> resetPauseState() async {
    await _pauseEventSubscription?.cancel();
    _pauseEventSubscription = null;
    await _pauseChangesController?.close();
    _pauseChangesController = null;
    _isPaused = false;
    _pauseReason = null;
  }

  /// Pre-sync validator callback.
  static PreSyncValidator? _preSyncValidator;

  /// Foreground headers callback for native 401 recovery.
  static Future<Map<String, String>> Function()? _foregroundHeadersCallback;

  // ============================================================
  // Standard Sync Methods
  // ============================================================

  /// Pauses all sync operations.
  ///
  /// Locations will continue to be collected but won't be synced
  /// until [resume] is called.
  static Future<void> pause() async {
    _isPaused = true;
    await LocusChannels.methods.invokeMethod('pauseSync');
  }

  /// Triggers an immediate sync of pending locations.
  static Future<bool> sync() async {
    if (_isPaused) {
      debugPrint(
          '[Locus] sync() skipped: sync is paused. Call Locus.dataSync.resume() to clear (e.g. after refreshing auth).');
      return false;
    }
    final result = await LocusChannels.methods.invokeMethod('sync');
    return result == true;
  }

  /// Returns whether sync is ready to proceed (not paused and URL configured).
  ///
  /// Use this to check if sync can proceed without calling [resume] first.
  static Future<bool> isSyncReady() async {
    if (_isPaused) {
      debugPrint(
          '[Locus] isSyncReady() skipped: sync is paused. Call Locus.dataSync.resume() to clear.');
      return false;
    }
    try {
      final result = await LocusChannels.methods.invokeMethod('getSyncState');
      if (result is Map) {
        final state = Map<String, dynamic>.from(result);
        return state['urlConfigured'] == true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Resumes syncing after a transport-level pause (typically after refreshing
  /// auth credentials following a 401/403) or after an explicit [pause] call.
  ///
  /// ```dart
  /// // After refreshing the auth token stored by your app:
  /// await Locus.dataSync.resume();
  /// ```
  ///
  /// Sync is active by default when `Config.url` is set — you do NOT need to
  /// call [resume] during normal initialization. Only call it to recover from
  /// a persisted auth-failure pause or an earlier [pause] call.
  static Future<bool> resume() async {
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
    _setupSyncBodyChannel();
    _preSyncValidator = validator;
  }

  /// Clears the pre-sync validator callback.
  static void clearPreSyncValidator() {
    _preSyncValidator = null;
  }

  /// Sets the foreground headers callback for native 401 recovery.
  static void setForegroundHeadersCallback(
    Future<Map<String, String>> Function()? callback,
  ) {
    _setupSyncBodyChannel();
    _foregroundHeadersCallback = callback;
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

  /// Refreshes dynamic headers via the foreground callback.
  ///
  /// Called by native side on 401 when method channel is available.
  static Future<Map<String, String>?> refreshDynamicHeaders() async {
    if (_foregroundHeadersCallback == null) return null;
    try {
      return await _foregroundHeadersCallback!();
    } catch (e) {
      debugPrint('[Locus] Error refreshing dynamic headers: $e');
      return null;
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

  /// Registers a headless-compatible pre-sync validator.
  static Future<void> registerHeadlessPreSyncValidator(
    HeadlessPreSyncValidator validator,
  ) async {
    _setupHeadlessValidationChannel();

    final dispatcherHandle = PluginUtilities.getCallbackHandle(
      _headlessValidationDispatcher,
    );
    final callbackHandle = PluginUtilities.getCallbackHandle(validator);

    if (dispatcherHandle == null || callbackHandle == null) {
      throw StateError(
        'Failed to register headless pre-sync validator. '
        'Ensure the callback is top-level or static and annotated with @pragma("vm:entry-point").',
      );
    }

    await LocusChannels.methods.invokeMethod(
      'registerHeadlessValidationCallback',
      {
        'dispatcher': dispatcherHandle.toRawHandle(),
        'callback': callbackHandle.toRawHandle(),
      },
    );
  }

  /// Registers a headless-compatible dynamic headers callback.
  static Future<void> registerHeadlessHeadersCallback(
    HeadlessHeadersCallback callback,
  ) async {
    _setupHeadlessHeadersChannel();

    final dispatcherHandle = PluginUtilities.getCallbackHandle(
      _headlessHeadersDispatcher,
    );
    final callbackHandle = PluginUtilities.getCallbackHandle(callback);

    if (dispatcherHandle == null || callbackHandle == null) {
      throw StateError(
        'Failed to register headless headers callback. '
        'Ensure the callback is top-level or static and annotated with @pragma("vm:entry-point").',
      );
    }

    await LocusChannels.methods.invokeMethod(
      'registerHeadlessHeadersCallback',
      {
        'dispatcher': dispatcherHandle.toRawHandle(),
        'callback': callbackHandle.toRawHandle(),
      },
    );
  }

  /// Returns the native RouteHistory backlog state.
  static Future<LocationSyncBacklog> getBacklog() async {
    final result = await LocusChannels.methods.invokeMethod(
      'getLocationSyncBacklog',
    );
    if (result is Map) {
      return LocationSyncBacklog.fromMap(Map<String, dynamic>.from(result));
    }
    return const LocationSyncBacklog(
      pendingLocationCount: 0,
      pendingBatchCount: 0,
      isPaused: false,
      quarantinedLocationCount: 0,
      groups: [],
    );
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
  static bool _headlessValidationChannelSetup = false;
  static bool _headlessHeadersChannelSetup = false;

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

        case 'refreshDynamicHeaders':
          return refreshDynamicHeaders();

        default:
          return null;
      }
    });
  }

  static void _setupHeadlessValidationChannel() {
    if (_headlessValidationChannelSetup) return;
    _headlessValidationChannelSetup = true;

    LocusChannels.headlessValidation.setMethodCallHandler((call) async {
      if (call.method != 'validatePreSync') {
        return true;
      }

      final callback =
          await _resolveTypedCallback<Future<bool> Function(SyncBodyContext)>(
              call.arguments);
      if (callback == null) {
        return true;
      }

      try {
        final context = _extractSyncBodyContext(call.arguments);
        return await callback(context);
      } catch (e) {
        debugPrint('Locus: Error in headless pre-sync validator: $e');
        return false;
      }
    });
  }

  static void _setupHeadlessHeadersChannel() {
    if (_headlessHeadersChannelSetup) return;
    _headlessHeadersChannelSetup = true;

    LocusChannels.headlessHeaders.setMethodCallHandler((call) async {
      if (call.method != 'getHeaders') {
        return <String, String>{};
      }

      final callback =
          await _resolveTypedCallback<Future<Map<String, String>> Function()>(
              call.arguments);
      if (callback == null) {
        return <String, String>{};
      }

      try {
        return await callback();
      } catch (e) {
        debugPrint('Locus: Error in headless headers callback: $e');
        return <String, String>{};
      }
    });
  }

  static Future<T?> _resolveTypedCallback<T>(Object? rawArgs) async {
    final args = Map<String, dynamic>.from(rawArgs as Map? ?? const {});
    final rawHandle = args['callbackHandle'] as int?;
    if (rawHandle == null) {
      return null;
    }
    final handle = CallbackHandle.fromRawHandle(rawHandle);
    return PluginUtilities.getCallbackFromHandle(handle) as T?;
  }

  static SyncBodyContext _extractSyncBodyContext(Object? rawArgs) {
    final args = Map<String, dynamic>.from(rawArgs as Map? ?? const {});
    final payload = args['payload'];
    if (payload is String) {
      return SyncBodyContext.fromMap(
        Map<String, dynamic>.from(jsonDecode(payload) as Map),
      );
    }
    if (payload is Map) {
      return SyncBodyContext.fromMap(Map<String, dynamic>.from(payload));
    }
    return SyncBodyContext.fromMap(args);
  }

  // ============================================================
  // Headless Dispatcher
  // ============================================================

  /// Entry point for headless sync body building.
  /// NOTE: The actual headless handler is now unified in [headlessDispatcher]
  /// (top-level function in locus_headless.dart) which handles both
  /// 'headlessEvent' and 'headlessBuildSyncBody' methods on the same channel
  /// to avoid handler overwrite conflicts.
  @pragma('vm:entry-point')
  static void _headlessSyncBodyDispatcher() {
    // Delegate to the unified headless dispatcher
    headlessDispatcher();
  }

  @pragma('vm:entry-point')
  static void _headlessValidationDispatcher() {
    WidgetsFlutterBinding.ensureInitialized();
    _setupHeadlessValidationChannel();
  }

  @pragma('vm:entry-point')
  static void _headlessHeadersDispatcher() {
    WidgetsFlutterBinding.ensureInitialized();
    _setupHeadlessHeadersChannel();
  }
}
