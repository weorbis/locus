import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/mock_backend/mock_backend_impl.dart';

/// Smoke coverage for [HttpMockBackend]. Each mode is hit with a single
/// `HttpClient` request and the observed status is compared to the contract
/// declared on [MockMode]. The final case re-binds a fresh server to prove
/// the previous one released its port cleanly.
void main() {
  group('HttpMockBackend', () {
    late HttpMockBackend backend;
    late HttpClient client;

    setUp(() async {
      backend = await HttpMockBackend.start(
        // Keep the slow-mode delay short so the whole suite runs in <1s.
        slowResponseDelay: const Duration(milliseconds: 50),
        outageRequestCount: 3,
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await backend.dispose();
      // dispose() must be idempotent.
      await backend.dispose();
    });

    Future<int> hit({String body = '{}'}) async {
      final HttpClientRequest req = await client.postUrl(backend.baseUrl);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(body));
      final HttpClientResponse res = await req.close();
      // Drain so the connection can be reused / closed cleanly.
      await res.drain<void>();
      return res.statusCode;
    }

    test('normal returns 200', () async {
      await backend.setMode(MockMode.normal);
      expect(await hit(), 200);
      expect(backend.requestCount, 1);
      expect(backend.recentRequests.first.responseStatus, 200);
    });

    test('auth401 returns 401 with WWW-Authenticate', () async {
      await backend.setMode(MockMode.auth401);
      final HttpClientRequest req = await client.postUrl(backend.baseUrl);
      req.add(utf8.encode('{}'));
      final HttpClientResponse res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 401);
      expect(res.headers.value('www-authenticate'), 'Bearer');
    });

    test('auth403 returns 403', () async {
      await backend.setMode(MockMode.auth403);
      expect(await hit(), 403);
    });

    test('http415Once returns 415 then 200', () async {
      await backend.setMode(MockMode.http415Once);
      expect(await hit(), 415);
      expect(await hit(), 200);
      expect(await hit(), 200);
    });

    test('http415Once resets after reset()', () async {
      await backend.setMode(MockMode.http415Once);
      expect(await hit(), 415);
      expect(await hit(), 200);
      await backend.reset();
      expect(backend.requestCount, 0);
      expect(await hit(), 415);
      expect(await hit(), 200);
    });

    test('slow returns 200 after configured delay', () async {
      await backend.setMode(MockMode.slow);
      final Stopwatch sw = Stopwatch()..start();
      expect(await hit(), 200);
      sw.stop();
      expect(sw.elapsed.inMilliseconds, greaterThanOrEqualTo(40));
    });

    test('drop closes the socket; status recorded as 0', () async {
      await backend.setMode(MockMode.drop);
      Object? caught;
      try {
        await hit();
      } catch (e) {
        caught = e;
      }
      expect(
        caught,
        isNotNull,
        reason: 'A dropped connection must surface as a client-side error.',
      );
      expect(backend.recentRequests.first.responseStatus, 0);
    });

    test('flaky alternates 500 then 200', () async {
      await backend.setMode(MockMode.flaky);
      expect(await hit(), 500);
      expect(await hit(), 200);
      expect(await hit(), 500);
      expect(await hit(), 200);
    });

    test('flaky counter resets after reset()', () async {
      await backend.setMode(MockMode.flaky);
      expect(await hit(), 500);
      await backend.reset();
      expect(await hit(), 500); // first request after reset is odd → 500
    });

    test('outage returns 503 N times then 200', () async {
      await backend.setMode(MockMode.outage);
      expect(await hit(), 503);
      expect(await hit(), 503);
      expect(await hit(), 503);
      expect(await hit(), 200);
      expect(await hit(), 200);
    });

    test('outage counter resets after reset()', () async {
      await backend.setMode(MockMode.outage);
      expect(await hit(), 503);
      expect(await hit(), 503);
      await backend.reset();
      expect(await hit(), 503);
      expect(await hit(), 503);
      expect(await hit(), 503);
      expect(await hit(), 200);
    });

    test('captures method, path, headers, and body bytes', () async {
      await backend.setMode(MockMode.normal);
      final HttpClientRequest req =
          await client.postUrl(backend.baseUrl.replace(path: '/sync'));
      req.headers.set('x-test', 'hello');
      const String body = '{"a":1}';
      req.add(utf8.encode(body));
      final HttpClientResponse res = await req.close();
      await res.drain<void>();

      final MockRequest captured = backend.recentRequests.first;
      expect(captured.method, 'POST');
      expect(captured.path, '/sync');
      expect(captured.headers['x-test'], 'hello');
      expect(utf8.decode(captured.bodyBytes), body);
    });

    test('recentRequests is capped at 100', () async {
      await backend.setMode(MockMode.normal);
      for (int i = 0; i < 105; i++) {
        await hit();
      }
      expect(backend.requestCount, 105);
      expect(backend.recentRequests.length, 100);
    });
  });

  test('a second HttpMockBackend.start succeeds after dispose (no port leak)',
      () async {
    final HttpMockBackend a = await HttpMockBackend.start();
    final int portA = a.baseUrl.port;
    await a.dispose();

    final HttpMockBackend b = await HttpMockBackend.start();
    expect(b.baseUrl.port, isNonZero);
    await b.dispose();

    // Ports may or may not be reused by the OS — what matters is that the
    // second start() succeeded at all. Asserting equality would be flaky.
    expect(portA, isNonZero);
  });
}
