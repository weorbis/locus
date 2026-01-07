import Foundation
import CoreLocation

class ConfigManager {
    
    // Location settings
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var stationaryRadius: CLLocationDistance = 25
    var locationTimeout: TimeInterval = 30
    var pausesLocationUpdatesAutomatically = false
    var showsBackgroundLocationIndicator = false
    
    // Motion detection
    var speedJumpFilter: Double = 300 // m/s
    var elasticityMultiplier: Double = 0
    var desiredOdometerAccuracy: Double = 100
    var activityRecognitionInterval: Int = 10000 // ms
    var minimumActivityRecognitionConfidence: Int = 75
    var stopTimeoutMinutes: Int = 0
    var motionTriggerDelayMs: Int = 0
    var disableMotionActivityUpdates = false
    var disableStopDetection = false
    var triggerActivities: [String] = []
    
    // Background/foreground settings
    var foregroundService = false
    var preventSuspend = false
    var enableHeadless = false
    var stopOnTerminate = true
    var startOnBoot = false
    var bgTaskId = "dev.locus.refresh"
    var heartbeatInterval: TimeInterval = 0
    
    // HTTP sync settings
    var httpUrl: String?
    var httpMethod: String = "POST"
    var autoSync: Bool = false
    var httpHeaders: [String: String] = [:]
    var httpParams: [String: Any] = [:]
    var extras: [String: Any] = [:]
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
    var dynamicHeaders: [String: String] = [:]
    var syncOnCellular: Bool = true
    var syncInterval: Int = 0
    
    // Logging
    var logLevel = "info"
    var logMaxDays = 0
    
    // Persistence
    var maxDaysToPersist = 0
    var maxRecordsToPersist = 0
    
    // Scheduling
    var scheduleEnabled = false
    var schedule: [String] = []
    
    // Geofence settings
    var maxMonitoredGeofences = 20
    var geofenceModeHighAccuracy = false
    var geofenceInitialTriggerEntry = true
    var geofenceProximityRadius: Int = 1000
    var privacyModeEnabled = false
    
    // Constants shared across plugin
    static let startOnBootKey = "bg_start_on_boot"
    static let stopOnTerminateKey = "bg_stop_on_terminate"
    static let enableHeadlessKey = "bg_enable_headless"
    static let lastConfigKey = "bg_last_config"
    
    init() {
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
        
        // Location settings
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
        if let val = config["locationTimeout"] as? NSNumber { locationTimeout = val.doubleValue }
        if let val = config["pausesLocationUpdatesAutomatically"] as? Bool { pausesLocationUpdatesAutomatically = val }
        if let val = config["showsBackgroundLocationIndicator"] as? Bool { showsBackgroundLocationIndicator = val }
        
        // Motion detection
        if let val = config["speedJumpFilter"] as? NSNumber { speedJumpFilter = val.doubleValue }
        if let val = config["elasticityMultiplier"] as? NSNumber { elasticityMultiplier = val.doubleValue }
        if let val = config["desiredOdometerAccuracy"] as? NSNumber { desiredOdometerAccuracy = val.doubleValue }
        if let val = config["activityRecognitionInterval"] as? NSNumber { activityRecognitionInterval = val.intValue }
        if let val = config["minimumActivityRecognitionConfidence"] as? NSNumber { minimumActivityRecognitionConfidence = val.intValue }
        if let val = config["disableMotionActivityUpdates"] as? Bool { disableMotionActivityUpdates = val }
        if let val = config["disableStopDetection"] as? Bool { disableStopDetection = val }
        if let val = config["triggerActivities"] as? [String] { triggerActivities = val }
        if let val = config["stopTimeout"] as? NSNumber { stopTimeoutMinutes = val.intValue }
        if let val = config["motionTriggerDelay"] as? NSNumber { motionTriggerDelayMs = val.intValue }
        
        // Background/foreground settings
        if let val = config["foregroundService"] as? Bool { foregroundService = val }
        if let val = config["preventSuspend"] as? Bool { preventSuspend = val }
        if let val = config["bgTaskId"] as? String { bgTaskId = val }
        if let val = config["heartbeatInterval"] as? NSNumber { heartbeatInterval = val.doubleValue }
        
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
        
        // HTTP sync settings
        if let val = config["url"] as? String { httpUrl = val }
        if let val = config["method"] as? String { httpMethod = val }
        if let val = config["headers"] as? [String: Any] {
            httpHeaders = val.reduce(into: [:]) { $0[$1.key] = String(describing: $1.value) }
        }
        if let val = config["params"] as? [String: Any] { httpParams = val }
        if let val = config["extras"] as? [String: Any] { extras = val }
        if let val = config["autoSync"] as? Bool { autoSync = val }
        if let val = config["batchSync"] as? Bool { batchSync = val }
        if let val = config["maxBatchSize"] as? NSNumber { maxBatchSize = val.intValue }
        if let val = config["autoSyncThreshold"] as? NSNumber { autoSyncThreshold = val.intValue }
        if let val = config["persistMode"] as? String { persistMode = val }
        if let val = config["httpRootProperty"] as? String { httpRootProperty = val }
        if let val = config["httpTimeout"] as? NSNumber { httpTimeout = val.doubleValue / 1000.0 }
        if let val = config["maxRetry"] as? NSNumber { maxRetry = val.intValue }
        if let val = config["retryDelay"] as? NSNumber { retryDelay = val.doubleValue / 1000.0 }
        if let val = config["retryDelayMultiplier"] as? NSNumber { retryDelayMultiplier = val.doubleValue }
        if let val = config["maxRetryDelay"] as? NSNumber { maxRetryDelay = val.doubleValue / 1000.0 }
        if let val = config["disableAutoSyncOnCellular"] as? Bool { disableAutoSyncOnCellular = val }
        if let val = config["queueMaxDays"] as? NSNumber { queueMaxDays = val.intValue }
        if let val = config["queueMaxRecords"] as? NSNumber { queueMaxRecords = val.intValue }
        if let val = config["idempotencyHeader"] as? String { idempotencyHeader = val }
        
        // Scheduling
        if let val = config["schedule"] as? [String] { schedule = val; scheduleEnabled = !val.isEmpty }
        
        // Logging
        if let val = config["logLevel"] as? String { logLevel = val }
        if let val = config["logMaxDays"] as? NSNumber { logMaxDays = val.intValue }
        
        // Persistence
        if let val = config["maxDaysToPersist"] as? NSNumber { maxDaysToPersist = val.intValue }
        if let val = config["maxRecordsToPersist"] as? NSNumber { maxRecordsToPersist = val.intValue }
        if let val = config["privacyModeEnabled"] as? Bool { privacyModeEnabled = val }
        
        // Geofence settings
        if let val = config["maxMonitoredGeofences"] as? NSNumber { maxMonitoredGeofences = val.intValue }
        if let val = config["geofenceModeHighAccuracy"] as? Bool { geofenceModeHighAccuracy = val }
        if let val = config["geofenceInitialTriggerEntry"] as? Bool { geofenceInitialTriggerEntry = val }
        if let val = config["geofenceProximityRadius"] as? NSNumber { geofenceProximityRadius = val.intValue }
    }
}
