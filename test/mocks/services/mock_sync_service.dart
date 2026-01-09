/// Mock implementation of SyncService for testing.
library;

import 'dart:async';

import 'package:locus/locus.dart';

/// Mock sync service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockSyncService();
///
/// // Enqueue items
/// await mock.enqueue({'type': 'location', 'data': {...}});
///
/// // Simulate successful sync
/// mock.simulateSync(success: true);
///
/// // Listen to events
/// mock.events.listen((event) {
///   print('Sync ${event.success ? 'succeeded' : 'failed'}');
/// });
/// ```
class MockSyncService implements SyncService {
  final List<QueueItem> _queue = [];
  SyncPolicy? _policy;
  Future<Map<String, String>> Function()? _headersCallback;
  bool _isPaused = false;
  int _syncCount = 0;

  final _eventsController = StreamController<HttpEvent>.broadcast();
  final _connectivityController =
      StreamController<ConnectivityChangeEvent>.broadcast();

  @override
  Stream<HttpEvent> get events => _eventsController.stream;

  @override
  Stream<ConnectivityChangeEvent> get connectivityEvents =>
      _connectivityController.stream;

  @override
  Future<bool> now() async {
    if (_isPaused) return false;

    if (_queue.isEmpty) {
      return true; // Nothing to sync
    }

    _syncCount++;

    // Simulate successful sync by default
    const event = HttpEvent(
      status: 200,
      ok: true,
      responseText: '{"status":"ok"}',
    );

    _eventsController.add(event);
    _queue.clear();

    return true;
  }

  @override
  Future<bool> resume() async {
    _isPaused = false;
    return true;
  }

  @override
  bool get isPaused => _isPaused;

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  PreSyncValidator? _preSyncValidator;

  @override
  void setPreSyncValidator(PreSyncValidator? validator) {
    _preSyncValidator = validator;
  }

  @override
  void clearPreSyncValidator() {
    _preSyncValidator = null;
  }

  @override
  Future<void> setPolicy(SyncPolicy policy) async {
    _policy = policy;
  }

  @override
  Future<SyncDecision> evaluatePolicy({required SyncPolicy policy}) async {
    // Simple mock evaluation
    return const SyncDecision(
      shouldSync: true,
      reason: 'Mock always allows sync',
    );
  }

  @override
  Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder) async {
    // Mock implementation doesn't need to store the builder
  }

  @override
  void clearSyncBodyBuilder() {
    // Mock implementation
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) async {
    // Mock implementation always succeeds
    return true;
  }

  @override
  void setHeadersCallback(Future<Map<String, String>> Function()? callback) {
    _headersCallback = callback;
  }

  @override
  void clearHeadersCallback() {
    _headersCallback = null;
  }

  @override
  Future<void> refreshHeaders() async {
    // Trigger headers callback if set
    if (_headersCallback != null) {
      await _headersCallback!();
    }
  }

  // ============================================================
  // Queue Operations
  // ============================================================

  @override
  Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) async {
    final id = 'mock-${_queue.length}-${DateTime.now().millisecondsSinceEpoch}';
    _queue.add(
      QueueItem(
        id: id,
        payload: payload,
        createdAt: DateTime.now(),
        retryCount: 0,
        type: type,
        idempotencyKey: idempotencyKey,
      ),
    );
    return id;
  }

  @override
  Future<List<QueueItem>> getQueue({int? limit}) async {
    if (limit != null && limit < _queue.length) {
      return List.unmodifiable(_queue.sublist(_queue.length - limit));
    }
    return List.unmodifiable(_queue);
  }

  @override
  Future<void> clearQueue() async {
    _queue.clear();
  }

  Future<bool> removeQueueItem(String id) async {
    final initialLength = _queue.length;
    _queue.removeWhere((item) => item.id == id);
    return _queue.length < initialLength;
  }

  Future<int> getQueueSize() async {
    return _queue.length;
  }

  // ============================================================
  // Test Helpers
  // ============================================================

  /// Simulates a sync operation with configurable outcome.
  void simulateSync({
    bool success = true,
    int statusCode = 200,
    String? responseText,
    int? itemCount,
  }) {
    final event = HttpEvent(
      status: statusCode,
      ok: success,
      responseText:
          responseText ?? (success ? '{"status":"ok"}' : '{"error":"failed"}'),
    );

    _eventsController.add(event);

    if (success) {
      _queue.clear();
      _syncCount++;
    }
  }

  /// Simulates a connectivity change event.
  void simulateConnectivityChange(bool connected, {String? networkType}) {
    _connectivityController.add(
      ConnectivityChangeEvent(connected: connected, networkType: networkType),
    );
  }

  /// Gets the current sync policy.
  SyncPolicy? get currentPolicy => _policy;

  /// Number of successful syncs performed.
  int get syncCount => _syncCount;

  /// Current queue length.
  int get queueLength => _queue.length;

  @override
  StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  }) {
    return _eventsController.stream.listen(callback, onError: onError);
  }

  @override
  StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  }) {
    return _connectivityController.stream.listen(callback, onError: onError);
  }

  @override
  Future<int> syncQueue({int? limit}) async {
    if (_queue.isEmpty) return 0;

    final itemsToSync = limit != null && limit < _queue.length
        ? _queue.sublist(0, limit)
        : _queue;

    final count = itemsToSync.length;
    _queue.removeRange(0, count);
    _syncCount++;

    return count;
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _eventsController.close();
    await _connectivityController.close();
  }
}
