import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:locus_example/mock_backend/mock_backend.dart';

/// Maximum number of recent requests retained for inspection. The interface
/// guarantees at least 100; we hold exactly 100 so the UI list and exported
/// JSON have a predictable upper bound.
const int _kRecentRequestCap = 100;

/// Default delay applied while [MockMode.slow] is active.
const Duration _kDefaultSlowDelay = Duration(seconds: 5);

/// Default count of HTTP 503 responses emitted while [MockMode.outage] is
/// active before flipping to 200.
const int _kDefaultOutageRequestCount = 5;

/// In-process [MockBackend] backed by a `dart:io` [HttpServer] bound to
/// `127.0.0.1` on an ephemeral port.
///
/// Construct via [HttpMockBackend.start] — the constructor is private to
/// guarantee callers receive a fully-bound, ready-to-serve instance.
///
/// Each request is read in full (including the body), captured in
/// [recentRequests], and then answered according to the active [mode]. Mode
/// transitions take effect on the next inbound request; in-flight handlers
/// run to completion against the mode they observed at dispatch time.
class HttpMockBackend implements MockBackend {
  HttpMockBackend._(
    this._server, {
    required MockMode initialMode,
    required Duration slowResponseDelay,
    required int outageRequestCount,
  })  : _mode = initialMode,
        _slowResponseDelay = slowResponseDelay,
        _outageRequestCount = outageRequestCount {
    _subscription = _server.listen(
      _handle,
      onError: (Object _, StackTrace __) {
        // Swallow listener errors — a single misbehaving connection must not
        // tear the whole mock down. Individual handler failures are logged via
        // [_safeRespond500].
      },
      cancelOnError: false,
    );
  }

  /// Binds an [HttpServer] to `127.0.0.1` on an OS-assigned port and returns a
  /// ready-to-serve mock.
  ///
  /// - [initialMode]: mode applied to the first request.
  /// - [slowResponseDelay]: delay used while [MockMode.slow] is active.
  /// - [outageRequestCount]: number of leading 503 responses [MockMode.outage]
  ///   emits before flipping to 200.
  static Future<HttpMockBackend> start({
    MockMode initialMode = MockMode.normal,
    Duration slowResponseDelay = _kDefaultSlowDelay,
    int outageRequestCount = _kDefaultOutageRequestCount,
  }) async {
    if (outageRequestCount < 0) {
      throw ArgumentError.value(
        outageRequestCount,
        'outageRequestCount',
        'must be non-negative',
      );
    }
    if (slowResponseDelay.isNegative) {
      throw ArgumentError.value(
        slowResponseDelay,
        'slowResponseDelay',
        'must be non-negative',
      );
    }
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    return HttpMockBackend._(
      server,
      initialMode: initialMode,
      slowResponseDelay: slowResponseDelay,
      outageRequestCount: outageRequestCount,
    );
  }

  final HttpServer _server;
  final Duration _slowResponseDelay;
  final int _outageRequestCount;

  late final StreamSubscription<HttpRequest> _subscription;

  MockMode _mode;
  int _requestCount = 0;
  bool _http415Fired = false;
  int _flakyCounter = 0;
  int _outageCounter = 0;
  bool _disposed = false;

  // Newest-first ring buffer. We use a List rather than a Queue so the
  // interface contract (`List<MockRequest> get recentRequests`) is satisfied
  // without copying on every read of the head.
  final List<MockRequest> _recentRequests = <MockRequest>[];

  @override
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  @override
  MockMode get mode => _mode;

  @override
  int get requestCount => _requestCount;

  @override
  List<MockRequest> get recentRequests =>
      List<MockRequest>.unmodifiable(_recentRequests);

  @override
  Future<void> setMode(MockMode mode) async {
    _mode = mode;
  }

  @override
  Future<void> reset() async {
    _recentRequests.clear();
    _requestCount = 0;
    _http415Fired = false;
    _flakyCounter = 0;
    _outageCounter = 0;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _server.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // Request handling
  // ---------------------------------------------------------------------------

  Future<void> _handle(HttpRequest request) async {
    final MockMode modeAtDispatch = _mode;
    final Uint8List body = await _readBody(request);
    final Map<String, String> headers = _flattenHeaders(request.headers);

    // Determine the response status before recording so it appears alongside
    // the captured request. Status decisions for stateful modes (`http415Once`,
    // `flaky`, `outage`) advance the relevant counter as a side effect.
    final int status = _statusFor(modeAtDispatch);

    _record(
      MockRequest(
        at: DateTime.now(),
        method: request.method,
        path: request.uri.path,
        headers: headers,
        bodyBytes: body,
        responseStatus: status,
      ),
    );

    try {
      await _respond(request, modeAtDispatch, status);
    } catch (e, st) {
      _safeRespond500(request, e, st);
    }
  }

  /// Reads the request body fully. Returns an empty buffer for empty bodies.
  Future<Uint8List> _readBody(HttpRequest request) async {
    final List<int> acc = await request.fold<List<int>>(
      <int>[],
      (List<int> a, List<int> chunk) => a..addAll(chunk),
    );
    return Uint8List.fromList(acc);
  }

  Map<String, String> _flattenHeaders(HttpHeaders raw) {
    final Map<String, String> out = <String, String>{};
    raw.forEach((String name, List<String> values) {
      // Lowercase keys so scenarios can use canonical lookups
      // (e.g. `headers['content-encoding']`).
      out[name.toLowerCase()] = values.join(', ');
    });
    return out;
  }

  void _record(MockRequest req) {
    _requestCount += 1;
    _recentRequests.insert(0, req);
    if (_recentRequests.length > _kRecentRequestCap) {
      _recentRequests.removeRange(_kRecentRequestCap, _recentRequests.length);
    }
  }

  /// Returns the HTTP status the mock will emit for this request. For modes
  /// that maintain per-instance state (`http415Once`, `flaky`, `outage`) this
  /// also advances the relevant counter so subsequent requests observe the
  /// correct progression.
  ///
  /// [MockMode.drop] is reported as status `0` per the interface contract —
  /// no HTTP response is written.
  int _statusFor(MockMode mode) {
    switch (mode) {
      case MockMode.normal:
        return HttpStatus.ok;
      case MockMode.auth401:
        return HttpStatus.unauthorized;
      case MockMode.auth403:
        return HttpStatus.forbidden;
      case MockMode.http415Once:
        if (!_http415Fired) {
          _http415Fired = true;
          return HttpStatus.unsupportedMediaType;
        }
        return HttpStatus.ok;
      case MockMode.slow:
        return HttpStatus.ok;
      case MockMode.drop:
        return 0;
      case MockMode.flaky:
        _flakyCounter += 1;
        // Odd-numbered requests fail (1st, 3rd, 5th, …), even-numbered succeed.
        return _flakyCounter.isOdd
            ? HttpStatus.internalServerError
            : HttpStatus.ok;
      case MockMode.outage:
        _outageCounter += 1;
        return _outageCounter <= _outageRequestCount
            ? HttpStatus.serviceUnavailable
            : HttpStatus.ok;
    }
  }

  Future<void> _respond(
    HttpRequest request,
    MockMode mode,
    int status,
  ) async {
    switch (mode) {
      case MockMode.normal:
        await _writeJson(request, HttpStatus.ok, const <String, Object?>{});
        return;
      case MockMode.auth401:
        request.response.headers.set('www-authenticate', 'Bearer');
        await _writeJson(
          request,
          HttpStatus.unauthorized,
          const <String, Object?>{'error': 'unauthorized'},
        );
        return;
      case MockMode.auth403:
        await _writeJson(
          request,
          HttpStatus.forbidden,
          const <String, Object?>{'error': 'forbidden'},
        );
        return;
      case MockMode.http415Once:
        if (status == HttpStatus.unsupportedMediaType) {
          await _writeJson(
            request,
            HttpStatus.unsupportedMediaType,
            const <String, Object?>{'error': 'unsupported_media_type'},
          );
        } else {
          await _writeJson(request, HttpStatus.ok, const <String, Object?>{});
        }
        return;
      case MockMode.slow:
        await Future<void>.delayed(_slowResponseDelay);
        await _writeJson(request, HttpStatus.ok, const <String, Object?>{});
        return;
      case MockMode.drop:
        await _drop(request);
        return;
      case MockMode.flaky:
        if (status == HttpStatus.internalServerError) {
          await _writeJson(
            request,
            HttpStatus.internalServerError,
            const <String, Object?>{'error': 'internal_server_error'},
          );
        } else {
          await _writeJson(request, HttpStatus.ok, const <String, Object?>{});
        }
        return;
      case MockMode.outage:
        if (status == HttpStatus.serviceUnavailable) {
          await _writeJson(
            request,
            HttpStatus.serviceUnavailable,
            const <String, Object?>{'error': 'service_unavailable'},
          );
        } else {
          await _writeJson(request, HttpStatus.ok, const <String, Object?>{});
        }
        return;
    }
  }

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    final HttpResponse response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    final List<int> encoded = utf8.encode(jsonEncode(body));
    response.contentLength = encoded.length;
    response.add(encoded);
    await response.close();
  }

  /// Closes the underlying TCP socket without writing any HTTP response. This
  /// reproduces the "connection dropped mid-flight" path the SDK must tolerate.
  Future<void> _drop(HttpRequest request) async {
    try {
      final Socket socket =
          await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } catch (_) {
      // The peer may have already closed the connection or the response may
      // have been partially flushed. Either way, there is nothing meaningful
      // we can recover from at this level — the mode contract is "no HTTP
      // status delivered", which has already been satisfied.
    }
  }

  /// Best-effort 500 response when a handler throws unexpectedly. We never let
  /// a handler crash propagate out of [_handle]; that would surface to the
  /// HttpServer's `onError` and could be misinterpreted as a server bug
  /// instead of a mode bug.
  void _safeRespond500(HttpRequest request, Object error, StackTrace stack) {
    try {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object?>{
          'error': 'mock_handler_threw',
          'message': error.toString(),
        }));
      // Fire-and-forget close: we're already in the error path.
      unawaited(request.response.close());
    } catch (_) {
      // Final fallback: detach and destroy. There is nothing else to try.
      try {
        unawaited(
          request.response
              .detachSocket(writeHeaders: false)
              .then((Socket s) => s.destroy())
              .catchError((Object _) {}),
        );
      } catch (_) {
        // Give up.
      }
    }
    // Surface for diagnostics in debug runs without using a logger dependency.
    assert(() {
      // ignore: avoid_print
      print('HttpMockBackend handler error: $error\n$stack');
      return true;
    }());
  }
}
