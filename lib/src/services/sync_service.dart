/// Sync service interface for v2.0 API.
///
/// Provides a clean, organized API for data synchronization.
/// Access via `Locus.sync`.
library;

import 'dart:async';

import 'package:locus/src/models.dart';
import 'package:locus/src/core/locus_interface.dart';

/// Callback for pre-sync validation.
///
/// Invoked before each sync attempt. Return `true` to proceed with sync,
/// `false` to skip this sync and keep locations queued.
///
/// [locations] - The locations about to be synced.
/// [extras] - The current config extras (context data).
typedef PreSyncValidator =
    Future<bool> Function(
      List<Location> locations,
      Map<String, dynamic> extras,
    );

/// Service interface for sync operations.
///
/// Handles synchronization of location data with remote servers,
/// including offline queue management and retry logic.
///
/// Example:
/// ```dart
/// // Trigger immediate sync
/// await Locus.sync.now();
///
/// // Listen to sync events
/// Locus.sync.events.listen((event) {
///   if (event.success) {
///     print('Synced ${event.count} locations');
///   } else {
///     print('Sync failed: ${event.statusCode}');
///   }
/// });
///
/// // Set sync policy
/// await Locus.sync.setPolicy(SyncPolicy(
///   minBatteryLevel: 20,
///   requireWifi: true,
///   maxRetries: 3,
/// ));
///
/// // Enqueue custom payload
/// await Locus.sync.enqueue({
///   'type': 'check-in',
///   'locationId': 'store-123',
/// });
/// ```
abstract class SyncService {
  /// Stream of HTTP sync events.
  Stream<HttpEvent> get events;

  /// Stream of connectivity changes.
  Stream<ConnectivityChangeEvent> get connectivityEvents;

  /// Whether sync is currently paused.
  ///
  /// When paused, no HTTP sync requests will be sent until [resume] is called.
  bool get isPaused;

  /// Triggers an immediate sync of pending locations.
  Future<bool> now();

  /// Pauses all sync operations.
  ///
  /// Use this to prevent syncs while the app is restoring state.
  /// Call [resume] when ready to allow syncs again.
  ///
  /// Example:
  /// ```dart
  /// // Pause sync during state restoration
  /// await Locus.sync.pause();
  ///
  /// // Restore context from backend
  /// final task = await findInProgressTask();
  /// await Locus.setConfig(Config(extras: {'task_id': task.id}));
  ///
  /// // Resume sync with updated context
  /// await Locus.sync.resume();
  /// ```
  Future<void> pause();

  /// Resumes sync after a pause.
  ///
  /// This will trigger an immediate sync attempt if there are pending locations.
  Future<bool> resume();

  /// Sets a pre-sync validation callback.
  ///
  /// The callback is invoked before each sync attempt, giving the app
  /// an opportunity to:
  /// - Validate the current context (extras)
  /// - Update the config with correct values
  /// - Cancel the sync by returning false
  ///
  /// Return `true` to proceed with sync, `false` to skip this sync attempt.
  /// The locations will remain queued for the next sync attempt.
  ///
  /// Example:
  /// ```dart
  /// Locus.sync.setPreSyncValidator((locations, extras) async {
  ///   // Check if we have required context
  ///   if (extras['task_id'] == null) {
  ///     // Try to restore context
  ///     final task = await findInProgressTask();
  ///     if (task != null) {
  ///       await Locus.setConfig(Config(extras: {
  ///         'task_id': task.id,
  ///         'owner_id': task.ownerId,
  ///       }));
  ///       return true; // Proceed with updated context
  ///     }
  ///     return false; // Cancel this sync
  ///   }
  ///   return true; // Context is valid
  /// });
  /// ```
  void setPreSyncValidator(PreSyncValidator? validator);

  /// Clears the pre-sync validator callback.
  void clearPreSyncValidator();

  /// Sets the sync policy.
  Future<void> setPolicy(SyncPolicy policy);

  /// Evaluates if sync should proceed based on current conditions.
  Future<SyncDecision> evaluatePolicy({required SyncPolicy policy});

  /// Sets a callback to build custom HTTP sync body.
  Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder);

  /// Clears the sync body builder callback.
  void clearSyncBodyBuilder();

  /// Registers a headless-compatible sync body builder.
  ///
  /// The callback must be a top-level or static function (not a closure)
  /// to work in headless/terminated mode.
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  );

  /// Sets a callback to provide dynamic HTTP headers.
  void setHeadersCallback(Future<Map<String, String>> Function()? callback);

  /// Clears the dynamic headers callback.
  void clearHeadersCallback();

  /// Manually triggers a header update.
  Future<void> refreshHeaders();

  // ============================================================
  // Queue Operations
  // ============================================================

  /// Enqueues a custom payload for offline-first delivery.
  ///
  /// [payload] - The data to enqueue.
  /// [type] - Optional type identifier for the payload.
  /// [idempotencyKey] - Optional key to prevent duplicate submissions.
  Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  });

  /// Returns queued payloads.
  Future<List<QueueItem>> getQueue({int? limit});

  /// Clears all queued payloads.
  Future<void> clearQueue();

  /// Attempts to sync queued payloads immediately.
  ///
  /// Returns the number of items successfully synced.
  Future<int> syncQueue({int? limit});

  // ============================================================
  // Subscriptions
  // ============================================================

  /// Subscribes to HTTP sync events.
  StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  });

  /// Subscribes to connectivity change events.
  StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  });
}
