import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('ConfigValidator', () {
    test('valid config passes validation', () {
      const config = Config(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10,
        stopTimeout: 5,
        url: 'https://api.example.com/locations',
        autoSync: true,
      );

      final result = ConfigValidator.validate(config);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('default config passes validation', () {
      const config = Config();
      final result = ConfigValidator.validate(config);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    group('distanceFilter', () {
      test('negative value is error', () {
        const config = Config(distanceFilter: -10);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'distanceFilter'), isTrue);
      });

      test('very small value is warning', () {
        const config = Config(distanceFilter: 2);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(result.warnings.any((w) => w.field == 'distanceFilter'), isTrue);
      });
    });

    group('stationaryRadius', () {
      test('negative value is error', () {
        const config = Config(stationaryRadius: -25);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'stationaryRadius'), isTrue);
      });
    });

    group('stopTimeout', () {
      test('negative value is error', () {
        const config = Config(stopTimeout: -5);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'stopTimeout'), isTrue);
      });
    });

    group('activityRecognitionInterval', () {
      test('negative value is error', () {
        const config = Config(activityRecognitionInterval: -1000);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.field == 'activityRecognitionInterval'),
          isTrue,
        );
      });

      test('very small value is warning', () {
        const config = Config(activityRecognitionInterval: 500);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(
          result.warnings.any((w) => w.field == 'activityRecognitionInterval'),
          isTrue,
        );
      });
    });

    group('heartbeatInterval', () {
      test('negative value is error', () {
        const config = Config(heartbeatInterval: -60);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(
            result.errors.any((e) => e.field == 'heartbeatInterval'), isTrue);
      });

      test('very small positive value is warning', () {
        const config = Config(heartbeatInterval: 15);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(
            result.warnings.any((w) => w.field == 'heartbeatInterval'), isTrue);
      });
    });

    group('url', () {
      test('missing protocol is error', () {
        const config = Config(url: 'api.example.com/locations');
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'url'), isTrue);
      });

      test('HTTP URL is warning', () {
        const config = Config(url: 'http://api.example.com/locations');
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(result.warnings.any((w) => w.field == 'url'), isTrue);
      });

      test('HTTPS URL is valid', () {
        const config = Config(url: 'https://api.example.com/locations');
        final result = ConfigValidator.validate(config);
        expect(result.errors.any((e) => e.field == 'url'), isFalse);
        expect(result.warnings.any((w) => w.field == 'url'), isFalse);
      });
    });

    group('autoSync', () {
      test('autoSync without URL is error', () {
        const config = Config(autoSync: true);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'autoSync'), isTrue);
      });

      test('autoSync with URL is valid', () {
        const config = Config(
          url: 'https://api.example.com/locations',
          autoSync: true,
        );
        final result = ConfigValidator.validate(config);
        expect(result.errors.any((e) => e.field == 'autoSync'), isFalse);
      });
    });

    group('retry configuration', () {
      test('negative maxRetry is error', () {
        const config = Config(maxRetry: -1);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'maxRetry'), isTrue);
      });

      test('negative retryDelay is error', () {
        const config = Config(retryDelay: -1000);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'retryDelay'), isTrue);
      });
    });

    group('batch configuration', () {
      test('batchSync with invalid maxBatchSize is error', () {
        const config = Config(batchSync: true, maxBatchSize: 0);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'maxBatchSize'), isTrue);
      });

      test('very large maxBatchSize is warning', () {
        const config = Config(batchSync: true, maxBatchSize: 1000);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(result.warnings.any((w) => w.field == 'maxBatchSize'), isTrue);
      });
    });

    group('schedule', () {
      test('invalid schedule format is error', () {
        const config = Config(schedule: ['8am-12pm']);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'schedule'), isTrue);
      });

      test('valid schedule format passes', () {
        const config = Config(schedule: ['08:00-12:00', '13:00-18:00']);
        final result = ConfigValidator.validate(config);
        expect(result.errors.any((e) => e.field == 'schedule'), isFalse);
      });
    });

    group('persist configuration', () {
      test('negative maxDaysToPersist is error', () {
        const config = Config(maxDaysToPersist: -7);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.field == 'maxDaysToPersist'), isTrue);
      });

      test('negative maxRecordsToPersist is error', () {
        const config = Config(maxRecordsToPersist: -100);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isFalse);
        expect(
            result.errors.any((e) => e.field == 'maxRecordsToPersist'), isTrue);
      });
    });

    group('conflicting options', () {
      test('stopOnTerminate with enableHeadless is warning', () {
        const config = Config(stopOnTerminate: true, enableHeadless: true);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(
            result.warnings.any((w) => w.field == 'stopOnTerminate'), isTrue);
      });

      test('startOnBoot without enableHeadless is warning', () {
        const config = Config(startOnBoot: true, enableHeadless: false);
        final result = ConfigValidator.validate(config);
        expect(result.isValid, isTrue);
        expect(result.warnings.any((w) => w.field == 'startOnBoot'), isTrue);
      });
    });

    group('assertValid', () {
      test('throws on invalid config', () {
        const config = Config(distanceFilter: -10);
        expect(
          () => ConfigValidator.assertValid(config),
          throwsA(isA<ConfigValidationException>()),
        );
      });

      test('does not throw on valid config', () {
        const config = Config(distanceFilter: 10);
        expect(() => ConfigValidator.assertValid(config), returnsNormally);
      });
    });

    test('ConfigValidationResult.toString includes errors and warnings', () {
      const config = Config(
        distanceFilter: -10,
        url: 'http://api.example.com/locations', // HTTP warning
      );
      final result = ConfigValidator.validate(config);
      final str = result.toString();
      // toString uses error.message, not error.field
      expect(str.contains('cannot be negative'), isTrue);
    });

    test('ConfigValidationException.toString includes details', () {
      final exception = ConfigValidationException([
        const ConfigValidationError(
          field: 'testField',
          message: 'Test message',
          suggestion: 'Test suggestion',
        ),
      ]);
      final str = exception.toString();
      expect(str.contains('testField'), isTrue);
      expect(str.contains('Test message'), isTrue);
      expect(str.contains('Test suggestion'), isTrue);
    });

    test('validates negative distance filter (result)', () {
      const config = Config(distanceFilter: -10);
      final result = ConfigValidator.validate(config);
      expect(result.isValid, isFalse);
      expect(result.errors.first.field, equals('distanceFilter'));
    });

    test('warns on very small distance filter', () {
      const config = Config(distanceFilter: 2);
      final result = ConfigValidator.validate(config);
      expect(result.isValid, isTrue);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first.field, equals('distanceFilter'));
    });
  });
}
