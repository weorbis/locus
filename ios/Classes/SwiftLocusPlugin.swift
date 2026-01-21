import Flutter
import UIKit
import CoreLocation
import CoreMotion
import Network
import BackgroundTasks

public class SwiftLocusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, LocationClientDelegate, SyncManagerDelegate, MotionManagerDelegate, SchedulerDelegate, GeofenceManagerDelegate {
  static let methodChannelName = "locus/methods"
  static let eventChannelName = "locus/events"
  static let headlessChannelName = "locus/headless"
  static let headlessDispatcherKey = "bg_headless_dispatcher"
  static let headlessSyncBodyDispatcherKey = "bg_headless_sync_body_dispatcher"
  static let headlessSyncBodyCallbackKey = "bg_headless_sync_body_callback"
  static let headlessCallbackKey = "bg_headless_callback"
  static let tripStateKey = "bg_trip_state"

  // Managers
  let configManager = ConfigManager()
  let storage: StorageManager
  let syncManager: SyncManager
  let motionDetector: MotionManager
  let scheduler: Scheduler
  let geofenceManager: GeofenceManager
  let trackingStats = TrackingStats()
  let headlessValidationDispatcher: HeadlessValidationDispatcher

  // State
  let locationClient: LocationClient
  var eventSink: FlutterEventSink?
  var pendingLocationResult: FlutterResult?
  var isEnabled = false
  var lastLocation: CLLocation?
  let networkQueue = DispatchQueue(label: "dev.locus.network")
  var networkMonitor: NWPathMonitor?

  // Timers
  var heartbeatTimer: Timer?

  var headlessEngine: FlutterEngine?
  var backgroundTaskCounter = 1
  var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  var registeredBgTaskId: String?
  var methodChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftLocusPlugin()
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
    instance.methodChannel = methodChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  override init() {
    storage = StorageManager(sqliteStorage: SQLiteStorage())
    syncManager = SyncManager(config: configManager, storage: storage)
    motionDetector = MotionManager(config: configManager)
    scheduler = Scheduler(config: configManager)
    geofenceManager = GeofenceManager(config: configManager, storage: storage)
    locationClient = LocationClient(config: configManager)
    headlessValidationDispatcher = HeadlessValidationDispatcher(config: configManager)
    super.init()

    // Migrate existing UserDefaults data to Keychain for security
    SecureStorage.shared.migrateFromUserDefaults()

    // Wire delegates
    locationClient.delegate = self
    syncManager.delegate = self
    motionDetector.delegate = self
    scheduler.delegate = self
    geofenceManager.delegate = self

    startConnectivityMonitor()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(powerSaveModeChanged),
      name: Notification.Name.NSProcessInfoPowerStateDidChange,
      object: nil
    )
    if configManager.startOnBoot {
      DispatchQueue.main.async { [weak self] in
        self?.maybeStartOnBoot()
      }
    }
    registerBackgroundTasks()
  }

  deinit {
    stopConnectivityMonitor()
    NotificationCenter.default.removeObserver(self)
    releaseBackgroundTasks()
    stopHeartbeatTimer()
    motionDetector.stop()
    scheduler.stop()
    syncManager.release()
    headlessEngine?.destroyContext()
    headlessEngine = nil
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitConnectivityChange(ProcessInfo.processInfo.isLowPowerModeEnabled, emitPowerSave: true)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      if let config = call.arguments as? [String: Any] {
        applyConfig(config)
      }
      result(buildState())
    case "start":
      startTracking()
      result(buildState())
    case "stop":
      stopTracking()
      result(buildState())
    case "getState":
      result(buildState())
    case "getCurrentPosition":
      pendingLocationResult = result
      locationClient.requestLocation()
    case "setConfig":
      if let config = call.arguments as? [String: Any] {
        applyConfig(config)
      }
      result(true)
    case "reset":
      if let config = call.arguments as? [String: Any] {
        applyConfig(config)
      }
      result(true)
    case "changePace":
      if let moving = call.arguments as? Bool {
        motionDetector.setMovingManually(moving)
      }
      result(true)
    case "addGeofence":
      if let geofence = call.arguments as? [String: Any] {
        geofenceManager.addGeofence(geofence)
      }
      result(true)
    case "addGeofences":
      if let geofences = call.arguments as? [[String: Any]] {
        for geofence in geofences {
          geofenceManager.addGeofence(geofence)
        }
      }
      result(true)
    case "removeGeofence":
      if let identifier = call.arguments as? String {
        geofenceManager.removeGeofence(identifier)
      }
      result(true)
    case "removeGeofences":
      geofenceManager.removeAllGeofences()
      result(true)
    case "getGeofence":
      if let identifier = call.arguments as? String {
        result(geofenceManager.getGeofence(identifier))
      } else {
        result(nil)
      }
    case "getGeofences":
      // Filter out invalid geofences before returning to Dart
      let allGeofences = storage.readGeofences()
      let validGeofences = allGeofences.filter { isValidGeofence($0) }
      result(validGeofences)
    case "geofenceExists":
      if let identifier = call.arguments as? String {
        result(geofenceManager.getGeofence(identifier) != nil)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected geofence identifier string", details: nil))
      }
    case "setPrivacyMode":
      if let enabled = call.arguments as? Bool {
        configManager.privacyModeEnabled = enabled
      }
      result(true)
    case "startGeofences":
      geofenceManager.startStoredGeofences()
      result(true)
    case "setOdometer":
      if let value = call.arguments as? NSNumber {
        storage.writeOdometer(value.doubleValue)
        result(value.doubleValue)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected numeric odometer", details: nil))
      }
    case "enqueue":
      if let args = call.arguments as? [String: Any],
         let payload = args["payload"] as? [String: Any] {
        let type = args["type"] as? String
        let idempotencyKey = (args["idempotencyKey"] as? String) ?? UUID().uuidString
        let id = storage.addToQueue(payload: payload, type: type, idempotencyKey: idempotencyKey)
        result(id)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected payload map", details: nil))
      }
    case "getQueue":
      if let args = call.arguments as? [String: Any], let limit = args["limit"] as? Int {
        let stored = storage.readQueue()
        result(Array(stored.prefix(limit)))
      } else {
        result(storage.readQueue())
      }
    case "clearQueue":
      storage.writeQueue([])
      result(true)
    case "syncQueue":
      result(syncManager.syncQueue(limit: (call.arguments as? [String: Any])?["limit"] as? Int ?? 0))
    case "resumeSync":
      syncManager.resumeSync()
      result(true)
    case "pauseSync":
      syncManager.pause()
      result(true)
    case "storeTripState":
      if let state = call.arguments as? [String: Any] {
        UserDefaults.standard.setValue(state, forKey: SwiftLocusPlugin.tripStateKey)
        result(true)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected trip state map", details: nil))
      }
    case "readTripState":
      result(UserDefaults.standard.dictionary(forKey: SwiftLocusPlugin.tripStateKey))
    case "clearTripState":
      UserDefaults.standard.removeObject(forKey: SwiftLocusPlugin.tripStateKey)
      result(true)
    case "getConfig":
      result(UserDefaults.standard.dictionary(forKey: "bg_last_config") ?? [:])
    case "getDiagnosticsMetadata":
      result(buildDiagnosticsMetadata())
    case "startSchedule", "stopSchedule", "sync", "getLog", "emailLog", "playSound", "destroyLocations", "getLocations", "registerHeadlessTask":
      if call.method == "startSchedule" {
        configManager.scheduleEnabled = true
        emitScheduleEvent()
        scheduler.start()
        scheduler.applyScheduleState()
        result(true)
      } else if call.method == "stopSchedule" {
        configManager.scheduleEnabled = false
        scheduler.stop()
        result(true)
      } else if call.method == "sync" {
        syncManager.resumeSync()
        syncManager.syncNow()
        result(true)
      } else if call.method == "destroyLocations" {
        storage.writeLocations([])
        result(true)
      } else if call.method == "getLocations" {
        if let args = call.arguments as? [String: Any], let limit = args["limit"] as? Int {
          let stored = storage.readLocations()
          result(Array(stored.suffix(limit)))
        } else {
          result(storage.readLocations())
        }
      } else if call.method == "registerHeadlessTask" {
        if let args = call.arguments as? [String: Any],
           let dispatcher = args["dispatcher"] as? Int64,
           let callback = args["callback"] as? Int64 {
          // Use SecureStorage for sensitive callback handles
          _ = SecureStorage.shared.setInt64(dispatcher, forKey: SecureStorage.headlessDispatcherKey)
          _ = SecureStorage.shared.setInt64(callback, forKey: SecureStorage.headlessCallbackKey)
          result(true)
        } else if let handle = call.arguments as? Int64 {
          _ = SecureStorage.shared.setInt64(handle, forKey: SecureStorage.headlessCallbackKey)
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected headless callback handle", details: nil))
        }
      } else if call.method == "getLog" {
        result(readLog())
      } else {
        result(FlutterError(code: "NOT_IMPLEMENTED", message: "Unknown headless method", details: nil))
      }
    case "registerHeadlessSyncBodyBuilder":
      if let args = call.arguments as? [String: Any],
         let dispatcher = args["dispatcher"] as? Int64,
         let callback = args["callback"] as? Int64 {
        // Use SecureStorage for sensitive callback handles
        _ = SecureStorage.shared.setInt64(dispatcher, forKey: SecureStorage.headlessSyncBodyDispatcherKey)
        _ = SecureStorage.shared.setInt64(callback, forKey: SecureStorage.headlessSyncBodyCallbackKey)
        result(true)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected dispatcher and callback handles", details: nil))
      }
    case "registerHeadlessValidationCallback":
      if let args = call.arguments as? [String: Any],
         let dispatcher = args["dispatcher"] as? Int64,
         let callback = args["callback"] as? Int64 {
        HeadlessValidationDispatcher.registerCallback(dispatcher: dispatcher, callback: callback)
        result(true)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected dispatcher and callback handles", details: nil))
      }
    case "setSyncBodyBuilderEnabled":
      // Enable/disable the Dart-side sync body builder
      if let enabled = call.arguments as? Bool {
        syncManager.syncBodyBuilderEnabled = enabled
      }
      result(true)
    case "startBackgroundTask":
      result(startBackgroundTask())
    case "stopBackgroundTask":
      if let taskId = call.arguments as? Int {
        endBackgroundTask(taskId)
      }
      result(true)
    case "getBatteryStats":
      result(buildBatteryStats())
    case "getPowerState":
      result(buildPowerState())
    case "getNetworkType":
      result(getNetworkTypeString())
    case "isIgnoringBatteryOptimizations":
      result(false)
    case "setSpoofDetection":
      // Spoof detection is handled on Dart side
      result(true)
    case "startSignificantChangeMonitoring":
      // Significant change monitoring is handled on Dart side
      result(true)
    case "stopSignificantChangeMonitoring":
      // Significant change monitoring is handled on Dart side
      result(true)
    case "setDynamicHeaders":
      if let headers = call.arguments as? [String: String] {
        configManager.dynamicHeaders = headers
      }
      result(true)
    case "setSyncPolicy":
      if let args = call.arguments as? [String: Any] {
        if let syncOnCellular = args["syncOnCellular"] as? Bool {
          configManager.syncOnCellular = syncOnCellular
        }
        if let syncInterval = args["syncInterval"] as? Int {
          configManager.syncInterval = syncInterval
        }
        if let batchSync = args["batchSync"] as? Bool {
          configManager.batchSync = batchSync
        }
      }
      result(true)
    case "isMeteredConnection":
      let path = networkMonitor?.currentPath
      let isCellular = path?.usesInterfaceType(.cellular) ?? false
      result(isCellular)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func applyConfig(_ config: [String: Any]) {
    configManager.apply(config)
    locationClient.applyConfig()

    locationClient.setDistanceFilter(motionDetector.isMoving ? configManager.distanceFilter : configManager.stationaryRadius)

    if configManager.disableMotionActivityUpdates {
      motionDetector.stop()
    } else if isEnabled {
      motionDetector.start()
    }
    registerBackgroundTasks()
  }

  func startTracking() {
    if isEnabled {
      return
    }
    let auth = locationClient.getAuthorizationStatus()
      if auth == .notDetermined {
        locationClient.requestPermissions()
        emitProviderChange()
        return
      }
      if auth == .authorizedWhenInUse {
        locationClient.requestAlwaysAuthorization()
        emitProviderChange()
        return
      }
      if auth == .denied || auth == .restricted {
      emitProviderChange()
      return
    }
    isEnabled = true
    trackingStats.onTrackingStart()
    locationClient.start()
    motionDetector.start()
    geofenceManager.startStoredGeofences()
    emitProviderChange()
    emitEnabledChange(true)
    startHeartbeatTimer()
    scheduleBackgroundRefresh()
  }

  func stopTracking() {
    if !isEnabled {
      return
    }
    isEnabled = false
    trackingStats.onTrackingStop()
    locationClient.stop()
    motionDetector.stop()
    emitEnabledChange(false)
    stopHeartbeatTimer()
    stopBackgroundRefresh()
  }

  func buildState() -> [String: Any] {
    var state: [String: Any] = [
      "enabled": isEnabled,
      "isMoving": motionDetector.isMoving,
      "odometer": storage.readOdometer()
    ]
    if let location = lastLocation {
      state["location"] = buildLocationPayload(location, eventName: "location")
    }
    return state
  }

  /// Validates that a geofence dictionary has all required fields with valid values.
  /// This prevents returning corrupted data to Dart that would cause warnings.
  private func isValidGeofence(_ geofence: [String: Any]) -> Bool {
    guard let identifier = geofence["identifier"] as? String, !identifier.isEmpty,
          let radius = geofence["radius"] as? Double, radius > 0,
          let latitude = geofence["latitude"] as? Double, latitude >= -90, latitude <= 90,
          let longitude = geofence["longitude"] as? Double, longitude >= -180, longitude <= 180 else {
      return false
    }
    return true
  }
}
