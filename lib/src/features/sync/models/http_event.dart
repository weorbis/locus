import 'package:locus/src/shared/models/json_map.dart';

/// One observation of an HTTP sync attempt made by the SDK.
///
/// Emitted on the foreground event stream as `EventType.http`. Embedders use
/// it for backend health dashboards, auth-failure handling, and metrics.
///
/// [recordsSent] carries the number of stored locations the SDK considered
/// flushed by this attempt. The native side fills it on the success path of
/// batched sync requests; on failures and on non-batched calls it is `null`.
/// Treat it as a best-effort hint — never required for correct decisions.
class HttpEvent {
  const HttpEvent({
    required this.status,
    required this.ok,
    this.responseText,
    this.response,
    this.recordsSent,
  });

  factory HttpEvent.fromMap(JsonMap map) {
    return HttpEvent(
      status: (map['status'] as num?)?.toInt() ?? 0,
      ok: map['ok'] as bool? ?? false,
      responseText: map['responseText'] as String?,
      response: map['response'] as JsonMap?,
      recordsSent: (map['recordsSent'] as num?)?.toInt(),
    );
  }

  /// HTTP status code reported by the backend, or `0` for transport-level
  /// errors (no response was received).
  final int status;

  /// `true` when the SDK considers this attempt a success (HTTP 2xx).
  final bool ok;

  /// Raw response body when available. Truncated by the platform side; do
  /// not parse beyond best-effort.
  final String? responseText;

  /// Parsed response body when the platform was able to decode it as JSON.
  final JsonMap? response;

  /// Number of stored locations the SDK regards as flushed by this attempt.
  ///
  /// Filled on the success path of batched location-sync requests. `null`
  /// for failures, transport errors, queue (non-location) requests, or
  /// platforms that have not yet been instrumented.
  final int? recordsSent;

  JsonMap toMap() => {
        'status': status,
        'ok': ok,
        if (responseText != null) 'responseText': responseText,
        if (response != null) 'response': response,
        if (recordsSent != null) 'recordsSent': recordsSent,
      };
}
