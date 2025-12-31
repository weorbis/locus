import Foundation
import CoreLocation

class ConfigManager {
    static let shared = ConfigManager()
    
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var stationaryRadius: CLLocationDistance = 25
    var pausesLocationUpdatesAutomatically = false
    var showsBackgroundLocationIndicator = false
    var httpUrl: String?
    var httpMethod: String = "POST"
    var autoSync: Bool = false
    var httpHeaders: [String: String] = [:]
    var httpParams: [String: Any] = [:]
    var httpTimeout: TimeInterval = 10
    var maxRetry = 0
    var retryDelay: TimeInterval = 5
    var retryDelayMultiplier: Double = 2.0
    var maxRetryDelay: TimeInterval = 60
    var disableAutoSyncOnCellular = false
    var batchSync = false
    var maxBatchSize = 50
    var autoSyncThreshold = 0
    var persistMode = "none"
    var httpRootProperty: String?
    var queueMaxDays = 0
    var queueMaxRecords = 0
    var idempotencyHeader = "Idempotency-Key"
    var logLevel = "info"
    var logMaxDays = 0
    var maxDaysToPersist = 0
    var maxRecordsToPersist = 0
    var scheduleEnabled = false
    var schedule: [String] = []
    var heartbeatInterval: TimeInterval = 0
    var stopTimeoutMinutes: Int = 0
    var motionTriggerDelayMs: Int = 0
    var disableMotionActivityUpdates = false
    var disableStopDetection = false
    var triggerActivities: [String] = []
    var maxMonitoredGeofences = 0
    var enableHeadless = false
    var stopOnTerminate = true
    var startOnBoot = false
    var bgTaskId = "dev.locus.refresh"
    
    // Constants shared across plugin
    static let startOnBootKey = "bg_start_on_boot"
    static let stopOnTerminateKey = "bg_stop_on_terminate"
    static let enableHeadlessKey = "bg_enable_headless"
    static let lastConfigKey = "bg_last_config"
    
    private init() {
        // Load persisted critical flags
        if let config = UserDefaults.standard.dictionary(forKey: ConfigManager.lastConfigKey) {
            apply(config)
        }
        startOnBoot = UserDefaults.standard.bool(forKey: ConfigManager.startOnBootKey)
        stopOnTerminate = UserDefaults.standard.bool(forKey: ConfigManager.stopOnTerminateKey)
        enableHeadless = UserDefaults.standard.bool(forKey: ConfigManager.enableHeadlessKey)
    }
    
    func apply(_ config: [String: Any]) {
        UserDefaults.standard.setValue(config, forKey: ConfigManager.lastConfigKey)
        
        if let desired = config["desiredAccuracy"] as? String {
            switch desired {
            case "navigation", "high": desiredAccuracy = kCLLocationAccuracyBest
            case "medium": desiredAccuracy = kCLLocationAccuracyHundredMeters
            case "low", "veryLow": desiredAccuracy = kCLLocationAccuracyKilometer
            case "lowest": desiredAccuracy = kCLLocationAccuracyThreeKilometers
            default: desiredAccuracy = kCLLocationAccuracyBest
            }
        }
        
        if let val = config["distanceFilter"] as? NSNumber { distanceFilter = val.doubleValue }
        if let val = config["stationaryRadius"] as? NSNumber { stationaryRadius = val.doubleValue }
        if let val = config["disableMotionActivityUpdates"] as? Bool { disableMotionActivityUpdates = val }
        if let val = config["disableStopDetection"] as? Bool { disableStopDetection = val }
        if let val = config["triggerActivities"] as? [String] { triggerActivities = val }
        if let val = config["pausesLocationUpdatesAutomatically"] as? Bool { pausesLocationUpdatesAutomatically = val }
        if let val = config["showsBackgroundLocationIndicator"] as? Bool { showsBackgroundLocationIndicator = val }
        if let val = config["url"] as? String { httpUrl = val }
        if let val = config["method"] as? String { httpMethod = val }
        if let val = config["headers"] as? [String: Any] {
            httpHeaders = val.reduce(into: [:]) { $0[$1.key] = String(describing: $1.value) }
        }
        if let val = config["params"] as? [String: Any] { httpParams = val }
        if let val = config["autoSync"] as? Bool { autoSync = val }
        if let val = config["batchSync"] as? Bool { batchSync = val }
        if let val = config["maxBatchSize"] as? NSNumber { maxBatchSize = val.intValue }
        if let val = config["autoSyncThreshold"] as? NSNumber { autoSyncThreshold = val.intValue }
        if let val = config["persistMode"] as? String { persistMode = val }
        if let val = config["httpRootProperty"] as? String { httpRootProperty = val }
        
        if let val = config["enableHeadless"] as? Bool {
            enableHeadless = val
            UserDefaults.standard.setValue(val, forKey: ConfigManager.enableHeadlessKey)
        }
        if let val = config["stopOnTerminate"] as? Bool {
            stopOnTerminate = val
            UserDefaults.standard.setValue(val, forKey: ConfigManager.stopOnTerminateKey)
        }
        if let val = config["startOnBoot"] as? Bool {
            startOnBoot = val
            UserDefaults.standard.setValue(val, forKey: ConfigManager.startOnBootKey)
        }
        
        if let val = config["bgTaskId"] as? String { bgTaskId = val }
        if let val = config["heartbeatInterval"] as? NSNumber { heartbeatInterval = val.doubleValue }
        if let val = config["stopTimeout"] as? NSNumber { stopTimeoutMinutes = val.intValue }
        if let val = config["motionTriggerDelay"] as? NSNumber { motionTriggerDelayMs = val.intValue }
        
        if let val = config["httpTimeout"] as? NSNumber { httpTimeout = val.doubleValue / 1000.0 }
        if let val = config["maxRetry"] as? NSNumber { maxRetry = val.intValue }
        if let val = config["retryDelay"] as? NSNumber { retryDelay = val.doubleValue / 1000.0 }
        if let val = config["retryDelayMultiplier"] as? NSNumber { retryDelayMultiplier = val.doubleValue }
        if let val = config["maxRetryDelay"] as? NSNumber { maxRetryDelay = val.doubleValue / 1000.0 }
        if let val = config["disableAutoSyncOnCellular"] as? Bool { disableAutoSyncOnCellular = val }
        
        if let val = config["queueMaxDays"] as? NSNumber { queueMaxDays = val.intValue }
        if let val = config["queueMaxRecords"] as? NSNumber { queueMaxRecords = val.intValue }
        if let val = config["idempotencyHeader"] as? String { idempotencyHeader = val }
        
        if let val = config["schedule"] as? [String] { schedule = val }
        
        if let val = config["logLevel"] as? String { logLevel = val }
        if let val = config["logMaxDays"] as? NSNumber { logMaxDays = val.intValue }
        
        if let val = config["maxDaysToPersist"] as? NSNumber { maxDaysToPersist = val.intValue }
        if let val = config["maxRecordsToPersist"] as? NSNumber { maxRecordsToPersist = val.intValue }
        if let val = config["maxMonitoredGeofences"] as? NSNumber { maxMonitoredGeofences = val.intValue }
    }
}
