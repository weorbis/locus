import 'package:flutter/foundation.dart';

/// Adversarial backend behaviors the mock can simulate. Each mode is
/// deliberately narrow: scenarios should pick exactly one and assert against
/// it, rather than the mock dynamically deciding what to return.
enum MockMode {
  /// 200 OK with an empty JSON body for every request.
  normal,

  /// 401 Unauthorized for every request. Exercises auth-pause.
  auth401,

  /// 403 Forbidden for every request. Exercises auth-pause persistence.
  auth403,

  /// 415 Unsupported Media Type on the first compressed request, then 200
  /// thereafter. Exercises the 60-minute compression-disable fallback.
  http415Once,

  /// 200 OK after a fixed delay (configurable; default 5s).
  /// Exercises the SDK's read-timeout / batch-progress UI surfaces.
  slow,

  /// Closes the TCP connection without sending a response. Exercises the
  /// "no HTTP status" error path.
  drop,

  /// Alternates 200 / 500 per request — odd-numbered (1st, 3rd, 5th, …)
  /// fail, even-numbered succeed. Exercises retry-with-success.
  flaky,

  /// Returns 503 for the first N requests then 200 onward. N defaults to 5.
  /// Exercises drainExhaustedContexts recovery (#34).
  outage,
}

/// One observed inbound HTTP request, captured for assertion in scenarios.
@immutable
class MockRequest {
  const MockRequest({
    required this.at,
    required this.method,
    required this.path,
    required this.headers,
    required this.bodyBytes,
    required this.responseStatus,
  });

  final DateTime at;
  final String method;
  final String path;
  final Map<String, String> headers;

  /// Raw bytes received. May be gzipped — scenarios that care can inspect
  /// `headers['content-encoding']` and decode.
  final Uint8List bodyBytes;

  /// HTTP status the mock returned for this request.
  final int responseStatus;

  bool get isGzipped =>
      (headers['content-encoding'] ?? '').toLowerCase().contains('gzip');

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'method': method,
        'path': path,
        'headers': headers,
        'bodyLength': bodyBytes.length,
        'gzipped': isGzipped,
        'responseStatus': responseStatus,
      };
}

/// In-process HTTP server the example app points its sync layer at.
///
/// Implementations bind to a localhost port, capture every inbound request,
/// and respond per the active [mode]. The runner constructs one mock per
/// scenario that needs it; the same instance can serve back-to-back
/// scenarios with [setMode] + [reset] between them.
abstract class MockBackend {
  /// HTTP base URL the SDK should be configured against, e.g.
  /// `http://127.0.0.1:54321`. Stable for the lifetime of the instance.
  Uri get baseUrl;

  /// Currently active mode.
  MockMode get mode;

  /// Switches the active mode. Takes effect on the next request — there is
  /// no in-flight cancellation.
  Future<void> setMode(MockMode mode);

  /// Total inbound requests since [reset] (or instance creation).
  int get requestCount;

  /// Latest-first capped history. Capacity is implementation-defined but
  /// guaranteed ≥ 100, which is enough for any single scenario.
  List<MockRequest> get recentRequests;

  /// Drops accumulated [recentRequests] and resets [requestCount] to zero.
  /// Mode is preserved.
  Future<void> reset();

  /// Tears down the HTTP server. After dispose the instance is unusable
  /// and a new one must be started.
  Future<void> dispose();
}
