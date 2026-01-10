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

  tearDown(() async {
    Locus.setMockInstance(original);
    await mock.dispose();
  });

  test('setMockInstance replaces the default instance', () {
    expect(identical(Locus.instance, mock), isTrue);
  });

  test('delegates core methods to mock instance', () async {
    const config = Config(distanceFilter: 42);

    await Locus.ready(config);
    await Locus.start();
    await Locus.getState();
    await Locus.location.getCurrentPosition();
    await Locus.location.getLocations();
    await Locus.location.changePace(true);
    await Locus.location.setOdometer(123.0);

    const geofence = Geofence(
      identifier: 'test',
      radius: 100,
      latitude: 1,
      longitude: 2,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: false,
    );
    await Locus.geofencing.add(geofence);
    await Locus.geofencing.addAll([geofence]);
    await Locus.geofencing.remove('test');
    await Locus.geofencing.removeAll();
    await Locus.geofencing.getAll();
    await Locus.geofencing.get('test');
    await Locus.geofencing.exists('test');
    await Locus.geofencing.startMonitoring();

    await Locus.setConfig(config);
    await Locus.reset(config);
    await Locus.destroy();

    await Locus.startSchedule();
    await Locus.stopSchedule();

    await Locus.dataSync.resume();  // Must resume before now() since sync is paused by default
    await Locus.dataSync.now();
    await Locus.location.destroyLocations();

    await Locus.registerHeadlessTask((event) async {});
    final taskId = await Locus.startBackgroundTask();
    await Locus.stopBackgroundTask(taskId);

    await Locus.getLog();

    await Locus.dataSync.enqueue({'event': 'test'});
    await Locus.dataSync.getQueue();
    await Locus.dataSync.clearQueue();
    await Locus.dataSync.syncQueue();

    await Locus.requestPermission();

    await Locus.trips.start(const TripConfig());
    await Locus.trips.stop();

    await Locus.setTrackingProfiles(
      {TrackingProfile.standby: const Config()},
      enableAutomation: true,
    );
    await Locus.setTrackingProfile(TrackingProfile.enRoute);
    Locus.startTrackingAutomation();
    Locus.stopTrackingAutomation();
    Locus.clearTrackingProfiles();

    Locus.geofencing.registerWorkflows([
      const GeofenceWorkflow(
        id: 'workflow-1',
        steps: [
          GeofenceWorkflowStep(
            id: 'step-1',
            geofenceIdentifier: 'test',
            action: GeofenceAction.enter,
          ),
        ],
      ),
    ]);
    Locus.geofencing.clearWorkflows();
    Locus.geofencing.stopWorkflows();

    await Locus.battery.getStats();
    await Locus.battery.getPowerState();
    await Locus.battery.setAdaptiveTracking(AdaptiveTrackingConfig.disabled);
    await Locus.battery.calculateAdaptiveSettings();

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

    await Locus.dataSync.setPolicy(SyncPolicy.balanced);
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
      Locus.location.stream.listen((_) {}),
      Locus.location.motionChanges.listen((_) {}),
      Locus.instance.activityStream.listen((_) {}),
      Locus.instance.providerStream.listen((_) {}),
      Locus.geofencing.events.listen((_) {}),
      Locus.geofencing.onGeofencesChange((_) {}),
      Locus.location.heartbeats.listen((_) {}),
      Locus.instance.onSchedule((_) {}),
      Locus.dataSync.connectivityEvents.listen((_) {}),
      Locus.instance.powerSaveStream.listen((_) {}),
      Locus.instance.enabledStream.listen((_) {}),
      Locus.instance.onNotificationAction((_) {}),
      Locus.dataSync.events.listen((_) {}),
      Locus.trips.events.listen((_) {}),
      Locus.geofencing.workflowEvents.listen((_) {}),
      Locus.battery.powerStateEvents.listen((_) {}),
      Locus.onLocationAnomaly((_) {}),
      Locus.onLocationQuality((_) {}),
    ];

    for (final sub in subs) {
      await sub.cancel();
    }
  });
}
