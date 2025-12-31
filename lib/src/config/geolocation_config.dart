library;

import 'package:locus/src/config/config_enums.dart';
import 'package:locus/src/config/notification_config.dart';
import 'package:locus/src/config/permission_rationale.dart';
import 'package:locus/src/models/models.dart';

/// Main configuration class for the background geolocation service.
class Config {
  /// SDK version.
  static const String version = '2.0.0';

  // Location settings
  final DesiredAccuracy? desiredAccuracy;
  final double? distanceFilter;
  final int? locationUpdateInterval;
  final int? fastestLocationUpdateInterval;
  final int? activityRecognitionInterval;
  final int? stopTimeout;
  final int? stopAfterElapsedMinutes;
  final int? stopDetectionDelay;
  final int? motionTriggerDelay;
  final int? minimumActivityRecognitionConfidence;
  final bool? useSignificantChangesOnly;
  final bool? allowIdenticalLocations;
  final bool? disableMotionActivityUpdates;
  final bool? disableStopDetection;
  final bool? disableProviderChangeRecord;
  final bool? disableLocationAuthorizationAlert;

  // Background/foreground settings
  final bool? enableHeadless;
  final bool? startOnBoot;
  final bool? stopOnTerminate;
  final bool? foregroundService;
  final bool? preventSuspend;
  final bool? pausesLocationUpdatesAutomatically;
  final bool? showsBackgroundLocationIndicator;

  // Motion detection settings
  final double? stationaryRadius;
  final double? desiredOdometerAccuracy;
  final double? elasticityMultiplier;
  final double? speedJumpFilter;
  final bool? stopOnStationary;

  // Geofencing settings
  final bool? geofenceModeHighAccuracy;
  final bool? geofenceInitialTriggerEntry;
  final int? geofenceProximityRadius;
  final int? maxMonitoredGeofences;

  // HTTP sync settings
  final int? locationTimeout;
  final int? httpTimeout;
  final int? maxRetry;
  final int? retryDelay;
  final double? retryDelayMultiplier;
  final int? maxRetryDelay;
  final String? bgTaskId;
  final String? url;
  final String? method;
  final JsonMap? headers;
  final JsonMap? params;
  final JsonMap? extras;
  final bool? autoSync;
  final bool? batchSync;
  final int? maxBatchSize;
  final int? autoSyncThreshold;
  final bool? disableAutoSyncOnCellular;
  final int? queueMaxDays;
  final int? queueMaxRecords;
  final String? idempotencyHeader;

  // Persistence settings
  final PersistMode? persistMode;
  final int? maxDaysToPersist;
  final int? maxRecordsToPersist;
  final String? locationTemplate;
  final String? geofenceTemplate;
  final String? httpRootProperty;

  // Scheduling settings
  final List<String>? schedule;
  final bool? scheduleUseAlarmManager;

  // Force reload settings
  final bool? forceReloadOnBoot;
  final bool? forceReloadOnLocationChange;
  final bool? forceReloadOnMotionChange;
  final bool? forceReloadOnGeofence;
  final bool? forceReloadOnHeartbeat;
  final bool? forceReloadOnSchedule;
  final bool? enableTimestampMeta;

  // Notification and logging
  final NotificationConfig? notification;
  final LogLevel? logLevel;
  final int? logMaxDays;
  final int? heartbeatInterval;
  final PermissionRationale? backgroundPermissionRationale;
  final List<ActivityType>? triggerActivities;

  const Config({
    this.desiredAccuracy,
    this.distanceFilter,
    this.locationUpdateInterval,
    this.fastestLocationUpdateInterval,
    this.activityRecognitionInterval,
    this.stopTimeout,
    this.stopAfterElapsedMinutes,
    this.stopDetectionDelay,
    this.motionTriggerDelay,
    this.minimumActivityRecognitionConfidence,
    this.useSignificantChangesOnly,
    this.allowIdenticalLocations,
    this.disableMotionActivityUpdates,
    this.disableStopDetection,
    this.disableProviderChangeRecord,
    this.disableLocationAuthorizationAlert,
    this.enableHeadless,
    this.startOnBoot,
    this.stopOnTerminate,
    this.foregroundService,
    this.preventSuspend,
    this.pausesLocationUpdatesAutomatically,
    this.showsBackgroundLocationIndicator,
    this.stationaryRadius,
    this.desiredOdometerAccuracy,
    this.elasticityMultiplier,
    this.speedJumpFilter,
    this.stopOnStationary,
    this.geofenceModeHighAccuracy,
    this.geofenceInitialTriggerEntry,
    this.geofenceProximityRadius,
    this.maxMonitoredGeofences,
    this.locationTimeout,
    this.httpTimeout,
    this.maxRetry,
    this.retryDelay,
    this.retryDelayMultiplier,
    this.maxRetryDelay,
    this.bgTaskId,
    this.url,
    this.method,
    this.headers,
    this.params,
    this.extras,
    this.autoSync,
    this.batchSync,
    this.maxBatchSize,
    this.autoSyncThreshold,
    this.disableAutoSyncOnCellular,
    this.queueMaxDays,
    this.queueMaxRecords,
    this.idempotencyHeader,
    this.persistMode,
    this.maxDaysToPersist,
    this.maxRecordsToPersist,
    this.locationTemplate,
    this.geofenceTemplate,
    this.httpRootProperty,
    this.schedule,
    this.scheduleUseAlarmManager,
    this.forceReloadOnBoot,
    this.forceReloadOnLocationChange,
    this.forceReloadOnMotionChange,
    this.forceReloadOnGeofence,
    this.forceReloadOnHeartbeat,
    this.forceReloadOnSchedule,
    this.enableTimestampMeta,
    this.notification,
    this.logLevel,
    this.logMaxDays,
    this.heartbeatInterval,
    this.backgroundPermissionRationale,
    this.triggerActivities,
  });

  Config copyWith({
    DesiredAccuracy? desiredAccuracy,
    double? distanceFilter,
    int? locationUpdateInterval,
    int? fastestLocationUpdateInterval,
    int? activityRecognitionInterval,
    int? stopTimeout,
    int? stopAfterElapsedMinutes,
    int? stopDetectionDelay,
    int? motionTriggerDelay,
    int? minimumActivityRecognitionConfidence,
    bool? useSignificantChangesOnly,
    bool? allowIdenticalLocations,
    bool? disableMotionActivityUpdates,
    bool? disableStopDetection,
    bool? disableProviderChangeRecord,
    bool? disableLocationAuthorizationAlert,
    bool? enableHeadless,
    bool? startOnBoot,
    bool? stopOnTerminate,
    bool? foregroundService,
    bool? preventSuspend,
    bool? pausesLocationUpdatesAutomatically,
    bool? showsBackgroundLocationIndicator,
    double? stationaryRadius,
    double? desiredOdometerAccuracy,
    double? elasticityMultiplier,
    double? speedJumpFilter,
    bool? stopOnStationary,
    bool? geofenceModeHighAccuracy,
    bool? geofenceInitialTriggerEntry,
    int? geofenceProximityRadius,
    int? maxMonitoredGeofences,
    int? locationTimeout,
    int? httpTimeout,
    int? maxRetry,
    int? retryDelay,
    double? retryDelayMultiplier,
    int? maxRetryDelay,
    String? bgTaskId,
    String? url,
    String? method,
    JsonMap? headers,
    JsonMap? params,
    JsonMap? extras,
    bool? autoSync,
    bool? batchSync,
    int? maxBatchSize,
    int? autoSyncThreshold,
    bool? disableAutoSyncOnCellular,
    int? queueMaxDays,
    int? queueMaxRecords,
    String? idempotencyHeader,
    PersistMode? persistMode,
    int? maxDaysToPersist,
    int? maxRecordsToPersist,
    String? locationTemplate,
    String? geofenceTemplate,
    String? httpRootProperty,
    List<String>? schedule,
    bool? scheduleUseAlarmManager,
    bool? forceReloadOnBoot,
    bool? forceReloadOnLocationChange,
    bool? forceReloadOnMotionChange,
    bool? forceReloadOnGeofence,
    bool? forceReloadOnHeartbeat,
    bool? forceReloadOnSchedule,
    bool? enableTimestampMeta,
    NotificationConfig? notification,
    LogLevel? logLevel,
    int? logMaxDays,
    int? heartbeatInterval,
    PermissionRationale? backgroundPermissionRationale,
    List<ActivityType>? triggerActivities,
  }) {
    return Config(
      desiredAccuracy: desiredAccuracy ?? this.desiredAccuracy,
      distanceFilter: distanceFilter ?? this.distanceFilter,
      locationUpdateInterval:
          locationUpdateInterval ?? this.locationUpdateInterval,
      fastestLocationUpdateInterval:
          fastestLocationUpdateInterval ?? this.fastestLocationUpdateInterval,
      activityRecognitionInterval:
          activityRecognitionInterval ?? this.activityRecognitionInterval,
      stopTimeout: stopTimeout ?? this.stopTimeout,
      stopAfterElapsedMinutes:
          stopAfterElapsedMinutes ?? this.stopAfterElapsedMinutes,
      stopDetectionDelay: stopDetectionDelay ?? this.stopDetectionDelay,
      motionTriggerDelay: motionTriggerDelay ?? this.motionTriggerDelay,
      minimumActivityRecognitionConfidence:
          minimumActivityRecognitionConfidence ??
              this.minimumActivityRecognitionConfidence,
      useSignificantChangesOnly:
          useSignificantChangesOnly ?? this.useSignificantChangesOnly,
      allowIdenticalLocations:
          allowIdenticalLocations ?? this.allowIdenticalLocations,
      disableMotionActivityUpdates:
          disableMotionActivityUpdates ?? this.disableMotionActivityUpdates,
      disableStopDetection: disableStopDetection ?? this.disableStopDetection,
      disableProviderChangeRecord:
          disableProviderChangeRecord ?? this.disableProviderChangeRecord,
      disableLocationAuthorizationAlert: disableLocationAuthorizationAlert ??
          this.disableLocationAuthorizationAlert,
      enableHeadless: enableHeadless ?? this.enableHeadless,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      stopOnTerminate: stopOnTerminate ?? this.stopOnTerminate,
      foregroundService: foregroundService ?? this.foregroundService,
      preventSuspend: preventSuspend ?? this.preventSuspend,
      pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically ??
          this.pausesLocationUpdatesAutomatically,
      showsBackgroundLocationIndicator: showsBackgroundLocationIndicator ??
          this.showsBackgroundLocationIndicator,
      stationaryRadius: stationaryRadius ?? this.stationaryRadius,
      desiredOdometerAccuracy:
          desiredOdometerAccuracy ?? this.desiredOdometerAccuracy,
      elasticityMultiplier: elasticityMultiplier ?? this.elasticityMultiplier,
      speedJumpFilter: speedJumpFilter ?? this.speedJumpFilter,
      stopOnStationary: stopOnStationary ?? this.stopOnStationary,
      geofenceModeHighAccuracy:
          geofenceModeHighAccuracy ?? this.geofenceModeHighAccuracy,
      geofenceInitialTriggerEntry:
          geofenceInitialTriggerEntry ?? this.geofenceInitialTriggerEntry,
      geofenceProximityRadius:
          geofenceProximityRadius ?? this.geofenceProximityRadius,
      maxMonitoredGeofences:
          maxMonitoredGeofences ?? this.maxMonitoredGeofences,
      locationTimeout: locationTimeout ?? this.locationTimeout,
      httpTimeout: httpTimeout ?? this.httpTimeout,
      maxRetry: maxRetry ?? this.maxRetry,
      retryDelay: retryDelay ?? this.retryDelay,
      retryDelayMultiplier: retryDelayMultiplier ?? this.retryDelayMultiplier,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      bgTaskId: bgTaskId ?? this.bgTaskId,
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      params: params ?? this.params,
      extras: extras ?? this.extras,
      autoSync: autoSync ?? this.autoSync,
      batchSync: batchSync ?? this.batchSync,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      autoSyncThreshold: autoSyncThreshold ?? this.autoSyncThreshold,
      disableAutoSyncOnCellular:
          disableAutoSyncOnCellular ?? this.disableAutoSyncOnCellular,
      queueMaxDays: queueMaxDays ?? this.queueMaxDays,
      queueMaxRecords: queueMaxRecords ?? this.queueMaxRecords,
      idempotencyHeader: idempotencyHeader ?? this.idempotencyHeader,
      persistMode: persistMode ?? this.persistMode,
      maxDaysToPersist: maxDaysToPersist ?? this.maxDaysToPersist,
      maxRecordsToPersist: maxRecordsToPersist ?? this.maxRecordsToPersist,
      locationTemplate: locationTemplate ?? this.locationTemplate,
      geofenceTemplate: geofenceTemplate ?? this.geofenceTemplate,
      httpRootProperty: httpRootProperty ?? this.httpRootProperty,
      schedule: schedule ?? this.schedule,
      scheduleUseAlarmManager:
          scheduleUseAlarmManager ?? this.scheduleUseAlarmManager,
      forceReloadOnBoot: forceReloadOnBoot ?? this.forceReloadOnBoot,
      forceReloadOnLocationChange:
          forceReloadOnLocationChange ?? this.forceReloadOnLocationChange,
      forceReloadOnMotionChange:
          forceReloadOnMotionChange ?? this.forceReloadOnMotionChange,
      forceReloadOnGeofence:
          forceReloadOnGeofence ?? this.forceReloadOnGeofence,
      forceReloadOnHeartbeat:
          forceReloadOnHeartbeat ?? this.forceReloadOnHeartbeat,
      forceReloadOnSchedule:
          forceReloadOnSchedule ?? this.forceReloadOnSchedule,
      enableTimestampMeta: enableTimestampMeta ?? this.enableTimestampMeta,
      notification: notification ?? this.notification,
      logLevel: logLevel ?? this.logLevel,
      logMaxDays: logMaxDays ?? this.logMaxDays,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      backgroundPermissionRationale:
          backgroundPermissionRationale ?? this.backgroundPermissionRationale,
      triggerActivities: triggerActivities ?? this.triggerActivities,
    );
  }

  JsonMap toMap() {
    final map = <String, dynamic>{
      'version': version,
    };

    void put(String key, dynamic value) {
      if (value != null) {
        map[key] = value;
      }
    }

    put('desiredAccuracy', desiredAccuracy?.name);
    put('distanceFilter', distanceFilter);
    put('locationUpdateInterval', locationUpdateInterval);
    put('fastestLocationUpdateInterval', fastestLocationUpdateInterval);
    put('activityRecognitionInterval', activityRecognitionInterval);
    put('stopTimeout', stopTimeout);
    put('stopAfterElapsedMinutes', stopAfterElapsedMinutes);
    put('stopDetectionDelay', stopDetectionDelay);
    put('motionTriggerDelay', motionTriggerDelay);
    put('minimumActivityRecognitionConfidence',
        minimumActivityRecognitionConfidence);
    put('useSignificantChangesOnly', useSignificantChangesOnly);
    put('allowIdenticalLocations', allowIdenticalLocations);
    put('disableMotionActivityUpdates', disableMotionActivityUpdates);
    put('disableStopDetection', disableStopDetection);
    put('disableProviderChangeRecord', disableProviderChangeRecord);
    put('disableLocationAuthorizationAlert', disableLocationAuthorizationAlert);
    put('enableHeadless', enableHeadless);
    put('startOnBoot', startOnBoot);
    put('stopOnTerminate', stopOnTerminate);
    put('foregroundService', foregroundService);
    put('preventSuspend', preventSuspend);
    put('pausesLocationUpdatesAutomatically',
        pausesLocationUpdatesAutomatically);
    put('showsBackgroundLocationIndicator', showsBackgroundLocationIndicator);
    put('stationaryRadius', stationaryRadius);
    put('desiredOdometerAccuracy', desiredOdometerAccuracy);
    put('elasticityMultiplier', elasticityMultiplier);
    put('speedJumpFilter', speedJumpFilter);
    put('stopOnStationary', stopOnStationary);
    put('geofenceModeHighAccuracy', geofenceModeHighAccuracy);
    put('geofenceInitialTriggerEntry', geofenceInitialTriggerEntry);
    put('geofenceProximityRadius', geofenceProximityRadius);
    put('maxMonitoredGeofences', maxMonitoredGeofences);
    put('locationTimeout', locationTimeout);
    put('httpTimeout', httpTimeout);
    put('maxRetry', maxRetry);
    put('retryDelay', retryDelay);
    put('retryDelayMultiplier', retryDelayMultiplier);
    put('maxRetryDelay', maxRetryDelay);
    put('bgTaskId', bgTaskId);
    put('url', url);
    put('method', method);
    put('headers', headers);
    put('params', params);
    put('extras', extras);
    put('autoSync', autoSync);
    put('batchSync', batchSync);
    put('maxBatchSize', maxBatchSize);
    put('autoSyncThreshold', autoSyncThreshold);
    put('disableAutoSyncOnCellular', disableAutoSyncOnCellular);
    put('queueMaxDays', queueMaxDays);
    put('queueMaxRecords', queueMaxRecords);
    put('idempotencyHeader', idempotencyHeader);
    put('persistMode', persistMode?.name);
    put('maxDaysToPersist', maxDaysToPersist);
    put('maxRecordsToPersist', maxRecordsToPersist);
    put('locationTemplate', locationTemplate);
    put('geofenceTemplate', geofenceTemplate);
    put('httpRootProperty', httpRootProperty);
    put('schedule', schedule);
    put('scheduleUseAlarmManager', scheduleUseAlarmManager);
    put('forceReloadOnBoot', forceReloadOnBoot);
    put('forceReloadOnLocationChange', forceReloadOnLocationChange);
    put('forceReloadOnMotionChange', forceReloadOnMotionChange);
    put('forceReloadOnGeofence', forceReloadOnGeofence);
    put('forceReloadOnHeartbeat', forceReloadOnHeartbeat);
    put('forceReloadOnSchedule', forceReloadOnSchedule);
    put('enableTimestampMeta', enableTimestampMeta);
    put('notification', notification?.toMap());
    put('logLevel', logLevel?.name);
    put('logMaxDays', logMaxDays);
    put('heartbeatInterval', heartbeatInterval);
    put('backgroundPermissionRationale',
        backgroundPermissionRationale?.toMap());
    put('triggerActivities', triggerActivities?.map((e) => e.name).toList());

    return map;
  }

  factory Config.fromMap(JsonMap map) {
    return Config(
      desiredAccuracy: _parseEnum(
        map['desiredAccuracy'] as String?,
        DesiredAccuracy.values,
      ),
      distanceFilter: (map['distanceFilter'] as num?)?.toDouble(),
      locationUpdateInterval: (map['locationUpdateInterval'] as num?)?.toInt(),
      fastestLocationUpdateInterval:
          (map['fastestLocationUpdateInterval'] as num?)?.toInt(),
      activityRecognitionInterval:
          (map['activityRecognitionInterval'] as num?)?.toInt(),
      stopTimeout: (map['stopTimeout'] as num?)?.toInt(),
      stopAfterElapsedMinutes:
          (map['stopAfterElapsedMinutes'] as num?)?.toInt(),
      stopDetectionDelay: (map['stopDetectionDelay'] as num?)?.toInt(),
      motionTriggerDelay: (map['motionTriggerDelay'] as num?)?.toInt(),
      minimumActivityRecognitionConfidence:
          (map['minimumActivityRecognitionConfidence'] as num?)?.toInt(),
      useSignificantChangesOnly: map['useSignificantChangesOnly'] as bool?,
      allowIdenticalLocations: map['allowIdenticalLocations'] as bool?,
      disableMotionActivityUpdates:
          map['disableMotionActivityUpdates'] as bool?,
      disableStopDetection: map['disableStopDetection'] as bool?,
      disableProviderChangeRecord: map['disableProviderChangeRecord'] as bool?,
      disableLocationAuthorizationAlert:
          map['disableLocationAuthorizationAlert'] as bool?,
      enableHeadless: map['enableHeadless'] as bool?,
      startOnBoot: map['startOnBoot'] as bool?,
      stopOnTerminate: map['stopOnTerminate'] as bool?,
      foregroundService: map['foregroundService'] as bool?,
      preventSuspend: map['preventSuspend'] as bool?,
      pausesLocationUpdatesAutomatically:
          map['pausesLocationUpdatesAutomatically'] as bool?,
      showsBackgroundLocationIndicator:
          map['showsBackgroundLocationIndicator'] as bool?,
      stationaryRadius: (map['stationaryRadius'] as num?)?.toDouble(),
      desiredOdometerAccuracy:
          (map['desiredOdometerAccuracy'] as num?)?.toDouble(),
      elasticityMultiplier: (map['elasticityMultiplier'] as num?)?.toDouble(),
      speedJumpFilter: (map['speedJumpFilter'] as num?)?.toDouble(),
      stopOnStationary: map['stopOnStationary'] as bool?,
      geofenceModeHighAccuracy: map['geofenceModeHighAccuracy'] as bool?,
      geofenceInitialTriggerEntry: map['geofenceInitialTriggerEntry'] as bool?,
      geofenceProximityRadius:
          (map['geofenceProximityRadius'] as num?)?.toInt(),
      maxMonitoredGeofences: (map['maxMonitoredGeofences'] as num?)?.toInt(),
      locationTimeout: (map['locationTimeout'] as num?)?.toInt(),
      httpTimeout: (map['httpTimeout'] as num?)?.toInt(),
      maxRetry: (map['maxRetry'] as num?)?.toInt(),
      retryDelay: (map['retryDelay'] as num?)?.toInt(),
      retryDelayMultiplier: (map['retryDelayMultiplier'] as num?)?.toDouble(),
      maxRetryDelay: (map['maxRetryDelay'] as num?)?.toInt(),
      bgTaskId: map['bgTaskId'] as String?,
      url: map['url'] as String?,
      method: map['method'] as String?,
      headers: map['headers'] is Map
          ? Map<String, dynamic>.from(map['headers'] as Map)
          : null,
      params: map['params'] is Map
          ? Map<String, dynamic>.from(map['params'] as Map)
          : null,
      extras: map['extras'] is Map
          ? Map<String, dynamic>.from(map['extras'] as Map)
          : null,
      autoSync: map['autoSync'] as bool?,
      batchSync: map['batchSync'] as bool?,
      maxBatchSize: (map['maxBatchSize'] as num?)?.toInt(),
      autoSyncThreshold: (map['autoSyncThreshold'] as num?)?.toInt(),
      disableAutoSyncOnCellular: map['disableAutoSyncOnCellular'] as bool?,
      queueMaxDays: (map['queueMaxDays'] as num?)?.toInt(),
      queueMaxRecords: (map['queueMaxRecords'] as num?)?.toInt(),
      idempotencyHeader: map['idempotencyHeader'] as String?,
      persistMode: _parseEnum(
        map['persistMode'] as String?,
        PersistMode.values,
      ),
      maxDaysToPersist: (map['maxDaysToPersist'] as num?)?.toInt(),
      maxRecordsToPersist: (map['maxRecordsToPersist'] as num?)?.toInt(),
      locationTemplate: map['locationTemplate'] as String?,
      geofenceTemplate: map['geofenceTemplate'] as String?,
      httpRootProperty: map['httpRootProperty'] as String?,
      schedule: (map['schedule'] as List?)?.cast<String>(),
      scheduleUseAlarmManager: map['scheduleUseAlarmManager'] as bool?,
      forceReloadOnBoot: map['forceReloadOnBoot'] as bool?,
      forceReloadOnLocationChange: map['forceReloadOnLocationChange'] as bool?,
      forceReloadOnMotionChange: map['forceReloadOnMotionChange'] as bool?,
      forceReloadOnGeofence: map['forceReloadOnGeofence'] as bool?,
      forceReloadOnHeartbeat: map['forceReloadOnHeartbeat'] as bool?,
      forceReloadOnSchedule: map['forceReloadOnSchedule'] as bool?,
      enableTimestampMeta: map['enableTimestampMeta'] as bool?,
      notification: map['notification'] is Map
          ? NotificationConfig.fromMap(
              Map<String, dynamic>.from(map['notification'] as Map),
            )
          : null,
      logLevel: _parseEnum(map['logLevel'] as String?, LogLevel.values),
      logMaxDays: (map['logMaxDays'] as num?)?.toInt(),
      heartbeatInterval: (map['heartbeatInterval'] as num?)?.toInt(),
      backgroundPermissionRationale: map['backgroundPermissionRationale'] is Map
          ? PermissionRationale.fromMap(
              Map<String, dynamic>.from(
                  map['backgroundPermissionRationale'] as Map),
            )
          : null,
      triggerActivities: (map['triggerActivities'] as List?)
          ?.map((e) => ActivityType.values.firstWhere(
                (v) => v.name == e,
                orElse: () => ActivityType.unknown,
              ))
          .toList(),
    );
  }

  static T? _parseEnum<T extends Enum>(String? value, List<T> values) {
    if (value == null) return null;
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}
