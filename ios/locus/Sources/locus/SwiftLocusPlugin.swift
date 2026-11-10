import Flutter
import UIKit
import CoreLocation
import CoreMotion
import Network
import BackgroundTasks
import UserNotifications

final class LocusEngineBinding: NSObject, FlutterPlugin, FlutterStreamHandler {
  let runtime: SwiftLocusPlugin
  let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  var eventSink: FlutterEventSink?

  init(runtime: SwiftLocusPlugin, registrar: FlutterPluginRegistrar) {
    self.runtime = runtime
    methodChannel = FlutterMethodChannel(
      name: SwiftLocusPlugin.methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel = FlutterEventChannel(
      name: SwiftLocusPlugin.eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    super.init()
    registrar.addMethodCallDelegate(self, channel: methodChannel)
    eventChannel.setStreamHandler(self)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    SwiftLocusPlugin.register(with: registrar)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    runtime.activateEngineForMethod(self)
    runtime.handle(call, result: result, from: self)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    runtime.beginEngineListening(self)
    return runtime.onEngineListen()
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    runtime.endEngineListening(self)
    return nil
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    eventSink = nil
    eventChannel.setStreamHandler(nil)
    methodChannel.setMethodCallHandler(nil)
    runtime.detachEngine(self)
  }
}

public class SwiftLocusPlugin: NSObject, FlutterPlugin, LocationClientDelegate, SyncManagerDelegate, MotionManagerDelegate, SchedulerDelegate, GeofenceManagerDelegate {
  static let methodChannelName = "locus/methods"
  static let eventChannelName = "locus/events"
  static let headlessChannelName = "locus/headless"
  static let headlessDispatcherKey = "bg_headless_dispatcher"
  static let headlessSyncBodyDispatcherKey = "bg_headless_sync_body_dispatcher"
  static let headlessSyncBodyCallbackKey = "bg_headless_sync_body_callback"
  static let headlessCallbackKey = "bg_headless_callback"
  static let tripStateKey = "bg_trip_state"

  /// Native managers are process-owned; every Flutter engine gets a lightweight
  /// binding to this runtime. This keeps background tracking singular while
  /// allowing a replacement UI engine to regain control after engine teardown.
  private static let sharedRuntime = SwiftLocusPlugin()
  private let engineBindings = EngineBindingRegistry()
  lazy var callbackBroker = EngineCallbackBroker(
    bindings: engineBindings,
    deadlineScheduler: mainQueueCallbackDeadlineScheduler
  )
  private var activeEngine: LocusEngineBinding? {
    engineBindings.activeBinding as? LocusEngineBinding
  }

  // Managers
  let configManager = ConfigManager()
  let storage: StorageManager
  let syncManager: SyncManager
  let motionDetector: MotionManager
  let scheduler: Scheduler
  let geofenceManager: GeofenceManager
  let trackingStats = TrackingStats()
  let headlessValidationDispatcher: HeadlessValidationDispatcher
  let headlessHeadersDispatcher: HeadlessHeadersDispatcher

  // State
  let locationClient: LocationClient
  var eventSink: FlutterEventSink? { activeEngine?.eventSink }
  var pendingLocationResult: FlutterResult?
  let locationRequestGate = SingleFlightRequestGate()
  private weak var currentCallEngine: LocusEngineBinding?
  var isEnabled = false
  private let lastLocationQueue = DispatchQueue(label: "dev.locus.lastLocation")
  private var _lastLocation: CLLocation?
  var lastLocation: CLLocation? {
    get { lastLocationQueue.sync { _lastLocation } }
    set { lastLocationQueue.sync { _lastLocation = newValue } }
  }
  let networkQueue = DispatchQueue(label: "dev.locus.network")
  var networkMonitor: NWPathMonitor?

  // Timers
  var heartbeatTimer: Timer?

  var headlessEngine: FlutterEngine?
  var headlessLastActivityTime: Date?
  var headlessCleanupTimer: Timer?
  var backgroundTaskCounter = 1
  var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  var registeredBgTaskIds: Set<String> = []
  var methodChannel: FlutterMethodChannel? { activeEngine?.methodChannel }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let binding = LocusEngineBinding(runtime: sharedRuntime, registrar: registrar)
    registrar.publish(binding)
  }

  override init() {
    storage = StorageManager(sqliteStorage: SQLiteStorage())
    syncManager = SyncManager(config: configManager, storage: storage)
    motionDetector = MotionManager(config: configManager)
    scheduler = Scheduler(config: configManager)
    geofenceManager = GeofenceManager(config: configManager, storage: storage)
    locationClient = LocationClient(config: configManager)
    headlessValidationDispatcher = HeadlessValidationDispatcher(config: configManager)
    headlessHeadersDispatcher = HeadlessHeadersDispatcher(config: configManager)
    super.init()

    // Migrate existing UserDefaults data to Keychain for security
    SecureStorage.shared.migrateFromUserDefaults()

    // Geofences are not armed while storage is unavailable; arm them once it recovers.
    storage.setRecoveryHandler { [weak self] in
      guard let self, self.isEnabled else { return }
      self.geofenceManager.startStoredGeofences()
    }

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
    // iOS has no device-boot callback equivalent. Cold recovery is governed
    // solely by persisted desired tracking state, never startOnBoot.
    DispatchQueue.main.async { [weak self] in
      self?.maybeResumePersistedTracking()
    }
    registerBackgroundTasks()
  }

  deinit {
    stopConnectivityMonitor()
    NotificationCenter.default.removeObserver(self)
    releaseBackgroundTasks()
    stopHeartbeatTimer()
    scheduler.stop()
    syncManager.release()
    headlessCleanupTimer?.invalidate()
    headlessCleanupTimer = nil
    headlessEngine?.destroyContext()
    headlessEngine = nil

    // Honor stopOnTerminate: if the host configured `stopOnTerminate:false` (the
    // canonical always-on recipe), we must NOT stop the CLLocationManager here.
    // CoreLocation + UIBackgroundModes=location + startMonitoringSignificantLocation
    // Changes can relaunch the process later; stopping updates in deinit would
    // defeat that. deinit is best-effort on iOS anyway — the OS may kill the process
    // without running destructors — but when it does run, this path matters.
    if configManager.stopOnTerminate {
      UserDefaults.standard.set(false, forKey: ConfigManager.trackingActiveKey)
      motionDetector.stop()
      locationClient.stop()
    }
  }

  fileprivate func activateEngineForMethod(_ engine: LocusEngineBinding) {
    callbackBroker.bindingClaimed(engineBindings.activateForMethod(engine))
  }

  fileprivate func beginEngineListening(_ engine: LocusEngineBinding) {
    callbackBroker.bindingClaimed(engineBindings.beginListening(engine))
  }

  fileprivate func endEngineListening(_ engine: LocusEngineBinding) {
    engineBindings.endListening(engine)
  }

  fileprivate func detachEngine(_ engine: LocusEngineBinding) {
    if locationRequestGate.detach(owner: engine), let pending = pendingLocationResult {
      pendingLocationResult = nil
      pending(FlutterError(
        code: "ENGINE_DETACHED",
        message: "The Flutter engine detached before getCurrentPosition completed",
        details: nil
      ))
    }
    engineBindings.detach(engine)
    callbackBroker.ownerDetached(engine)
  }

  fileprivate func onEngineListen() -> FlutterError? {
    emitConnectivityChange(ProcessInfo.processInfo.isLowPowerModeEnabled, emitPowerSave: true)
    // Replay the current pause state so a freshly-attached Dart listener sees a
    // persisted 401/403 pause without having to poll getSyncPauseState.
    syncManager.replaySyncPauseState()
    return nil
  }

  fileprivate func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult,
    from engine: LocusEngineBinding
  ) {
    currentCallEngine = engine
    defer { currentCallEngine = nil }
    handle(call, result: result)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      if let config = call.arguments as? [String: Any] {
        do {
          try applyConfig(config)
        } catch {
          result(configFlutterError(error))
          return
        }
      }
      // Emit a warning if location permissions are denied or not determined
      let authStatus = locationClient.getAuthorizationStatus()
      if authStatus == .denied || authStatus == .restricted {
        let errorEvent: [String: Any] = [
          "type": "error",
          "data": [
            "code": "ERR_PERMISSION_DENIED",
            "message": "Location permission is \(authStatus == .denied ? "denied" : "restricted"). Request permission before starting tracking."
          ]
        ]
        sendEvent(errorEvent)
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
      guard let engine = currentCallEngine,
            locationRequestGate.begin(owner: engine) else {
        result(FlutterError(
          code: "LOCATION_REQUEST_IN_PROGRESS",
          message: "Another getCurrentPosition request is already in progress",
          details: nil
        ))
        return
      }
      pendingLocationResult = result
      locationClient.requestLocation()
    case "hasPreciseLocationPermission":
      // Precise location requires both an authorized status (when-in-use OR
      // always) AND, on iOS 14+, the user-facing "Precise Location" toggle
      // being on. Authorization and accuracy are process-wide on iOS, so a
      // transient CLLocationManager instance returns the same value as
      // LocationClient's manager — no need to expose internals.
      let probe = CLLocationManager()
      let authStatus: CLAuthorizationStatus
      if #available(iOS 14.0, *) {
        authStatus = probe.authorizationStatus
      } else {
        authStatus = CLLocationManager.authorizationStatus()
      }
      let authorized = authStatus == .authorizedWhenInUse
        || authStatus == .authorizedAlways
      let precise: Bool
      if #available(iOS 14.0, *) {
        precise = probe.accuracyAuthorization == .fullAccuracy
      } else {
        // Pre-iOS 14 has no reduced-accuracy concept; "authorized" implies precise.
        precise = true
      }
      result(authorized && precise)
    case "setConfig":
      if let config = call.arguments as? [String: Any] {
        do {
          try applyConfig(config)
        } catch {
          result(configFlutterError(error))
          return
        }
      }
      result(true)
    case "reset":
      if let config = call.arguments as? [String: Any] {
        do {
          try applyConfig(config)
        } catch {
          result(configFlutterError(error))
          return
        }
      }
      result(true)
    case "changePace":
      if let moving = call.arguments as? Bool {
        motionDetector.setMovingManually(moving)
      }
      result(true)
    case "addGeofence":
      if replyIfStorageUnavailable(result) { return }
      if let geofence = call.arguments as? [String: Any] {
        geofenceManager.addGeofence(geofence)
      }
      result(true)
    case "addGeofences":
      if replyIfStorageUnavailable(result) { return }
      if let geofences = call.arguments as? [[String: Any]] {
        for geofence in geofences {
          geofenceManager.addGeofence(geofence)
        }
      }
      result(true)
    case "removeGeofence":
      if replyIfStorageUnavailable(result) { return }
      if let identifier = call.arguments as? String {
        geofenceManager.removeGeofence(identifier)
      }
      result(true)
    case "removeGeofences":
      if replyIfStorageUnavailable(result) { return }
      geofenceManager.removeAllGeofences()
      result(true)
    case "getGeofence":
      if replyIfStorageUnavailable(result) { return }
      if let identifier = call.arguments as? String {
        result(geofenceManager.getGeofence(identifier))
      } else {
        result(nil)
      }
    case "getGeofences":
      if replyIfStorageUnavailable(result) { return }
      // Filter out invalid geofences before returning to Dart
      let allGeofences = storage.readGeofences()
      let validGeofences = allGeofences.filter { isValidGeofence($0) }
      result(validGeofences)
    case "geofenceExists":
      if replyIfStorageUnavailable(result) { return }
      if let identifier = call.arguments as? String {
        result(geofenceManager.getGeofence(identifier) != nil)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected geofence identifier string", details: nil))
      }
    case "setPrivacyMode":
      if let enabled = call.arguments as? Bool {
        do {
          try configManager.setPrivacyMode(enabled)
        } catch {
          result(configFlutterError(error))
          return
        }
      }
      result(true)
    case "startGeofences":
      if replyIfStorageUnavailable(result) { return }
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
      if replyIfStorageUnavailable(result) { return }
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
      if replyIfStorageUnavailable(result) { return }
      if let args = call.arguments as? [String: Any], let limit = args["limit"] as? Int {
        let stored = storage.readQueue()
        result(Array(stored.prefix(limit)))
      } else {
        result(storage.readQueue())
      }
    case "clearQueue":
      if replyIfStorageUnavailable(result) { return }
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
      result(configManager.persistedConfig)
    case "getDiagnosticsMetadata":
      result(buildDiagnosticsMetadata())
    case "queryLocations":
      do {
        let query = try StoredLocationQuery(arguments: call.arguments)
        storage.queryLocations(query) { outcome in
          switch outcome {
          case .success(let locations):
            result(locations)
          case .failure(let error as StorageUnavailableError):
            result(Self.storageUnavailableFlutterError(error))
          case .failure(let error):
            result(FlutterError(code: "LOCATION_QUERY_ERROR", message: error.localizedDescription, details: nil))
          }
        }
      } catch {
        result(FlutterError(code: "INVALID_ARGUMENT", message: error.localizedDescription, details: nil))
      }
    case "getManufacturer":
      // Mirror of the Android handler used by DeviceOptimizationService.
      // iOS hardware is single-vendor; the "Don't Kill My App" map is
      // Android-only, so returning nil lets the Dart caller short-circuit
      // without a platform check at the call site.
      result(nil)
    case "startSchedule", "stopSchedule", "sync", "getLog", "emailLog", "playSound", "destroyLocations", "getLocations", "registerHeadlessTask", "setAdaptiveTracking":
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
        if replyIfStorageUnavailable(result) { return }
        storage.writeLocations([])
        result(true)
      } else if call.method == "getLocations" {
        if replyIfStorageUnavailable(result) { return }
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
          let stored = SecureStorage.shared.setCallbackHandles(
            dispatcher: dispatcher,
            callback: callback,
            forKey: SecureStorage.headlessHandlesKey
          )
          result(stored ? true : secureStorageFlutterError())
        } else if let handle = call.arguments as? Int64 {
          // Backwards compatibility for the old callback-only channel shape.
          // Prefer updating the atomic pair when a dispatcher already exists.
          let existing = SecureStorage.shared.getCallbackHandles(
            forKey: SecureStorage.headlessHandlesKey,
            legacyDispatcherKey: SecureStorage.headlessDispatcherKey,
            legacyCallbackKey: SecureStorage.headlessCallbackKey
          )
          let dispatcher = existing?.dispatcher
            ?? SecureStorage.shared.getInt64(
              forKey: SecureStorage.headlessDispatcherKey
            )
          let stored: Bool
          if let dispatcher {
            stored = SecureStorage.shared.setCallbackHandles(
              dispatcher: dispatcher,
              callback: handle,
              forKey: SecureStorage.headlessHandlesKey
            )
          } else {
            stored = SecureStorage.shared.setInt64(
              handle,
              forKey: SecureStorage.headlessCallbackKey
            )
          }
          result(stored ? true : secureStorageFlutterError())
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected headless callback handle", details: nil))
        }
      } else if call.method == "getLog" {
        if replyIfStorageUnavailable(result) { return }
        result(readLog())
      } else if call.method == "setAdaptiveTracking" {
        // Adaptive profile calculation is Dart-owned; native receives the
        // resulting setConfig calls. Keep this method as a parity no-op.
        result(true)
      } else {
        result(FlutterError(code: "NOT_IMPLEMENTED", message: "Unknown headless method", details: nil))
      }
    case "registerHeadlessSyncBodyBuilder":
      if let args = call.arguments as? [String: Any],
         let dispatcher = args["dispatcher"] as? Int64,
         let callback = args["callback"] as? Int64 {
        let stored = SecureStorage.shared.setCallbackHandles(
          dispatcher: dispatcher,
          callback: callback,
          forKey: SecureStorage.headlessSyncBodyHandlesKey
        )
        result(stored ? true : secureStorageFlutterError())
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected dispatcher and callback handles", details: nil))
      }
    case "registerHeadlessValidationCallback":
      if let args = call.arguments as? [String: Any],
         let dispatcher = args["dispatcher"] as? Int64,
         let callback = args["callback"] as? Int64 {
        let stored = HeadlessValidationDispatcher.registerCallback(
          dispatcher: dispatcher,
          callback: callback
        )
        result(stored ? true : secureStorageFlutterError())
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected dispatcher and callback handles", details: nil))
      }
    case "registerHeadlessHeadersCallback":
      if let args = call.arguments as? [String: Any],
         let dispatcher = args["dispatcher"] as? Int64,
         let callback = args["callback"] as? Int64 {
        let stored = HeadlessHeadersDispatcher.registerCallback(
          dispatcher: dispatcher,
          callback: callback
        )
        result(stored ? true : secureStorageFlutterError())
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected dispatcher and callback handles", details: nil))
      }
    case "setSyncBodyBuilderEnabled":
      // Enable/disable the Dart-side sync body builder
      if let enabled = call.arguments as? Bool {
        syncManager.syncBodyBuilderEnabled = enabled
      }
      result(true)
    case "getLocationSyncBacklog":
      result(syncManager.getLocationSyncBacklog())
    case "getSyncPauseState":
      result(syncManager.getSyncPauseState())
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
    case "updateNotification":
      guard isEnabled else {
        result(false)
        return
      }
      let args = call.arguments as? [String: Any]
      let title = args?["title"] as? String
      let text = args?["text"] as? String
      updateTrackingNotification(title: title, text: text) { updated in
        DispatchQueue.main.async {
          result(updated)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func applyConfig(_ config: [String: Any]) throws {
    try configManager.apply(config)
    locationClient.applyConfig()

    locationClient.setDistanceFilter(motionDetector.isMoving ? configManager.distanceFilter : configManager.stationaryRadius)

    if configManager.disableMotionActivityUpdates {
      motionDetector.stop()
    } else if isEnabled {
      motionDetector.start()
    }
    registerBackgroundTasks()
    maybeResumePersistedTracking()
  }

  private func configFlutterError(_ error: Error) -> FlutterError {
    FlutterError(
      code: "CONFIG_PERSISTENCE_ERROR",
      message: error.localizedDescription,
      details: nil
    )
  }

  private static func storageUnavailableFlutterError(_ error: StorageUnavailableError) -> FlutterError {
    FlutterError(
      code: "STORAGE_UNAVAILABLE",
      message: "Encrypted storage is unavailable",
      details: error.reason
    )
  }

  /// Replies `STORAGE_UNAVAILABLE` and returns true when the encrypted database
  /// is not open, so callers never report success or empty data for it.
  private func replyIfStorageUnavailable(_ result: FlutterResult) -> Bool {
    do {
      try storage.requireAvailable()
      return false
    } catch let error as StorageUnavailableError {
      result(Self.storageUnavailableFlutterError(error))
      return true
    } catch {
      result(FlutterError(code: "STORAGE_UNAVAILABLE", message: "Encrypted storage is unavailable", details: error.localizedDescription))
      return true
    }
  }

  private func secureStorageFlutterError() -> FlutterError {
    FlutterError(
      code: "SECURE_STORAGE_ERROR",
      message: "Unable to store callback handles in iOS Keychain",
      details: nil
    )
  }

  // MARK: - Notification Support

  private static let trackingNotificationIdentifier = "dev.locus.tracking"

  private func withTrackingNotificationAuthorization(
    _ completion: @escaping (Bool) -> Void
  ) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        completion(true)
      case .notDetermined:
        NSLog("[locus] updateNotification: notification permission not yet requested — the host app must call UNUserNotificationCenter.requestAuthorization() before using this API")
        completion(false)
      case .denied:
        NSLog("[locus] updateNotification: notification permission denied by user")
        completion(false)
      @unknown default:
        completion(false)
      }
    }
  }

  func updateTrackingNotification(
    title: String?,
    text: String?,
    completion: @escaping (Bool) -> Void
  ) {
    withTrackingNotificationAuthorization { granted in
      guard granted else {
        completion(false)
        return
      }

      let content = UNMutableNotificationContent()
      content.title = title ?? "Locus"
      content.body = text ?? "Tracking location"
      // Silent update — no repeated sound/vibration
      content.sound = nil

      let request = UNNotificationRequest(
        identifier: Self.trackingNotificationIdentifier,
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request) { error in
        completion(error == nil)
      }
    }
  }

  private func removeTrackingNotification() {
    let id = Self.trackingNotificationIdentifier
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
  }

  // MARK: - Tracking Lifecycle

  func startTracking() {
    if isEnabled {
      return
    }
    let auth = locationClient.getAuthorizationStatus()
    if !locationClient.isLocationServicesEnabled() {
      emitProviderChange()
      return
    }
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
    UserDefaults.standard.set(true, forKey: ConfigManager.trackingActiveKey)
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
    let wasEnabled = isEnabled
    isEnabled = false
    UserDefaults.standard.set(false, forKey: ConfigManager.trackingActiveKey)
    if wasEnabled {
      trackingStats.onTrackingStop()
    }
    locationClient.stop()
    motionDetector.stop()
    removeTrackingNotification()
    if wasEnabled {
      emitEnabledChange(false)
    }
    stopHeartbeatTimer()
    stopBackgroundRefresh()
  }

  /// Cold-start reconciliation: if iOS terminated the process while tracking was
  /// active and significant-change monitoring later relaunches it, the persisted
  /// flag is still `true`. Re-arm tracking so that `Locus.isTracking()` reports
  /// accurately and locations keep flowing after the new process starts. A user
  /// force-quit remains an OS-enforced stop boundary until the app is opened again.
  /// Silent no-op when permissions were revoked or nothing was active.
  func maybeResumePersistedTracking() {
    let auth = locationClient.getAuthorizationStatus()
    let action = decideTrackingRecovery(
      trackingDesired: UserDefaults.standard.bool(forKey: ConfigManager.trackingActiveKey),
      runtimeEnabled: isEnabled,
      configStatus: configManager.persistedConfigStatus,
      hasAlwaysAuthorization: auth == .authorizedAlways,
      locationServicesEnabled: locationClient.isLocationServicesEnabled(),
      stopOnTerminate: configManager.stopOnTerminate
    )

    switch action {
    case .none, .keepRunning:
      return
    case .waitForConfig:
      NSLog("[locus] Recovery deferred: persisted configuration is corrupt or temporarily unavailable")
    case .clearDesiredState:
      UserDefaults.standard.set(false, forKey: ConfigManager.trackingActiveKey)
      if isEnabled { stopTracking() }
    case .stopRuntime:
      stopTracking()
    case .start:
      NSLog("[locus] Re-arming tracking from valid persisted intent and configuration")
      startTracking()
    }
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
