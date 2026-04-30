package dev.locus.core

import android.content.Context
import android.content.SharedPreferences
import dev.locus.LocusPlugin
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class ConfigManager(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        /**
         * SharedPreferences key that records whether tracking is currently active.
         * Set to `true` inside [LocationTracker.startTracking] and `false` inside
         * [LocationTracker.stopTracking]. Read on cold start to reconcile the
         * in-memory `enabled` flag with on-disk reality so that [Locus.isTracking]
         * reports correctly after process relaunch.
         */
        const val KEY_TRACKING_ACTIVE = "bg_tracking_active"

        /**
         * SharedPreferences key recording why sync is currently paused. Persists across
         * process restarts so a transport-level auth failure (401/403) survives relaunch
         * and prevents retry storms on cold start. `null` means sync is active; value is
         * the HTTP status code as a string (e.g. "http_401", "http_403"). Cleared on any
         * successful 2xx response or explicit resumeSync() call.
         */
        const val KEY_SYNC_PAUSE_REASON = "bg_sync_pause_reason"
    }

    init {
        restorePersistedConfig()
    }

    // Notification settings
    var foregroundService: Boolean = true
    var notificationTitle: String = "Locus"
    var notificationText: String = "Tracking location in background."
    var notificationIcon: String = "ic_launcher"
    var notificationId: Int = 197812504
    var notificationImportance: Int = 3
    var notificationActions: MutableList<String> = mutableListOf()

    // Activity & location settings
    var activityRecognitionInterval: Long = 10000
    var locationUpdateInterval: Long = 10000
    var fastestLocationUpdateInterval: Long = 5000
    var distanceFilter: Float = 10f
    var stationaryRadius: Float = 25f
    var minActivityConfidence: Int = 0
    var stopTimeoutMinutes: Int = 0
    var motionTriggerDelay: Long = 0
    var stopDetectionDelay: Long = 0

    // HTTP settings
    var httpUrl: String? = null
    var httpMethod: String = "POST"
    var autoSync: Boolean = false
    var batchSync: Boolean = false
    var maxBatchSize: Int = 50
    var autoSyncThreshold: Int = 0
    var persistMode: String = "none"
    var httpRootProperty: String? = null
    var disableAutoSyncOnCellular: Boolean = false
    var queueMaxDays: Int = 0
    var queueMaxRecords: Int = 0
    var idempotencyHeader: String = "Idempotency-Key"
    var httpHeaders: MutableMap<String, Any> = java.util.concurrent.ConcurrentHashMap()
    var httpParams: MutableMap<String, Any> = java.util.concurrent.ConcurrentHashMap()
    var httpExtras: MutableMap<String, Any> = java.util.concurrent.ConcurrentHashMap()

    /** Alias for httpExtras to match iOS API */
    val extras: Map<String, Any> get() = httpExtras
    var httpTimeoutMs: Int = 10000
    var maxRetry: Int = 3
    var retryDelayMs: Int = 5000
    var retryDelayMultiplier: Double = 2.0
    var maxRetryDelayMs: Int = 60000

    /**
     * After all per-batch HTTP retries are exhausted for a single route
     * context the drain skips that context so other contexts in the queue
     * can still make progress. Without a cooldown the skipped context is
     * stranded until the *next* explicit `resumeSync()` or until any other
     * context produces a 2xx. For a one-task-per-shift workload (where there
     * is only one active context) this means the queue wedges for the rest
     * of the session under any sustained transient backend failure.
     *
     * These two knobs put a clock on that strand. The first time a context
     * exhausts its retries it gets [drainStrandInitialCooldownMs]; each
     * subsequent re-strand doubles, capped at [drainStrandMaxCooldownMs].
     * Any 2xx (from the same or another context) clears all strands.
     */
    var drainStrandInitialCooldownMs: Int = 30_000
    var drainStrandMaxCooldownMs: Int = 300_000

    /**
     * When `true`, [SyncManager] gzips request bodies larger than 1 KB before
     * POSTing them. The wire format is `Content-Encoding: gzip` (RFC 1952).
     * Defaults to `true`; flip to `false` to bypass compression for backends
     * that cannot decompress (a legitimate gzipped POST will then look like a
     * malformed body and the server will return 400).
     */
    var compressRequests: Boolean = true

    // -- 415 fallback (Q8 §4.2) -------------------------------------------
    //
    // Some intermediary proxies strip or double-encode `Content-Encoding:
    // gzip`, so the origin sees a body it cannot decompress and replies
    // 415 Unsupported Media Type. The fix is operator override on
    // [compressRequests], but a one-hour automatic fallback gives the
    // caller a self-healing path without paging the on-call.
    //
    // State machine extracted to a Context-free helper so it's testable
    // as plain JUnit (no Robolectric overhead). Thread-safe by design.
    private val compressionFallback = CompressionFallbackState()

    /** Disables gzip compression for [durationMs] ms from now. */
    fun disableCompressionFor(durationMs: Long) =
        compressionFallback.disableFor(durationMs)

    /** Whether the 415 fallback currently suppresses compression. */
    val isCompressionDisabledByFallback: Boolean
        get() = compressionFallback.isDisabled

    /** Test-only seam: clears the flag regardless of the deadline. */
    fun resetCompressionFallback() = compressionFallback.reset()

    // Sync policy settings
    var syncPolicyLowBatteryThreshold: Int = 20
    var syncPolicyPreferWifi: Boolean = false
    var syncPolicyRequireCharging: Boolean = false
    var syncPolicyMinBatchSize: Int = 1
    var syncPolicyMaxBatchSize: Int = 50
    var syncPolicyBatchIntervalMs: Long = 60000

    // Schedule & lifecycle settings
    var scheduleEnabled: Boolean = false
    var schedule: MutableList<String> = mutableListOf()
    var heartbeatIntervalSeconds: Int = 0
    var enableHeadless: Boolean = false
    var startOnBoot: Boolean = false
    var stopOnTerminate: Boolean = true
    var logLevel: String = "info"
    var logMaxDays: Int = 0
    var maxDaysToPersist: Int = 0
    var maxRecordsToPersist: Int = 0

    // Motion & geofence settings
    var disableMotionActivityUpdates: Boolean = false
    var disableStopDetection: Boolean = false
    var triggerActivities: MutableList<String> = mutableListOf()
    var maxMonitoredGeofences: Int = 0
    var desiredAccuracy: String = "high"
    var privacyModeEnabled: Boolean = false

    fun applyConfig(config: Map<String, Any>?) {
        if (config == null) return

        prefs.edit().putString("bg_last_config", JSONObject(config).toString()).apply()

        // Notification settings
        (config["foregroundService"] as? Boolean)?.let { foregroundService = it }

        val notification = config["notification"] as? Map<*, *>
        notificationTitle = (notification?.get("title") ?: config["notificationTitle"]) as? String ?: notificationTitle
        notificationText = (notification?.get("text") ?: config["notificationText"]) as? String ?: notificationText
        notificationIcon = (notification?.get("smallIcon") ?: config["notificationSmallIcon"]) as? String ?: notificationIcon

        (notification?.get("actions") as? List<*>)?.let { actions ->
            notificationActions.clear()
            actions.filterNotNull().forEach { notificationActions.add(it.toString()) }
        }

        // Activity & location settings
        (config["activityRecognitionInterval"] as? Number)?.let { activityRecognitionInterval = it.toLong() }
        (config["locationUpdateInterval"] as? Number)?.let { locationUpdateInterval = it.toLong() }
        (config["fastestLocationUpdateInterval"] as? Number)?.let { fastestLocationUpdateInterval = it.toLong() }
        (config["distanceFilter"] as? Number)?.let { distanceFilter = it.toFloat() }
        (config["stationaryRadius"] as? Number)?.let { stationaryRadius = it.toFloat() }
        (config["minimumActivityRecognitionConfidence"] as? Number)?.let { minActivityConfidence = it.toInt() }
        (config["disableMotionActivityUpdates"] as? Boolean)?.let { disableMotionActivityUpdates = it }
        (config["disableStopDetection"] as? Boolean)?.let { disableStopDetection = it }

        (config["triggerActivities"] as? List<*>)?.let { triggers ->
            triggerActivities = triggers.filterNotNull().map { it.toString() }.toMutableList()
        }

        // Sync settings
        (config["autoSync"] as? Boolean)?.let { autoSync = it }
        (config["batchSync"] as? Boolean)?.let { batchSync = it }
        (config["maxBatchSize"] as? Number)?.let { maxBatchSize = it.toInt() }
        (config["autoSyncThreshold"] as? Number)?.let { autoSyncThreshold = it.toInt() }
        (config["disableAutoSyncOnCellular"] as? Boolean)?.let { disableAutoSyncOnCellular = it }
        (config["queueMaxDays"] as? Number)?.let { queueMaxDays = it.toInt() }
        (config["queueMaxRecords"] as? Number)?.let { queueMaxRecords = it.toInt() }
        (config["idempotencyHeader"] as? String)?.let { idempotencyHeader = it }
        (config["persistMode"] as? String)?.let { persistMode = it }
        (config["maxDaysToPersist"] as? Number)?.let { maxDaysToPersist = it.toInt() }
        (config["maxRecordsToPersist"] as? Number)?.let { maxRecordsToPersist = it.toInt() }
        (config["maxMonitoredGeofences"] as? Number)?.let { maxMonitoredGeofences = it.toInt() }
        (config["httpRootProperty"] as? String)?.let { httpRootProperty = it }

        // HTTP settings
        (config["url"] as? String)?.let { httpUrl = it }
        (config["httpTimeout"] as? Number)?.let { httpTimeoutMs = it.toInt() }
        (config["maxRetry"] as? Number)?.let { maxRetry = it.toInt() }
        (config["retryDelay"] as? Number)?.let { retryDelayMs = it.toInt() }
        (config["retryDelayMultiplier"] as? Number)?.let { retryDelayMultiplier = it.toDouble() }
        (config["maxRetryDelay"] as? Number)?.let { maxRetryDelayMs = it.toInt() }
        (config["drainStrandInitialCooldown"] as? Number)?.let { drainStrandInitialCooldownMs = it.toInt() }
        (config["drainStrandMaxCooldown"] as? Number)?.let { drainStrandMaxCooldownMs = it.toInt() }
        (config["compressRequests"] as? Boolean)?.let { compressRequests = it }
        (config["method"] as? String)?.let { httpMethod = it }

        (config["headers"] as? Map<*, *>)?.let { httpHeaders = it.toStringKeyMap() }
        (config["params"] as? Map<*, *>)?.let { httpParams = it.toStringKeyMap() }
        (config["extras"] as? Map<*, *>)?.let { httpExtras = it.toStringKeyMap() }

        // Schedule settings
        (config["schedule"] as? List<*>)?.let { scheduleList ->
            schedule = scheduleList.filterNotNull().map { it.toString() }.toMutableList()
        }

        (config["logLevel"] as? String)?.let { logLevel = it }
        (config["logMaxDays"] as? Number)?.let { logMaxDays = it.toInt() }
        (config["enableHeadless"] as? Boolean)?.let { enableHeadless = it }
        (config["startOnBoot"] as? Boolean)?.let { startOnBoot = it }
        (config["stopOnTerminate"] as? Boolean)?.let { stopOnTerminate = it }
        (config["heartbeatInterval"] as? Number)?.let { heartbeatIntervalSeconds = it.toInt() }
        (config["stopTimeout"] as? Number)?.let { stopTimeoutMinutes = it.toInt() }
        (config["motionTriggerDelay"] as? Number)?.let { motionTriggerDelay = it.toLong() }
        (config["stopDetectionDelay"] as? Number)?.let { stopDetectionDelay = it.toLong() }
        (config["desiredAccuracy"] as? String)?.let { desiredAccuracy = it }
        
        // Privacy mode: Reset to false unless explicitly enabled in config.
        // This ensures that stale persisted privacy mode values don't block location sync.
        // Use setPrivacyMode() API to explicitly enable privacy mode if needed.
        val configPrivacyMode = config["privacyModeEnabled"] as? Boolean
        privacyModeEnabled = configPrivacyMode ?: false
        // Clear persisted privacy mode when config is applied (unless explicitly set to true)
        if (configPrivacyMode != true) {
            prefs.edit().remove("bg_privacy_mode").apply()
        }

        // Apply sync policy if present
        applySyncPolicy(config["syncPolicy"] as? Map<*, *>)

        prefs.edit()
            .putBoolean("bg_enable_headless", enableHeadless)
            .putBoolean("bg_start_on_boot", startOnBoot)
            .putBoolean("bg_stop_on_terminate", stopOnTerminate)
            .apply()
    }

    fun applySyncPolicy(policy: Map<*, *>?) {
        if (policy == null) return
        (policy["lowBatteryThreshold"] as? Number)?.let { syncPolicyLowBatteryThreshold = it.toInt() }
        (policy["preferWifi"] as? Boolean)?.let { syncPolicyPreferWifi = it }
        (policy["requireCharging"] as? Boolean)?.let { syncPolicyRequireCharging = it }
        (policy["minBatchSize"] as? Number)?.let { syncPolicyMinBatchSize = it.toInt() }
        (policy["maxBatchSize"] as? Number)?.let { syncPolicyMaxBatchSize = it.toInt() }
        (policy["batchInterval"] as? Number)?.let { syncPolicyBatchIntervalMs = it.toLong() }
    }

    fun buildConfigSnapshot(): Map<String, Any> {
        val configJson = prefs.getString("bg_last_config", null) ?: return emptyMap()
        return try {
            JSONObject(configJson).toMap()
        } catch (e: JSONException) {
            emptyMap()
        }
    }

    /**
     * Persists whether tracking is currently active. Used to reconcile the in-memory
     * `LocationTracker.enabled` flag with on-disk reality after a process restart:
     * if the process was killed while tracking was active (e.g. the user swiped the
     * app away and the OS later reaped the process), the flag stays `true` and
     * `onAttachedToEngine` re-arms tracking.
     */
    fun setTrackingActive(active: Boolean) {
        prefs.edit().putBoolean(KEY_TRACKING_ACTIVE, active).apply()
    }

    /** @see setTrackingActive */
    fun isTrackingActivePersisted(): Boolean {
        return prefs.getBoolean(KEY_TRACKING_ACTIVE, false)
    }

    /**
     * Persists the sync pause reason. Pass `null` to clear (sync active again).
     * Pass a reason string (e.g. "http_401") to mark sync as paused across restarts.
     * Only transport-level auth failures write here; user-initiated pause() does not
     * persist so "pause for now" intent doesn't leak into the next process.
     */
    fun setSyncPauseReason(reason: String?) {
        prefs.edit().apply {
            if (reason == null) remove(KEY_SYNC_PAUSE_REASON) else putString(KEY_SYNC_PAUSE_REASON, reason)
        }.apply()
    }

    /** @see setSyncPauseReason */
    fun getSyncPauseReason(): String? {
        return prefs.getString(KEY_SYNC_PAUSE_REASON, null)
    }

    private fun restorePersistedConfig() {
        val persistedConfig = buildConfigSnapshot()
        if (persistedConfig.isEmpty()) return
        applyConfig(persistedConfig)
    }

    private fun Map<*, *>.toStringKeyMap(): MutableMap<String, Any> =
        java.util.concurrent.ConcurrentHashMap<String, Any>().also { map ->
            entries.forEach { (k, v) ->
                val key = k as? String ?: return@forEach
                val value = v ?: return@forEach
                map[key] = value
            }
        }

    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        keys().forEach { key ->
            val value = get(key)
            map[key] = when (value) {
                is JSONArray -> value.toString()
                is JSONObject -> value.toMap()
                else -> value
            }
        }
        return map
    }
}
