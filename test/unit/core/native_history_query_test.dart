import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import 'package:locus/src/core/method_channel_locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('locus/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) respond;

  setUpAll(() async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(Locus.instance, isA<MethodChannelLocus>());
    // Finish the default provider's asynchronous service registration first.
    await Future<void>.delayed(Duration.zero);
  });
  setUp(() {
    calls.clear();
    respond = (_) async => <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return respond(call);
    });
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'public query forwards every predicate with UTC microsecond edges',
    () async {
      final query = fullQuery();
      await Locus.location.query(query);
      expect(calls.map((call) => call.method), ['queryLocations']);
      final arguments = queryArguments(calls.single);
      expectQueryArguments(arguments, query);
      expect(arguments['from'], -1999);
      expect(arguments['timestampFallback'], isA<int>());
    },
  );

  test(
    'native page is returned without filtering sorting or paging twice',
    () async {
      respond = (_) async => [
        payload('selected-second', 2),
        payload('selected-first', 1),
      ];
      final locations = await Locus.location.query(
        const LocationQuery(
          limit: 2,
          offset: 100,
          sortOrder: LocationSortOrder.oldestFirst,
        ),
      );
      expect(locations.map((location) => location.uuid), [
        'selected-second',
        'selected-first',
      ]);
      expect(calls, hasLength(1));
    },
  );

  test(
    'omitted limit requests all matching rows and normalizes negative offset',
    () async {
      respond = (_) async => [
        payload('one', 1),
        payload('two', 2),
        payload('three', 3),
      ];
      final locations = await Locus.location.query(
        const LocationQuery(offset: -4),
      );
      expect(locations, hasLength(3));
      final arguments = queryArguments(calls.single);
      expect(arguments.containsKey('limit'), isFalse);
      expect(arguments['offset'], 0);
      expect(arguments['sortOrder'], 'newestFirst');
    },
  );

  test('nonpositive limits return empty without calling native code', () async {
    for (final limit in [0, -1, -100]) {
      expect(await Locus.location.query(LocationQuery(limit: limit)), isEmpty);
    }
    expect(calls, isEmpty);
  });

  test(
    'malformed native lists rows and map keys report INVALID_RESULT',
    () async {
      for (final response in <Object?>[
        null,
        'not a list',
        <String, Object?>{},
        <Object?>[null],
        <Object?>['not a row'],
        <Object?>[
          <Object?, Object?>{1: 'not a string key'},
        ],
      ]) {
        respond = (_) async => response;
        await expectLater(
          Locus.location.query(const LocationQuery()),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'INVALID_RESULT',
            ),
          ),
        );
      }
      expect(calls.map((call) => call.method), everyElement('queryLocations'));
    },
  );

  test(
    'native platform errors retain their code message and details',
    () async {
      respond = (_) async => throw PlatformException(
        code: 'DATABASE_READ_FAILED',
        message: 'History cannot be read',
        details: 'fixture failure',
      );
      await expectLater(
        Locus.location.query(const LocationQuery()),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'DATABASE_READ_FAILED')
              .having(
                (error) => error.message,
                'message',
                'History cannot be read',
              )
              .having((error) => error.details, 'details', 'fixture failure'),
        ),
      );
    },
  );

  test(
    'missing native query reports unsupported without legacy fallback',
    () async {
      respond = (_) async => throw MissingPluginException('old native plugin');
      await expectLater(
        Locus.location.query(const LocationQuery()),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_NATIVE_QUERY',
          ),
        ),
      );
      expect(calls.map((call) => call.method), ['queryLocations']);
    },
  );

  test(
    'summary uses the same native query fields and summarizes its page',
    () async {
      final query = fullQuery();
      respond = (_) async => [payload('first', 1), payload('second', 2)];
      final summary = await Locus.location.getSummary(query: query);
      expect(summary.locationCount, 2);
      expect(calls.map((call) => call.method), ['queryLocations']);
      expectQueryArguments(queryArguments(calls.single), query);
    },
  );
}

LocationQuery fullQuery() => LocationQuery(
  from: DateTime.fromMicrosecondsSinceEpoch(-1999, isUtc: true),
  to: DateTime(2026, 11, 3, 12, 30, 40, 123, 456),
  minAccuracy: 20,
  maxAccuracy: 10,
  isMoving: false,
  bounds: const LocationBounds(
    southwest: Coords(latitude: 10, longitude: 20, accuracy: 0),
    northeast: Coords(latitude: 11, longitude: 21, accuracy: 0),
  ),
  limit: 2,
  offset: 3,
  sortOrder: LocationSortOrder.oldestFirst,
);

void expectQueryArguments(Map<String, Object?> arguments, LocationQuery query) {
  final expected = Map<String, Object?>.from(query.toMap());
  expected['from'] = query.from?.toUtc().microsecondsSinceEpoch;
  expected['to'] = query.to?.toUtc().microsecondsSinceEpoch;
  final actual = Map<String, Object?>.from(arguments)
    ..remove('timestampFallback');
  expect(actual, expected);
}

Map<String, Object?> queryArguments(MethodCall call) {
  final Object? arguments = call.arguments;
  if (arguments is! Map<Object?, Object?>) {
    throw StateError('Expected query map');
  }
  return Map<String, Object?>.from(arguments);
}

JsonMap payload(String uuid, int second) => {
  'uuid': uuid,
  'timestamp': DateTime.utc(2026, 11, 3, 12, 0, second).toIso8601String(),
  'coords': <String, Object?>{
    'latitude': 10.5,
    'longitude': 20.5,
    'accuracy': 15.0,
  },
  'is_moving': true,
};
