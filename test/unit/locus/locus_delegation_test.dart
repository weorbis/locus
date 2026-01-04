import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocusInterface original;
  late MockLocus mock;

  setUp(() {
    original = Locus.instance;
    mock = MockLocus();
    Locus.setMockInstance(mock);
  });

  tearDown(() {
    Locus.setMockInstance(original);
    mock.dispose();
  });

  test('setMockInstance replaces the default instance', () {
    expect(identical(Locus.instance, mock), isTrue);
  });

  test('delegates core methods to mock instance', () async {
    const config = Config(distanceFilter: 42);

    await Locus.ready(config);
    await Locus.start();
    await Locus.getState();
    await Locus.getCurrentPosition();
    await Locus.getLocations();
    await Locus.changePace(true);
    await Locus.setOdometer(123.0);

    const geofence = Geofence(
      identifier: 'test',
      radius: 100,
      latitude: 1,
      longitude: 2,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: false,
    );
    await Locus.addGeofence(geofence);
    await Locus.addGeofences([geofence]);
    await Locus.removeGeofence('test');
    await Locus.removeGeofences();
    await Locus.getGeofences();
    await Locus.getGeofence('test');
    await Locus.geofenceExists('test');
    await Locus.startGeofences();

    await Locus.setConfig(config);
    await Locus.reset(config);
    await Locus.destroy();

    await Locus.startSchedule();
    await Locus.stopSchedule();

    await Locus.sync();
    await Locus.resumeSync();
    await Locus.destroyLocations();

    await Locus.registerHeadlessTask((event) async {});
    final taskId = await Locus.startBackgroundTask();
    await Locus.stopBackgroundTask(taskId);

    await Locus.getLog();
    await Locus.emailLog('test@example.com');
    await Locus.playSound('ding');

    await Locus.enqueue({'event': 'test'});
    await Locus.getQueue();
    await Locus.clearQueue();
    await Locus.syncQueue();

    await Locus.requestPermission();

    await Locus.startTrip(const TripConfig());
    Locus.stopTrip();

    await Locus.setTrackingProfiles(
      {TrackingProfile.standby: const Config()},
      enableAutomation: true,
    );
    await Locus.setTrackingProfile(TrackingProfile.enRoute);
    Locus.startTrackingAutomation();
    Locus.stopTrackingAutomation();
    Locus.clearTrackingProfiles();

    Locus.registerGeofenceWorkflows([
      GeofenceWorkflow(
        id: 'workflow-1',
        steps: [
          const GeofenceWorkflowStep(
            id: 'step-1',
            geofenceIdentifier: 'test',
            action: GeofenceAction.enter,
          ),
        ],
      ),
    ]);
    Locus.clearGeofenceWorkflows();
    Locus.stopGeofenceWorkflows();

    await Locus.getBatteryStats();
    await Locus.getPowerState();
    await Locus.setAdaptiveTracking(AdaptiveTrackingConfig.disabled);
    await Locus.calculateAdaptiveSettings();

    await Locus.setSpoofDetection(const SpoofDetectionConfig());
    await Locus.startSignificantChangeMonitoring();
    await Locus.stopSignificantChangeMonitoring();
    Locus.setErrorHandler(const ErrorRecoveryConfig());
    await Locus.handleError(LocusError.networkError(message: 'test'));
    await Locus.isTracking();
    Locus.startLifecycleObserving();
    Locus.stopLifecycleObserving();
    await Locus.isInActiveGeofence();

    await Locus.getDiagnostics();
    await Locus.applyRemoteCommand(
      const RemoteCommand(id: 'cmd-1', type: RemoteCommandType.syncQueue),
    );

    await Locus.startBatteryBenchmark();
    await Locus.stopBatteryBenchmark();
    Locus.recordBenchmarkLocationUpdate();
    Locus.recordBenchmarkSync();

    await Locus.setSyncPolicy(SyncPolicy.balanced);
    await Locus.evaluateSyncPolicy(policy: SyncPolicy.balanced);

    expect(
      mock.methodCalls,
      containsAll([
        'ready',
        'start',
        'getState',
        'getCurrentPosition',
        'getLocations',
        'changePace:true',
        'setOdometer:123.0',
        'addGeofence:test',
        'addGeofences',
        'removeGeofence:test',
        'removeGeofences',
        'getGeofences',
        'getGeofence:test',
        'geofenceExists:test',
        'startGeofences',
        'setConfig',
        'reset',
        'destroy',
        'startSchedule',
        'stopSchedule',
        'sync',
        'resumeSync',
        'destroyLocations',
        'registerHeadlessTask',
        'startBackgroundTask',
        'getLog',
        'emailLog:test@example.com',
        'playSound:ding',
        'enqueue',
        'getQueue',
        'clearQueue',
        'syncQueue',
        'requestPermission',
        'startTrip',
        'stopTrip',
        'setTrackingProfiles',
        'setTrackingProfile:TrackingProfile.enRoute',
        'startTrackingAutomation',
        'stopTrackingAutomation',
        'clearTrackingProfiles',
        'registerGeofenceWorkflows',
        'clearGeofenceWorkflows',
        'stopGeofenceWorkflows',
        'getBatteryStats',
        'getPowerState',
        'setAdaptiveTracking',
        'setSpoofDetection',
        'startSignificantChangeMonitoring',
        'stopSignificantChangeMonitoring',
        'setErrorHandler',
        'startLifecycleObserving',
        'stopLifecycleObserving',
        'applyRemoteCommand:RemoteCommandType.syncQueue',
      ]),
    );
    expect(mock.methodCalls, contains('stopBackgroundTask:$taskId'));
    expect(mock.adaptiveTrackingConfig, AdaptiveTrackingConfig.disabled);
    expect(mock.errorRecoveryConfig, isNotNull);
    expect(mock.syncPolicy, SyncPolicy.balanced);
  });

  test('streams and callbacks route through mock', () async {
    final events = <GeolocationEvent<dynamic>>[];
    final eventSub = Locus.events.listen(events.add);

    var headersRefreshed = false;
    Locus.setHeadersCallback(() async {
      headersRefreshed = true;
      return {'Authorization': 'test'};
    });
    await Locus.refreshHeaders();
    Locus.clearHeadersCallback();

    final location = MockLocationExtension.mock(
      latitude: 37.4219,
      longitude: -122.084,
    );
    mock.emitLocation(location);
    await Future.delayed(Duration.zero);

    expect(events.isNotEmpty, isTrue);
    expect(headersRefreshed, isTrue);

    await eventSub.cancel();

    final subs = <StreamSubscription<dynamic>>[
      Locus.onLocation((_) {}),
      Locus.onMotionChange((_) {}),
      Locus.onActivityChange((_) {}),
      Locus.onProviderChange((_) {}),
      Locus.onGeofence((_) {}),
      Locus.onGeofencesChange((_) {}),
      Locus.onHeartbeat((_) {}),
      Locus.onSchedule((_) {}),
      Locus.onConnectivityChange((_) {}),
      Locus.onPowerSaveChange((_) {}),
      Locus.onEnabledChange((_) {}),
      Locus.onNotificationAction((_) {}),
      Locus.onHttp((_) {}),
      Locus.onTripEvent((_) {}),
      Locus.onWorkflowEvent((_) {}),
      Locus.onPowerStateChangeWithObj((_) {}),
      Locus.onLocationAnomaly((_) {}),
      Locus.onLocationQuality((_) {}),
    ];

    for (final sub in subs) {
      await sub.cancel();
    }
  });
}
