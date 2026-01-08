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
    @Volatile var httpHeaders: MutableMap<String, Any> = mutableMapOf()
    @Volatile var httpParams: MutableMap<String, Any> = mutableMapOf()
    @Volatile var httpExtras: MutableMap<String, Any> = mutableMapOf()

    /** Alias for httpExtras to match iOS API */
    val extras: Map<String, Any> get() = httpExtras
    var httpTimeoutMs: Int = 10000
    var maxRetry: Int = 0
    var retryDelayMs: Int = 5000
    var retryDelayMultiplier: Double = 2.0
    var maxRetryDelayMs: Int = 60000

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
        (config["method"] as? String)?.let { httpMethod = it }

        (config["headers"] as? Map<*, *>)?.let { httpHeaders = it.toStringKeyMap() }
        (config["params"] as? Map<*, *>)?.let { httpParams = it.toStringKeyMap() }
        (config["extras"] as? Map<*, *>)?.let { httpExtras = it.toStringKeyMap() }

        // Schedule settings
        (config["schedule"] as? List<*>)?.let { scheduleList ->
            schedule = scheduleList.filterNotNull().map { it.toString() }.toMutableList()
        }

        // Lifecycle settings
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
        (config["privacyModeEnabled"] as? Boolean)?.let { privacyModeEnabled = it }

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

    private fun Map<*, *>.toStringKeyMap(): MutableMap<String, Any> =
        entries.mapNotNull { (k, v) ->
            (k as? String)?.let { key -> v?.let { value -> key to value } }
        }.toMap().toMutableMap()

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
