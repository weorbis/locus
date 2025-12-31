import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  test('config copyWith overrides selected fields', () {
    const config = Config(
      desiredAccuracy: DesiredAccuracy.medium,
      distanceFilter: 50,
      autoSync: false,
      logLevel: LogLevel.warning,
      triggerActivities: [ActivityType.walking],
    );

    final updated = config.copyWith(
      distanceFilter: 15,
      autoSync: true,
      triggerActivities: [ActivityType.running, ActivityType.tilting],
    );

    final map = updated.toMap();
    expect(map['desiredAccuracy'], 'medium');
    expect(map['distanceFilter'], 15);
    expect(map['autoSync'], true);
    expect(map['logLevel'], 'warning');
    expect(map['triggerActivities'], ['running', 'tilting']);
  });

  test('config fromMap deserializes all fields', () {
    final map = {
      'desiredAccuracy': 'high',
      'distanceFilter': 25.0,
      'autoSync': true,
      'logLevel': 'debug',
      'triggerActivities': ['walking', 'running'],
      'url': 'https://example.com/api',
      'headers': {'Authorization': 'Bearer token'},
      'notification': {
        'title': 'Tracking',
        'text': 'Active',
      },
      'backgroundPermissionRationale': {
        'title': 'Permission needed',
        'message': 'Please grant location access.',
      },
    };

    final config = Config.fromMap(map);
    expect(config.desiredAccuracy, DesiredAccuracy.high);
    expect(config.distanceFilter, 25.0);
    expect(config.autoSync, true);
    expect(config.logLevel, LogLevel.debug);
    expect(
        config.triggerActivities, [ActivityType.walking, ActivityType.running]);
    expect(config.url, 'https://example.com/api');
    expect(config.headers, {'Authorization': 'Bearer token'});
    expect(config.notification?.title, 'Tracking');
    expect(config.notification?.text, 'Active');
    expect(config.backgroundPermissionRationale?.title, 'Permission needed');
  });

  test('config toMap and fromMap roundtrip', () {
    const original = Config(
      desiredAccuracy: DesiredAccuracy.navigation,
      distanceFilter: 10.0,
      stopTimeout: 5,
      autoSync: true,
      batchSync: false,
      logLevel: LogLevel.verbose,
      triggerActivities: [ActivityType.inVehicle, ActivityType.onBicycle],
    );

    final map = original.toMap();
    final restored = Config.fromMap(map);

    expect(restored.desiredAccuracy, original.desiredAccuracy);
    expect(restored.distanceFilter, original.distanceFilter);
    expect(restored.stopTimeout, original.stopTimeout);
    expect(restored.autoSync, original.autoSync);
    expect(restored.batchSync, original.batchSync);
    expect(restored.logLevel, original.logLevel);
    expect(restored.triggerActivities, original.triggerActivities);
  });

  test('notification config serializes optional fields', () {
    const notification = NotificationConfig(
      title: 'Tracking',
      text: 'Enabled',
      smallIcon: 'ic_tracker',
      actions: ['PAUSE', 'STOP'],
      strings: {'pause': 'Pause'},
    );

    final map = notification.toMap();
    expect(map['title'], 'Tracking');
    expect(map['text'], 'Enabled');
    expect(map['smallIcon'], 'ic_tracker');
    expect(map['actions'], ['PAUSE', 'STOP']);
    expect(map['strings'], {'pause': 'Pause'});
    expect(map.containsKey('largeIcon'), false);
  });

  test('notification config fromMap deserializes fields', () {
    final map = {
      'title': 'Active',
      'text': 'Recording location',
      'smallIcon': 'ic_location',
      'largeIcon': 'ic_app',
      'actions': ['PAUSE'],
    };

    final notification = NotificationConfig.fromMap(map);
    expect(notification.title, 'Active');
    expect(notification.text, 'Recording location');
    expect(notification.smallIcon, 'ic_location');
    expect(notification.largeIcon, 'ic_app');
    expect(notification.actions, ['PAUSE']);
  });

  test('permission rationale serializes action labels', () {
    const rationale = PermissionRationale(
      title: 'Location required',
      message: 'Enable location to track movement.',
      positiveAction: 'Continue',
      negativeAction: 'Later',
    );

    final map = rationale.toMap();
    expect(map['title'], 'Location required');
    expect(map['message'], 'Enable location to track movement.');
    expect(map['positiveAction'], 'Continue');
    expect(map['negativeAction'], 'Later');
  });

  test('permission rationale fromMap deserializes fields', () {
    final map = {
      'title': 'Background Location',
      'message': 'We need access to track your route.',
      'positiveAction': 'Allow',
      'negativeAction': 'Deny',
    };

    final rationale = PermissionRationale.fromMap(map);
    expect(rationale.title, 'Background Location');
    expect(rationale.message, 'We need access to track your route.');
    expect(rationale.positiveAction, 'Allow');
    expect(rationale.negativeAction, 'Deny');
  });

  test('config presets provide expected defaults', () {
    expect(ConfigPresets.lowPower.desiredAccuracy, DesiredAccuracy.low);
    expect(ConfigPresets.tracking.distanceFilter, 10);
    expect(ConfigPresets.trail.desiredAccuracy, DesiredAccuracy.navigation);
    expect(ConfigPresets.balanced.heartbeatInterval, 120);
  });

  test('config maps queue settings', () {
    const config = Config(
      queueMaxDays: 3,
      queueMaxRecords: 100,
      idempotencyHeader: 'Idempotency-Key',
    );

    final map = config.toMap();
    expect(map['queueMaxDays'], 3);
    expect(map['queueMaxRecords'], 100);
    expect(map['idempotencyHeader'], 'Idempotency-Key');

    final restored = Config.fromMap(map);
    expect(restored.queueMaxDays, 3);
    expect(restored.queueMaxRecords, 100);
    expect(restored.idempotencyHeader, 'Idempotency-Key');
  });

  group('TripConfig defaults', () {
    test('has reasonable defaults', () {
      const config = TripConfig(startDistanceMeters: 100);
      expect(config.updateIntervalSeconds, equals(60));
    });
  });
}
