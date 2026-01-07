import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('SyncService behavior', () {
    late MockLocus mockLocus;
    late SyncServiceImpl service;

    setUp(() {
      mockLocus = MockLocus();
      service = SyncServiceImpl(() => mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    test('setSyncBodyBuilder stores builder for sync payloads', () async {
      await service.setSyncBodyBuilder((locations, extras) async {
        return {
          'count': locations.length,
          'source': extras['source'],
        };
      });

      final result = await mockLocus.invokeSyncBodyBuilder(
        [
          MockLocationExtension.mock(latitude: 1),
          MockLocationExtension.mock(latitude: 2),
        ],
        {'source': 'unit-test'},
      );

      expect(result, {
        'count': 2,
        'source': 'unit-test',
      });
    });

    test('refreshHeaders invokes the headers callback', () async {
      var callbackCalls = 0;
      service.setHeadersCallback(() async {
        callbackCalls++;
        return {'Authorization': 'Bearer token'};
      });

      await service.refreshHeaders();

      expect(callbackCalls, 1);
    });

    test('getQueue returns most recent items when limit is set', () async {
      await service.enqueue({'seq': 1});
      await service.enqueue({'seq': 2});
      await service.enqueue({'seq': 3});

      final queue = await service.getQueue(limit: 2);
      expect(queue.length, 2);
      expect(queue[0].payload['seq'], 2);
      expect(queue[1].payload['seq'], 3);
    });
  });
}
