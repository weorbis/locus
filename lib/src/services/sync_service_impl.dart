/// Sync service implementation for v2.0 API.
library;

import 'dart:async';

import 'package:locus/src/models.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/services/sync_service.dart';

/// Implementation of [SyncService] using method channel.
class SyncServiceImpl implements SyncService {
  /// Creates a sync service with the given Locus interface provider.
  SyncServiceImpl(this._instanceProvider);

  final LocusInterface Function() _instanceProvider;

  LocusInterface get _instance => _instanceProvider();

  @override
  Stream<HttpEvent> get events => _instance.httpStream;

  @override
  Stream<ConnectivityChangeEvent> get connectivityEvents =>
      _instance.connectivityStream;

  @override
  Future<bool> now() => _instance.sync();

  @override
  Future<bool> resume() => _instance.resumeSync();

  @override
  Future<void> setPolicy(SyncPolicy policy) => _instance.setSyncPolicy(policy);

  @override
  Future<SyncDecision> evaluatePolicy({required SyncPolicy policy}) =>
      _instance.evaluateSyncPolicy(policy: policy);

  @override
  Future<void> setSyncBodyBuilder(SyncBodyBuilder? builder) =>
      _instance.setSyncBodyBuilder(builder);

  @override
  void clearSyncBodyBuilder() => _instance.clearSyncBodyBuilder();

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(
    Future<JsonMap> Function(SyncBodyContext context) builder,
  ) =>
      _instance.registerHeadlessSyncBodyBuilder(builder);

  @override
  void setHeadersCallback(Future<Map<String, String>> Function()? callback) =>
      _instance.setHeadersCallback(callback);

  @override
  void clearHeadersCallback() => _instance.clearHeadersCallback();

  @override
  Future<void> refreshHeaders() => _instance.refreshHeaders();

  // ============================================================
  // Queue Operations
  // ============================================================

  @override
  Future<String> enqueue(
    JsonMap payload, {
    String? type,
    String? idempotencyKey,
  }) =>
      _instance.enqueue(payload, type: type, idempotencyKey: idempotencyKey);

  @override
  Future<List<QueueItem>> getQueue({int? limit}) =>
      _instance.getQueue(limit: limit);

  @override
  Future<void> clearQueue() => _instance.clearQueue();

  @override
  Future<int> syncQueue({int? limit}) => _instance.syncQueue(limit: limit);

  // ============================================================
  // Subscriptions
  // ============================================================

  @override
  StreamSubscription<HttpEvent> onHttp(
    void Function(HttpEvent) callback, {
    Function? onError,
  }) =>
      _instance.onHttp(callback, onError: onError);

  @override
  StreamSubscription<ConnectivityChangeEvent> onConnectivityChange(
    void Function(ConnectivityChangeEvent) callback, {
    Function? onError,
  }) =>
      _instance.onConnectivityChange(callback, onError: onError);
}
