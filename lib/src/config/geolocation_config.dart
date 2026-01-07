library;

import 'package:locus/src/config/config_enums.dart';
import 'package:locus/src/config/notification_config.dart';
import 'package:locus/src/config/permission_rationale.dart';
import 'package:locus/src/features/location/services/spoof_detection.dart'
    show SpoofDetectionConfig;
import 'package:locus/src/models.dart';

/// Main configuration class for the background geolocation service.
class Config {
  /// Fitness/trail preset (high accuracy, frequent updates).
  factory Config.fitness() => ConfigPresets.trail;

  /// Passive preset (lowest power usage).
  factory Config.passive() => ConfigPresets.lowPower;

  /// Creates a [Config] with optional configuration parameters.
  ///
  /// All parameters are optional and default to null, which uses
  /// platform-specific defaults at runtime.
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
    this.adaptiveTracking,
    this.lowBattery,
    this.spoofDetection,
  });

  /// Creates a [Config] from a map representation.
  ///
  /// Deserializes all configuration fields from the provided [map].
  /// Returns a [Config] instance with all applicable settings.
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
      adaptiveTracking: map['adaptiveTracking'] != null
          ? AdaptiveTrackingConfig.fromMap(
              Map<String, dynamic>.from(map['adaptiveTracking'] as Map))
          : null,
      lowBattery: map['lowBattery'] != null
          ? LowBatteryConfig.fromMap(
              Map<String, dynamic>.from(map['lowBattery'] as Map))
          : null,
      spoofDetection: map['spoofDetection'] != null
          ? SpoofDetectionConfig.fromMap(
              Map<String, dynamic>.from(map['spoofDetection'] as Map))
          : null,
    );
  }

  /// The current SDK version.
  static const String version = '1.1.0';

  // Location settings
  /// Desired location accuracy level.
  final DesiredAccuracy? desiredAccuracy;

  /// Minimum distance in meters device must move before update is triggered.
  final double? distanceFilter;

  /// Desired interval in milliseconds for location updates.
  final int? locationUpdateInterval;

  /// Fastest interval in milliseconds at which app can handle updates.
  final int? fastestLocationUpdateInterval;

  /// Interval in milliseconds for activity recognition updates.
  final int? activityRecognitionInterval;

  /// Minutes device must be stationary before entering stopped state.
  final int? stopTimeout;

  /// Minutes after which tracking automatically stops.
  final int? stopAfterElapsedMinutes;

  /// Delay in milliseconds before stop detection is activated.
  final int? stopDetectionDelay;

  /// Milliseconds to wait before motion triggers location tracking.
  final int? motionTriggerDelay;

  /// Minimum confidence (0-100) required for activity recognition.
  final int? minimumActivityRecognitionConfidence;

  /// Whether to use only significant location changes (iOS).
  final bool? useSignificantChangesOnly;

  /// Whether to record consecutive locations with identical coordinates.
  final bool? allowIdenticalLocations;

  /// Whether to disable motion/activity updates.
  final bool? disableMotionActivityUpdates;

  /// Whether to disable automatic stop detection.
  final bool? disableStopDetection;

  /// Whether to disable recording provider change events.
  final bool? disableProviderChangeRecord;

  /// Whether to disable location authorization alerts (iOS).
  final bool? disableLocationAuthorizationAlert;

  // Background/foreground settings
  /// Whether to enable headless mode for background operation.
  final bool? enableHeadless;

  /// Whether to start tracking automatically on device boot.
  final bool? startOnBoot;

  /// Whether to stop tracking when app terminates.
  final bool? stopOnTerminate;

  /// Whether to enable foreground service notification (Android).
  final bool? foregroundService;

  /// Whether to prevent app suspension during tracking (iOS).
  final bool? preventSuspend;

  /// Whether iOS automatically pauses location updates (iOS).
  final bool? pausesLocationUpdatesAutomatically;

  /// Whether to show background location indicator in status bar (iOS).
  final bool? showsBackgroundLocationIndicator;

  // Motion detection settings
  /// Radius in meters within which device is considered stationary.
  final double? stationaryRadius;

  /// Desired accuracy in meters for odometer distance calculations.
  final double? desiredOdometerAccuracy;

  /// Multiplier for distance filter elasticity during motion.
  final double? elasticityMultiplier;

  /// Maximum speed in m/s; locations exceeding this are filtered.
  final double? speedJumpFilter;

  /// Whether to stop tracking when device becomes stationary.
  final bool? stopOnStationary;

  // Geofencing settings
  /// Whether to use high accuracy mode for geofence monitoring.
  final bool? geofenceModeHighAccuracy;

  /// Whether to trigger entry event if already inside geofence.
  final bool? geofenceInitialTriggerEntry;

  /// Proximity radius in meters for geofence activation.
  final int? geofenceProximityRadius;

  /// Maximum number of geofences to monitor simultaneously.
  final int? maxMonitoredGeofences;

  // HTTP sync settings
  /// Timeout in seconds for acquiring a location fix.
  final int? locationTimeout;

  /// Timeout in milliseconds for HTTP requests.
  final int? httpTimeout;

  /// Maximum number of HTTP retry attempts.
  final int? maxRetry;

  /// Initial delay in milliseconds before first retry.
  final int? retryDelay;

  /// Multiplier for exponential backoff between retries.
  final double? retryDelayMultiplier;

  /// Maximum delay in milliseconds between retries.
  final int? maxRetryDelay;

  /// Background task identifier for iOS background processing.
  final String? bgTaskId;

  /// URL endpoint for HTTP location sync.
  final String? url;

  /// HTTP method for sync requests (GET, POST, PUT, etc.).
  final String? method;

  /// Additional HTTP headers to include in sync requests.
  final JsonMap? headers;

  /// Query parameters to append to sync URL.
  final JsonMap? params;

  /// Extra data to include in every location record.
  final JsonMap? extras;

  /// Whether to automatically sync locations to server.
  final bool? autoSync;

  /// Whether to batch multiple locations in single HTTP request.
  final bool? batchSync;

  /// Maximum number of locations to include in a single batch.
  final int? maxBatchSize;

  /// Number of locations to queue before auto-syncing.
  final int? autoSyncThreshold;

  /// Whether to disable auto-sync when on cellular network.
  final bool? disableAutoSyncOnCellular;

  /// Maximum days to keep queued locations before discarding.
  final int? queueMaxDays;

  /// Maximum number of queued locations before discarding oldest.
  final int? queueMaxRecords;

  /// HTTP header name for idempotency key.
  final String? idempotencyHeader;

  // Persistence settings
  /// Mode for persisting location data locally.
  final PersistMode? persistMode;

  /// Maximum days to persist location data.
  final int? maxDaysToPersist;

  /// Maximum number of location records to persist.
  final int? maxRecordsToPersist;

  /// Template for customizing location data format.
  final String? locationTemplate;

  /// Template for customizing geofence event format.
  final String? geofenceTemplate;

  /// Root property name for location array in HTTP requests.
  final String? httpRootProperty;

  // Scheduling settings
  /// List of time windows (HH:mm-HH:mm) when tracking is active.
  final List<String>? schedule;

  /// Whether to use AlarmManager for schedule (Android).
  final bool? scheduleUseAlarmManager;

  // Force reload settings
  /// Whether to force config reload on device boot.
  final bool? forceReloadOnBoot;

  /// Whether to force config reload on location change.
  final bool? forceReloadOnLocationChange;

  /// Whether to force config reload on motion change.
  final bool? forceReloadOnMotionChange;

  /// Whether to force config reload on geofence event.
  final bool? forceReloadOnGeofence;

  /// Whether to force config reload on heartbeat.
  final bool? forceReloadOnHeartbeat;

  /// Whether to force config reload on schedule change.
  final bool? forceReloadOnSchedule;

  /// Whether to include timestamp metadata in location records.
  final bool? enableTimestampMeta;

  // Notification and logging
  /// Configuration for foreground service notification.
  final NotificationConfig? notification;

  /// Logging verbosity level.
  final LogLevel? logLevel;

  /// Maximum days to retain log files.
  final int? logMaxDays;

  /// Interval in seconds for heartbeat events.
  final int? heartbeatInterval;

  /// Rationale shown when requesting background location permission.
  final PermissionRationale? backgroundPermissionRationale;

  /// Activity types that trigger location tracking.
  final List<ActivityType>? triggerActivities;

  // Advanced Locus 1.2.0+ features
  /// Configuration for adaptive tracking optimization.
  final AdaptiveTrackingConfig? adaptiveTracking;

  /// Configuration for low battery mode.
  final LowBatteryConfig? lowBattery;

  /// Configuration for location spoofing detection.
  final SpoofDetectionConfig? spoofDetection;

  /// Creates a copy of this [Config] with optionally modified fields.
  ///
  /// Returns a new [Config] instance with the specified fields updated
  /// while preserving all other fields from the original.
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
    AdaptiveTrackingConfig? adaptiveTracking,
    LowBatteryConfig? lowBattery,
    SpoofDetectionConfig? spoofDetection,
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
      adaptiveTracking: adaptiveTracking ?? this.adaptiveTracking,
      lowBattery: lowBattery ?? this.lowBattery,
      spoofDetection: spoofDetection ?? this.spoofDetection,
    );
  }

  /// Converts this [Config] to a map representation.
  ///
  /// Returns a map containing all non-null configuration values,
  /// suitable for serialization or platform channel communication.
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

    put('adaptiveTracking', adaptiveTracking?.toMap());
    put('lowBattery', lowBattery?.toMap());
    put('spoofDetection', spoofDetection?.toMap());

    return map;
  }

  /// Parses an enum value from a string representation.
  ///
  /// Returns the matching enum value or null if not found.
  static T? _parseEnum<T extends Enum>(String? value, List<T> values) {
    if (value == null) return null;
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}

/// Ready-to-use configuration presets for common tracking scenarios.
class ConfigPresets {
  const ConfigPresets._();

  /// Lowest power usage preset with coarse accuracy and infrequent updates.
  ///
  /// Best for passive tracking scenarios where battery life is critical.
  static const Config lowPower = Config(
    desiredAccuracy: DesiredAccuracy.low,
    distanceFilter: 200,
    stopTimeout: 15,
    heartbeatInterval: 300,
    autoSync: true,
    batchSync: true,
  );

  /// Balanced preset offering moderate accuracy and reasonable battery usage.
  ///
  /// Good general-purpose configuration for most tracking scenarios.
  static const Config balanced = Config(
    desiredAccuracy: DesiredAccuracy.medium,
    distanceFilter: 50,
    stopTimeout: 8,
    heartbeatInterval: 120,
    autoSync: true,
    batchSync: true,
  );

  /// High accuracy preset for active tracking scenarios.
  ///
  /// Provides frequent updates with good accuracy for real-time tracking.
  static const Config tracking = Config(
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10,
    stopTimeout: 5,
    heartbeatInterval: 60,
    autoSync: true,
    batchSync: true,
  );

  /// Highest accuracy preset with very frequent updates.
  ///
  /// Optimized for fitness tracking, hiking trails, and activities
  /// requiring maximum precision and update frequency.
  static const Config trail = Config(
    desiredAccuracy: DesiredAccuracy.navigation,
    distanceFilter: 5,
    stopTimeout: 2,
    activityRecognitionInterval: 5000,
    heartbeatInterval: 30,
    autoSync: true,
    batchSync: false,
  );
}
