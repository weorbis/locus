import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/observability/locus_logger.dart';
import 'package:logging/logging.dart';

void main() {
  group('locusLogger', () {
    test('namespaces every logger under locus.*', () {
      expect(locusLogger('sync').fullName, 'locus.sync');
      expect(locusLogger('headless').fullName, 'locus.headless');
    });

    test('rejects empty area', () {
      expect(() => locusLogger(''), throwsArgumentError);
    });
  });

  group('LocusEvent', () {
    test('renders bare name when no attributes', () {
      expect(const LocusEvent('sync_started').toString(), 'sync_started');
    });

    test('renders snake_case attributes after the name', () {
      const event =
          LocusEvent('points_evicted', {'count': 12, 'reason': 'count_limit'});
      expect(event.toString(), 'points_evicted count=12 reason=count_limit');
    });

    test('formats DateTime values as ISO-8601 UTC', () {
      final ts = DateTime.utc(2026, 4, 27, 10, 30, 0);
      final event = LocusEvent('snapshot', {'occurred_at': ts});
      expect(event.toString(), 'snapshot occurred_at=2026-04-27T10:30:00.000Z');
    });

    test('formats null values explicitly', () {
      const event = LocusEvent('http_error', {'status': null});
      expect(event.toString(), 'http_error status=null');
    });
  });

  group('LocusLoggerEvents extension', () {
    late Logger logger;
    late StreamSubscription<LogRecord> sub;
    late List<LogRecord> records;

    setUp(() {
      Logger.root.level = Level.ALL;
      logger = locusLogger('test_${DateTime.now().microsecondsSinceEpoch}');
      records = <LogRecord>[];
      sub = Logger.root.onRecord.listen(records.add);
    });

    tearDown(() async {
      await sub.cancel();
    });

    test('eventInfo emits LocusEvent on record.object at INFO level', () {
      logger.eventInfo('sync_started', {'attempt': 1});
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.level, Level.INFO);
      expect(record.object, isA<LocusEvent>());
      final event = record.object! as LocusEvent;
      expect(event.name, 'sync_started');
      expect(event.attributes, {'attempt': 1});
    });

    test('eventSevere carries error + stack trace', () {
      final error = StateError('boom');
      final st = StackTrace.current;
      logger.eventSevere('persistence_failure', {'op': 'insert'}, error, st);
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.level, Level.SEVERE);
      expect(record.error, same(error));
      expect(record.stackTrace, same(st));
    });
  });
}
