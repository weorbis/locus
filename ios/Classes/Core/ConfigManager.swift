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
    var maxRetry = 3
    var retryDelay: TimeInterval = 5
    var retryDelayMultiplier: Double = 2.0
    var maxRetryDelay: TimeInterval = 60

    /// After all per-batch HTTP retries are exhausted for a single route
    /// context the drain skips that context so other contexts in the queue
    /// can still make progress. Without a cooldown the skipped context is
    /// stranded until the *next* explicit `resumeSync()` or until any other
    /// context produces a 2xx. For a one-task-per-shift workload (where
    /// there is only one active context) this means the queue wedges for
    /// the rest of the session under any sustained transient backend
    /// failure.
    ///
    /// These two knobs put a clock on that strand. The first time a context
    /// exhausts its retries it gets `drainStrandInitialCooldown`; each
    /// subsequent re-strand (after the previous cooldown has elapsed)
    /// doubles, capped at `drainStrandMaxCooldown`. Any 2xx (from the same
    /// or another context) clears all strands.
    var drainStrandInitialCooldown: TimeInterval = 30
    var drainStrandMaxCooldown: TimeInterval = 300

    /// When `true`, `SyncManager` gzips request bodies larger than 1 KB before
    /// POSTing. The wire format is `Content-Encoding: gzip` (RFC 1952).
    /// Defaults to `true`; flip to `false` to bypass compression for backends
    /// that cannot decompress.
    var compressRequests: Bool = true
    var disableAutoSyncOnCellular = false
    var batchSync = false
    var maxBatchSize = 50
    var autoSyncThreshold = 0
    var persistMode = "none"
    var httpRootProperty: String?
    var queueMaxDays = 0
    var queueMaxRecords = 0
    var idempotencyHeader = "Idempotency-Key"

    /// Serializes reads/writes of [dynamicHeaders] — without it, a concurrent
    /// write while a reader is iterating the dictionary crashes with
    /// `EXC_BAD_ACCESS`.
    private let dynamicHeadersQueue = DispatchQueue(label: "dev.locus.config.dynamicheaders")
    private var _dynamicHeaders: [String: String] = [:]
    var dynamicHeaders: [String: String] {
        get { dynamicHeadersQueue.sync { _dynamicHeaders } }
        set { dynamicHeadersQueue.sync { _dynamicHeaders = newValue } }
    }

    /// Atomic per-key update. `value == nil` removes the entry. Use this in
    /// preference to read-modify-write through the [dynamicHeaders]
    /// computed property when only a single header is changing — that
    /// path would race against a concurrent full-replacement.
    func updateDynamicHeader(_ key: String, value: String?) {
        dynamicHeadersQueue.sync {
            if let value = value {
                _dynamicHeaders[key] = value
            } else {
                _dynamicHeaders.removeValue(forKey: key)
            }
        }
    }

    // MARK: - 415 fallback
    //
    // Some intermediary proxies strip or double-encode `Content-Encoding:
    // gzip`, so the origin sees a body it cannot decompress and replies
    // 415. A one-hour automatic suppression gives the caller a self-healing
    // path without paging the on-call; the operator can also override
    // `compressRequests` directly.
    private let compressionFallback = CompressionFallbackState(
        loadDeadline: {
            let stored = UserDefaults.standard.double(
                forKey: ConfigManager.compressionDisabledUntilKey
            )
            return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        },
        saveDeadline: { deadline in
            if let deadline = deadline {
                UserDefaults.standard.set(
                    deadline.timeIntervalSince1970,
                    forKey: ConfigManager.compressionDisabledUntilKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: ConfigManager.compressionDisabledUntilKey
                )
            }
        }
    )

    /// Disables gzip compression for `duration` seconds from now.
    func disableCompressionFor(duration: TimeInterval) {
        compressionFallback.disableFor(duration: duration)
    }

    /// Whether the 415 fallback currently suppresses compression.
    var isCompressionDisabledByFallback: Bool {
        compressionFallback.isDisabled
    }

    /// Test-only seam: clears the fallback regardless of the deadline.
    func resetCompressionFallback() {
        compressionFallback.reset()
    }
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

    /// UserDefaults key recording whether tracking is currently active. Matches the
    /// Android `ConfigManager.KEY_TRACKING_ACTIVE` constant. Read on process cold start
    /// to re-arm tracking after the OS reaped a background process (e.g. the user
    /// swiped the app away and CoreLocation later relaunched it via Significant
    /// Location Changes).
    static let trackingActiveKey = "bg_tracking_active"

    /// UserDefaults key recording why sync is currently paused. Mirrors the Android
    /// `ConfigManager.KEY_SYNC_PAUSE_REASON` constant. Persists across process restarts
    /// so transport-level auth failures (401/403) survive relaunch and prevent retry
    /// storms on cold start. `nil` means sync is active; value is the HTTP status as a
    /// string ("http_401", "http_403"). Cleared on any 2xx or resumeSync().
    static let syncPauseReasonKey = "bg_sync_pause_reason"

    /// UserDefaults key recording the wall-clock deadline (seconds since 1970) until
    /// which the 415 fallback suppresses gzip compression. Mirrors the Android
    /// `ConfigManager.KEY_COMPRESSION_DISABLED_UNTIL_MS` constant. Persists across
    /// process restarts so the 60-min suppression window survives the frequent
    /// process kills on mobile (Doze, OOM, foreground-service restart, force-stop,
    /// reboot, iOS background-launch). `0.0` / absent means compression is allowed.
    /// Cleared on lazy expiry read or `resetCompressionFallback()`.
    static let compressionDisabledUntilKey = "bg_compression_disabled_until"

    func setSyncPauseReason(_ reason: String?) {
        if let reason = reason {
            UserDefaults.standard.set(reason, forKey: ConfigManager.syncPauseReasonKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ConfigManager.syncPauseReasonKey)
        }
    }

    func getSyncPauseReason() -> String? {
        return UserDefaults.standard.string(forKey: ConfigManager.syncPauseReasonKey)
    }

    init() {
        // Load persisted critical flags
        if let config = UserDefaults.standard.dictionary(forKey: ConfigManager.lastConfigKey) {
            apply(config)
        }
        startOnBoot = UserDefaults.standard.bool(forKey: ConfigManager.startOnBootKey)
        stopOnTerminate = UserDefaults.standard.bool(forKey: ConfigManager.stopOnTerminateKey)
        enableHeadless = UserDefaults.standard.bool(forKey: ConfigManager.enableHeadlessKey)

        // IMPORTANT: Always reset privacy mode on init.
        // Prevents stale persisted values from blocking location sync.
        // Privacy mode should only be enabled explicitly via setPrivacyMode() API or config.
        privacyModeEnabled = false
    }
    
    func apply(_ config: [String: Any]) {
        // Persist the merge of any prior bg_last_config with the incoming
        // config so omitted keys (e.g. `extras` when Locus.ready does not
        // re-stamp them) preserve the last-known-good value across cold
        // starts. Without this, an incoming config that legitimately omits
        // a field would silently erase that field from disk and the next
        // cold-start would init it to its in-memory default.
        var merged: [String: Any] =
            UserDefaults.standard.dictionary(forKey: ConfigManager.lastConfigKey) ?? [:]
        for (key, value) in config { merged[key] = value }
        UserDefaults.standard.setValue(merged, forKey: ConfigManager.lastConfigKey)
        
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
        if let val = config["drainStrandInitialCooldown"] as? NSNumber { drainStrandInitialCooldown = val.doubleValue / 1000.0 }
        if let val = config["drainStrandMaxCooldown"] as? NSNumber { drainStrandMaxCooldown = val.doubleValue / 1000.0 }
        if let val = config["compressRequests"] as? Bool { compressRequests = val }
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
