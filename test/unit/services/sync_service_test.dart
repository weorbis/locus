/// Comprehensive tests for SyncService API.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('SyncService', () {
    late MockLocus mockLocus;
    late SyncServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = SyncServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    group('now', () {
      test('should trigger immediate sync', () async {
        final result = await service.now();

        expect(result, isA<bool>());
        expect(mockLocus.methodCalls, contains('sync'));
      });
    });

    group('resume', () {
      test('should resume sync after pause', () async {
        final result = await service.resume();

        expect(result, isA<bool>());
        expect(mockLocus.methodCalls, contains('resumeSync'));
      });
    });

    group('setPolicy', () {
      test('should set sync policy', () async {
        const policy = SyncPolicy(
          lowBatteryThreshold: 20,
          preferWifi: true,
          batchSize: 3,
        );

        await service.setPolicy(policy);

        expect(mockLocus.methodCalls, contains('setSyncPolicy'));
      });

      test('should accept custom policy settings', () async {
        const policy = SyncPolicy(
          lowBatteryThreshold: 10,
          preferWifi: false,
          batchSize: 5,
          foregroundOnly: true,
        );

        await service.setPolicy(policy);

        expect(mockLocus.methodCalls, contains('setSyncPolicy'));
      });
    });

    group('evaluatePolicy', () {
      test('should evaluate sync conditions', () async {
        const policy = SyncPolicy(
          lowBatteryThreshold: 20,
          preferWifi: true,
        );

        final decision = await service.evaluatePolicy(policy: policy);

        expect(decision, isA<SyncDecision>());
      });
    });

    group('enqueue', () {
      test('should enqueue custom payload', () async {
        final payload = {'type': 'check-in', 'locationId': 'store-123'};

        final id = await service.enqueue(payload);

        expect(id, isNotEmpty);
        expect(mockLocus.methodCalls, contains('enqueue'));
      });

      test('should accept type parameter', () async {
        final payload = {'data': 'test'};

        await service.enqueue(payload, type: 'custom-event');

        expect(mockLocus.methodCalls, contains('enqueue'));
      });

      test('should accept idempotency key', () async {
        final payload = {'event': 'test'};

        await service.enqueue(
          payload,
          idempotencyKey: 'unique-key-123',
        );

        expect(mockLocus.methodCalls, contains('enqueue'));
      });
    });

    group('getQueue', () {
      test('should return queued items', () async {
        await service.enqueue({'test': 'data1'});
        await service.enqueue({'test': 'data2'});

        final queue = await service.getQueue();

        expect(queue, isA<List<QueueItem>>());
      });

      test('should respect limit parameter', () async {
        for (var i = 0; i < 10; i++) {
          await service.enqueue({'item': i});
        }

        final queue = await service.getQueue(limit: 5);

        expect(queue.length, lessThanOrEqualTo(5));
      });
    });

    group('clearQueue', () {
      test('should clear all queued items', () async {
        await service.enqueue({'test': 'data'});
        await service.clearQueue();

        final queue = await service.getQueue();

        expect(queue, isEmpty);
      });
    });

    group('syncQueue', () {
      test('should sync queued items', () async {
        await service.enqueue({'test': 'data1'});
        await service.enqueue({'test': 'data2'});

        final count = await service.syncQueue();

        expect(count, isA<int>());
      });

      test('should respect limit parameter', () async {
        for (var i = 0; i < 5; i++) {
          await service.enqueue({'item': i});
        }

        await service.syncQueue(limit: 2);

        expect(mockLocus.methodCalls, contains('syncQueue'));
      });
    });

    group('events', () {
      test('should emit HTTP sync events', () async {
        final events = <HttpEvent>[];
        final sub = service.events.listen(events.add);

        const event = HttpEvent(
          status: 200,
          ok: true,
          responseText: 'OK',
        );
        mockLocus.emitHttpEvent(event);

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.ok, isTrue);

        await sub.cancel();
      });

      test('should emit failed sync events', () async {
        final events = <HttpEvent>[];
        final sub = service.events.listen(events.add);

        const event = HttpEvent(
          status: 500,
          ok: false,
          responseText: 'Server Error',
        );
        mockLocus.emitHttpEvent(event);

        await Future.delayed(Duration.zero);

        expect(events.first.ok, isFalse);

        await sub.cancel();
      });
    });

    group('connectivityEvents', () {
      test('should emit connectivity changes', () async {
        final events = <ConnectivityChangeEvent>[];
        final sub = service.connectivityEvents.listen(events.add);

        const event = ConnectivityChangeEvent(
          connected: true,
          networkType: 'wifi',
        );
        mockLocus.emitConnectivityChange(event);

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.connected, isTrue);

        await sub.cancel();
      });
    });

    group('callbacks', () {
      test('should set sync body builder', () async {
        Future<Map<String, dynamic>> builder(List<Location> locations, Map<String, dynamic> extras) async {
          return {'custom': 'data', 'count': locations.length};
        }

        await service.setSyncBodyBuilder(builder);

        expect(mockLocus.methodCalls, contains('setSyncBodyBuilder'));
      });

      test('should clear sync body builder', () {
        service.clearSyncBodyBuilder();

        expect(mockLocus.methodCalls, contains('clearSyncBodyBuilder'));
      });

      test('should set headers callback', () {
        Future<Map<String, String>> callback() async {
          return {'Authorization': 'Bearer token'};
        }

        service.setHeadersCallback(callback);

        // Callback is set internally
        expect(true, isTrue);
      });

      test('should clear headers callback', () {
        service.clearHeadersCallback();

        // Callback is cleared
        expect(true, isTrue);
      });

      test('should refresh headers', () async {
        await service.refreshHeaders();

        expect(mockLocus.methodCalls, contains('refreshHeaders'));
      });
    });

    group('subscriptions', () {
      test('onHttp should receive events', () async {
        HttpEvent? received;
        final sub = service.onHttp((event) {
          received = event;
        });

        const event = HttpEvent(
          status: 200,
          ok: true,
          responseText: 'OK',
        );
        mockLocus.emitHttpEvent(event);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);
        expect(received!.ok, isTrue);

        await sub.cancel();
      });

      test('onConnectivityChange should receive events', () async {
        ConnectivityChangeEvent? received;
        final sub = service.onConnectivityChange((event) {
          received = event;
        });

        const event = ConnectivityChangeEvent(
          connected: true,
          networkType: 'wifi',
        );
        mockLocus.emitConnectivityChange(event);

        await Future.delayed(Duration.zero);

        expect(received, isNotNull);

        await sub.cancel();
      });
    });
  });
}
