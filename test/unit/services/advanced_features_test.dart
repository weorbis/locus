import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  group('SpoofDetectionConfig', () {
    test('presets have expected values', () {
      expect(SpoofDetectionConfig.disabled.enabled, false);
      expect(SpoofDetectionConfig.low.minFactorsForDetection, 3);
      expect(SpoofDetectionConfig.balanced.minFactorsForDetection, 2);
      expect(SpoofDetectionConfig.high.blockMockLocations, true);
      expect(SpoofDetectionConfig.strict.checkDeveloperOptions, true);
    });

    test('serialization round-trip preserves values', () {
      const config = SpoofDetectionConfig(
        enabled: true,
        blockMockLocations: true,
        sensitivity: SpoofSensitivity.high,
        maxPossibleSpeedKph: 500,
        minFactorsForDetection: 1,
      );

      final map = config.toMap();
      final restored = SpoofDetectionConfig.fromMap(map);

      expect(restored.enabled, true);
      expect(restored.blockMockLocations, true);
      expect(restored.sensitivity, SpoofSensitivity.high);
      expect(restored.maxPossibleSpeedKph, 500);
      expect(restored.minFactorsForDetection, 1);
    });
  });

  group('SpoofDetector', () {
    test('detects mock provider', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 1,
      ));

      final location = _createLocation(lat: 37.0, lng: -122.0);
      final event = detector.analyze(location, isMockProvider: true);

      expect(event, isNotNull);
      expect(event!.factors, contains(SpoofFactor.mockProvider));
      expect(event.confidence, greaterThan(0.5));
    });

    test('detects impossible speed', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 1,
        maxPossibleSpeedKph: 200,
      ));

      // First location
      final loc1 = _createLocation(
        lat: 37.0,
        lng: -122.0,
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      );
      detector.analyze(loc1);

      // Second location - impossible jump (1 degree = ~111km in 1 second)
      final loc2 = _createLocation(
        lat: 38.0,
        lng: -122.0,
        timestamp: DateTime(2024, 1, 1, 12, 0, 1),
      );
      final event = detector.analyze(loc2);

      expect(event, isNotNull);
      expect(event!.factors, contains(SpoofFactor.impossibleSpeed));
    });

    test('detects repeated coordinates', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 1,
      ));

      final location = _createLocation(lat: 37.0, lng: -122.0);

      // Same location multiple times (need 4 to exceed threshold of 3)
      detector.analyze(location);
      detector.analyze(location);
      detector.analyze(location);
      final event = detector.analyze(location);

      expect(event, isNotNull);
      expect(event!.factors, contains(SpoofFactor.repeatedCoordinates));
    });

    test('returns null when disabled', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: false,
      ));

      final location = _createLocation(lat: 37.0, lng: -122.0);
      final event = detector.analyze(location, isMockProvider: true);

      expect(event, isNull);
    });

    test('respects minFactorsForDetection', () {
      final detector = SpoofDetector(const SpoofDetectionConfig(
        enabled: true,
        minFactorsForDetection: 3,
      ));

      final location = _createLocation(lat: 37.0, lng: -122.0);
      // Only one factor (mock provider)
      final event = detector.analyze(location, isMockProvider: true);

      expect(event, isNull); // Not enough factors
    });
  });

  group('SpoofFactor', () {
    test('has descriptions for all values', () {
      for (final factor in SpoofFactor.values) {
        expect(factor.description, isNotEmpty);
      }
    });
  });

  group('SignificantChangeConfig', () {
    test('presets have expected values', () {
      expect(SignificantChangeConfig.defaults.minDisplacementMeters, 500);
      expect(SignificantChangeConfig.sensitive.minDisplacementMeters, 250);
      expect(SignificantChangeConfig.ultraLowPower.minDisplacementMeters, 1000);
    });

    test('serialization round-trip preserves values', () {
      const config = SignificantChangeConfig(
        minDisplacementMeters: 750,
        deferUntilMoved: false,
        wakeFromBackground: false,
        maxUpdateInterval: Duration(minutes: 15),
      );

      final map = config.toMap();
      final restored = SignificantChangeConfig.fromMap(map);

      expect(restored.minDisplacementMeters, 750);
      expect(restored.deferUntilMoved, false);
      expect(restored.wakeFromBackground, false);
      expect(restored.maxUpdateInterval?.inMinutes, 15);
    });
  });

  group('SignificantChangeManager', () {
    test('starts and stops monitoring', () {
      final manager = SignificantChangeManager();

      expect(manager.isMonitoring, false);

      manager.start(const SignificantChangeConfig());
      expect(manager.isMonitoring, true);

      manager.stop();
      expect(manager.isMonitoring, false);
    });

    test('emits events for significant movement', () async {
      final manager = SignificantChangeManager();
      manager.start(const SignificantChangeConfig(
        minDisplacementMeters: 100,
        deferUntilMoved: true,
      ));

      final events = <SignificantChangeEvent>[];
      manager.events.listen(events.add);

      // First location (no event due to deferUntilMoved)
      final loc1 = _createLocation(lat: 37.0, lng: -122.0);
      manager.processLocation(loc1);

      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, isEmpty); // No event yet

      // Second location - significant movement (~110km north)
      final loc2 = _createLocation(lat: 38.0, lng: -122.0);
      manager.processLocation(loc2);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(events.length, 1);
      expect(events.first.location, loc2);

      manager.dispose();
    });

    test('ignores small movements', () async {
      final manager = SignificantChangeManager();
      manager.start(const SignificantChangeConfig(
        minDisplacementMeters: 500000, // 500km threshold (very large)
        deferUntilMoved: true,
      ));

      final events = <SignificantChangeEvent>[];
      manager.events.listen(events.add);

      final loc1 = _createLocation(lat: 37.0, lng: -122.0);
      manager.processLocation(loc1);

      // Small movement (~111m north)
      final loc2 = _createLocation(lat: 37.001, lng: -122.0);
      manager.processLocation(loc2);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, isEmpty); // No event for small movement below threshold

      manager.dispose();
    });
  });

  group('ErrorRecoveryConfig', () {
    test('presets have expected values', () {
      expect(ErrorRecoveryConfig.defaults.maxRetries, 3);
      expect(ErrorRecoveryConfig.aggressive.maxRetries, 5);
      expect(ErrorRecoveryConfig.conservative.autoRestart, false);
    });

    test('serialization preserves values', () {
      const config = ErrorRecoveryConfig(
        maxRetries: 5,
        retryDelay: Duration(seconds: 10),
        retryBackoff: 1.5,
        logErrors: false,
      );

      final map = config.toMap();

      expect(map['maxRetries'], 5);
      expect(map['retryDelayMs'], 10000);
      expect(map['retryBackoff'], 1.5);
      expect(map['logErrors'], false);
    });
  });

  group('LocusError', () {
    test('factory constructors create correct types', () {
      final permissionError = LocusError.permissionDenied();
      expect(permissionError.type, LocusErrorType.permissionDenied);
      expect(
          permissionError.suggestedRecovery, RecoveryAction.requestUserAction);

      final timeoutError = LocusError.timeout(timeout: Duration(seconds: 30));
      expect(timeoutError.type, LocusErrorType.locationTimeout);
      expect(timeoutError.suggestedRecovery, RecoveryAction.retry);
      expect(timeoutError.details?['timeoutMs'], 30000);

      final networkError = LocusError.networkError();
      expect(networkError.type, LocusErrorType.networkError);
      expect(networkError.isRecoverable, true);
    });

    test('fromException wraps unknown errors', () {
      final error = LocusError.fromException(Exception('test'));
      expect(error.type, LocusErrorType.unknown);
      expect(error.message, contains('test'));
    });

    test('fromException passes through LocusError', () {
      final original = LocusError.timeout();
      final wrapped = LocusError.fromException(original);
      expect(identical(original, wrapped), true);
    });
  });

  group('ErrorRecoveryManager', () {
    test('handles ignored error types', () async {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        ignoreTypes: {LocusErrorType.locationTimeout},
        logErrors: false,
      ));

      final error = LocusError.timeout();
      final action = await manager.handleError(error);

      expect(action, RecoveryAction.ignore);
    });

    test('tracks retry counts', () async {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        maxRetries: 3,
        logErrors: false,
      ));

      final error = LocusError.networkError();

      // 0th, 1st, 2nd retry
      await manager.handleError(error);
      await manager.handleError(error);
      await manager.handleError(error);

      // 4th attempt (retryCount=3) exhausts retries (>= maxRetries)
      final action = await manager.handleError(error);
      expect(action, RecoveryAction.fallbackLowPower);

      manager.dispose();
    });

    test('calculates retry delay with backoff', () {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        retryDelay: Duration(seconds: 1),
        retryBackoff: 2.0,
        logErrors: false,
      ));

      // Simulate retries to increment counter
      manager.handleError(LocusError.networkError());

      final delay1 = manager.getRetryDelay(LocusErrorType.networkError);
      expect(delay1.inSeconds, 2); // 1 * 2

      manager.handleError(LocusError.networkError());
      final delay2 = manager.getRetryDelay(LocusErrorType.networkError);
      expect(delay2.inSeconds, 4); // 1 * 2 * 2

      manager.dispose();
    });

    test('emits errors to stream', () async {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        logErrors: false,
      ));

      final errors = <LocusError>[];
      manager.errors.listen(errors.add);

      final error = LocusError.timeout();
      await manager.handleError(error);

      expect(errors.length, 1);
      expect(errors.first.type, LocusErrorType.locationTimeout);

      manager.dispose();
    });

    test('markResolved clears retry count', () async {
      final manager = ErrorRecoveryManager(const ErrorRecoveryConfig(
        logErrors: false,
      ));

      await manager.handleError(LocusError.networkError());
      await manager.handleError(LocusError.networkError());

      manager.markResolved(LocusErrorType.networkError);

      // Next error should start fresh
      final delay = manager.getRetryDelay(LocusErrorType.networkError);
      expect(delay, const Duration(seconds: 5)); // Default delay

      manager.dispose();
    });
  });
}

Location _createLocation({
  required double lat,
  required double lng,
  double accuracy = 10,
  DateTime? timestamp,
}) {
  return Location(
    coords: Coords(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      speed: 0,
      heading: 0,
      altitude: 0,
    ),
    timestamp: timestamp ?? DateTime.now(),
    isMoving: false,
    uuid: 'test-${DateTime.now().millisecondsSinceEpoch}',
    odometer: 0,
  );
}
