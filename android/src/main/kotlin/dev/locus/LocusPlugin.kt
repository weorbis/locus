package dev.locus

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import dev.locus.activity.MotionManager
import dev.locus.core.BackgroundTaskManager
import dev.locus.core.AutoSyncChecker
import dev.locus.core.ConfigManager
import dev.locus.core.EventDispatcher
import dev.locus.core.ForegroundServiceController
import dev.locus.core.GeofenceEventProcessor
import dev.locus.core.HeadlessDispatcher
import dev.locus.core.LocationEventProcessor
import dev.locus.core.LocationPayloadBuilder
import dev.locus.core.LocationTracker
import dev.locus.core.LocationProviderMonitor
import dev.locus.core.LogManager
import dev.locus.core.LocationUpdateProcessor
import dev.locus.core.TrackingLifecycleController
import dev.locus.core.TrackingEventEmitter
import dev.locus.core.TrackingConfigApplier
import dev.locus.core.PreferenceEventHandler
import dev.locus.core.Scheduler
import dev.locus.core.StateManager
import dev.locus.core.SyncManager
import dev.locus.core.SystemMonitor
import dev.locus.core.TrackingStats
import dev.locus.geofence.GeofenceManager
import dev.locus.location.LocationClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

@SuppressLint("LongLogTag")
class LocusPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    SharedPreferences.OnSharedPreferenceChangeListener {

    companion object {
        private const val TAG = "locus"
        private const val METHOD_CHANNEL = "locus/methods"
        private const val EVENT_CHANNEL = "locus/events"
        const val PREFS_NAME = "dev.locus.preferences"
        const val KEY_ACTIVITY_EVENT = "bg_activity_event"
        const val KEY_GEOFENCE_EVENT = "bg_geofence_event"
        const val KEY_NOTIFICATION_ACTION = "bg_notification_action"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var androidContext: Context? = null
    private var prefs: SharedPreferences? = null
    private var isListenerRegistered = false

    private var configManager: ConfigManager? = null
    private var stateManager: StateManager? = null
    private var logManager: LogManager? = null
    private var headlessDispatcher: HeadlessDispatcher? = null
    private var eventDispatcher: EventDispatcher? = null
    private var systemMonitor: SystemMonitor? = null
    private var backgroundTaskManager: BackgroundTaskManager? = null
    private var foregroundServiceController: ForegroundServiceController? = null
    private var geofenceManager: GeofenceManager? = null
    private var locationClient: LocationClient? = null
    private var motionManager: MotionManager? = null
    private var syncManager: SyncManager? = null
    private var locationTracker: LocationTracker? = null
    private var scheduler: Scheduler? = null
    private var preferenceEventHandler: PreferenceEventHandler? = null
    private var privacyModeEnabled = false
    private var trackingStats: TrackingStats? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        androidContext = binding.applicationContext
        prefs = androidContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        privacyModeEnabled = prefs?.getBoolean("bg_privacy_mode", false) ?: false

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }

        val context = androidContext ?: return
        val preferences = prefs ?: return

        val config = ConfigManager(context).also {
            it.privacyModeEnabled = privacyModeEnabled
        }
        configManager = config
        
        val state = StateManager(context)
        stateManager = state
        
        val stats = TrackingStats(context)
        trackingStats = stats
        
        val logs = LogManager(config, state.logStore)
        logManager = logs
        
        val headless = HeadlessDispatcher(context, config, preferences)
        headlessDispatcher = headless
        
        val events = EventDispatcher(headless)
        eventDispatcher = events

        systemMonitor = SystemMonitor(context, object : SystemMonitor.Listener {
            override fun onConnectivityChange(payload: Map<String, Any>) {
                emitConnectivityChange(payload)
            }

            override fun onPowerSaveChange(enabled: Boolean) {
                emitPowerSaveChange(enabled)
            }
        })

        backgroundTaskManager = BackgroundTaskManager(context)
        
        val fgController = ForegroundServiceController(context)
        foregroundServiceController = fgController

        val geofence = GeofenceManager(context) { added, removed ->
            emitGeofencesChange(added, removed)
        }
        geofenceManager = geofence
        
        val locClient = LocationClient(context, config)
        locationClient = locClient
        
        val motion = MotionManager(context, config)
        motionManager = motion

        val sync = SyncManager(
            context,
            config,
            state.locationStore,
            state.queueStore,
            object : SyncManager.SyncListener {
                override fun onHttpEvent(eventData: Map<String, Any>) {
                    events.sendEvent(eventData)
                }

                override fun onLog(level: String, message: String) {
                    logs.log(level, message)
                }

                override fun onSyncRequest() {
                    stats.onSyncRequest()
                }
            }
        )
        syncManager = sync

        val autoSyncChecker = AutoSyncChecker {
            systemMonitor?.isAutoSyncAllowed(config) ?: false
        }

        val eventProcessor = LocationEventProcessor(
            config,
            state,
            sync,
            events,
            autoSyncChecker
        )

        val providerMonitor = LocationProviderMonitor(context)
        val trackingEventEmitter = TrackingEventEmitter(events, providerMonitor)
        val payloadBuilder = LocationPayloadBuilder(motion, state)
        val locationUpdateProcessor = LocationUpdateProcessor(
            state,
            stats,
            payloadBuilder,
            eventProcessor,
            logs
        )
        val trackingLifecycleController = TrackingLifecycleController(
            config,
            locClient,
            motion,
            geofence,
            fgController,
            trackingEventEmitter,
            logs,
            stats
        )
        val trackingConfigApplier = TrackingConfigApplier(
            config,
            motion,
            geofence,
            locClient
        ) { locationTracker?.restartHeartbeat() }
        val geofenceEventProcessor = GeofenceEventProcessor(
            config,
            motion,
            geofence,
            state,
            sync,
            events,
            autoSyncChecker
        )

        val tracker = LocationTracker(
            config,
            locClient,
            motion,
            state,
            eventProcessor,
            payloadBuilder,
            locationUpdateProcessor,
            trackingLifecycleController,
            trackingConfigApplier
        )
        locationTracker = tracker

        preferenceEventHandler = PreferenceEventHandler(
            config,
            motion,
            geofenceEventProcessor,
            events
        )

        scheduler = Scheduler(config) { shouldBeEnabled ->
            val tracker = locationTracker ?: return@Scheduler shouldBeEnabled
            when {
                shouldBeEnabled && !tracker.isEnabled() -> {
                    tracker.startTracking()
                    tracker.emitScheduleEvent()
                    true
                }
                !shouldBeEnabled && tracker.isEnabled() -> {
                    tracker.stopTracking()
                    false
                }
                else -> shouldBeEnabled
            }
        }

        applyStoredConfig()
        systemMonitor?.registerConnectivity()
        systemMonitor?.registerPowerSave()

        if (prefs != null && !isListenerRegistered) {
            prefs?.registerOnSharedPreferenceChangeListener(this)
            isListenerRegistered = true
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        configManager?.let { config ->
            if (config.stopOnTerminate) {
                locationTracker?.stopTracking()
            }
        }
        motionManager?.stop()
        locationTracker?.release()
        systemMonitor?.unregisterConnectivity()
        systemMonitor?.unregisterPowerSave()
        scheduler?.stop()
        backgroundTaskManager?.release()
        syncManager?.release()
        
        // Close database helpers
        stateManager?.locationStore?.close()
        stateManager?.queueStore?.close()

        if (prefs != null && isListenerRegistered) {
            prefs?.unregisterOnSharedPreferenceChangeListener(this)
            isListenerRegistered = false
        }

        eventDispatcher?.setEventSink(null)
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventDispatcher?.setEventSink(events)
        systemMonitor?.readConnectivityEvent()?.let { emitConnectivityChange(it) }
        systemMonitor?.readPowerSaveState()?.let { emitPowerSaveChange(it) }
    }

    override fun onCancel(arguments: Any?) {
        eventDispatcher?.setEventSink(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        // No-op
    }

    override fun onDetachedFromActivityForConfigChanges() {
        if (prefs != null && isListenerRegistered) {
            prefs?.unregisterOnSharedPreferenceChangeListener(this)
            isListenerRegistered = false
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        if (prefs != null && !isListenerRegistered) {
            prefs?.registerOnSharedPreferenceChangeListener(this)
            isListenerRegistered = true
        }
    }

    override fun onDetachedFromActivity() {
        // No-op
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                locationTracker?.applyConfig(call.arguments.asMap())
                result.success(locationTracker?.buildState())
            }
            "start" -> {
                locationTracker?.startTracking()
                result.success(locationTracker?.buildState())
            }
            "stop" -> {
                locationTracker?.stopTracking()
                result.success(locationTracker?.buildState())
            }
            "getState" -> {
                result.success(locationTracker?.buildState())
            }
            "getCurrentPosition" -> {
                getCurrentPosition(result)
            }
            "setConfig" -> {
                locationTracker?.applyConfig(call.arguments.asMap())
                result.success(true)
            }
            "reset" -> {
                locationTracker?.applyConfig(call.arguments.asMap())
                result.success(true)
            }
            "setOdometer" -> {
                (call.arguments as? Number)?.let { num ->
                    val value = num.toDouble()
                    stateManager?.odometerValue = value
                    result.success(value)
                } ?: result.error("INVALID_ARGUMENT", "Expected numeric odometer value", null)
            }
            "changePace" -> {
                (call.arguments as? Boolean)?.let { moving ->
                    locationTracker?.changePace(moving)
                }
                result.success(true)
            }
            "addGeofence" -> {
                call.arguments.asMap()?.let { geofenceManager?.addGeofence(it, result) }
                    ?: result.error("INVALID_ARGUMENT", "Expected map argument", null)
            }
            "addGeofences" -> {
                geofenceManager?.addGeofences(call.arguments.asList(), result)
            }
            "removeGeofence" -> {
                geofenceManager?.removeGeofence(call.arguments, result)
            }
            "removeGeofences" -> {
                geofenceManager?.removeGeofences(result)
            }
            "getGeofence" -> {
                geofenceManager?.getGeofence(call.arguments, result)
            }
            "getGeofences" -> {
                geofenceManager?.getGeofences(result)
            }
            "geofenceExists" -> {
                geofenceManager?.geofenceExists(call.arguments, result)
            }
            "destroyLocations" -> {
                stateManager?.clearLocations()
                result.success(true)
            }
            "getLocations" -> {
                val args = call.arguments.asMap()
                val limit = (args?.get("limit") as? Number)?.toInt() ?: 0
                result.success(stateManager?.getStoredLocations(limit))
            }
            "enqueue" -> {
                val enqueueArgs = call.arguments.asMap()
                if (enqueueArgs == null) {
                    result.error("INVALID_ARGUMENT", "Expected payload map", null)
                    return
                }
                val payloadObj = enqueueArgs["payload"]
                if (payloadObj !is Map<*, *>) {
                    result.error("INVALID_ARGUMENT", "Missing payload map", null)
                    return
                }
                val type = enqueueArgs["type"] as? String ?: "location"
                val idempotencyKey = (enqueueArgs["idempotencyKey"] as? String)
                    ?: UUID.randomUUID().toString()
                val config = configManager
                @Suppress("UNCHECKED_CAST")
                val payload = payloadObj as Map<String, Any>
                val id = stateManager?.enqueue(
                    payload,
                    type,
                    idempotencyKey,
                    config?.queueMaxDays ?: 7,
                    config?.queueMaxRecords ?: 500
                )
                result.success(id)
            }
            "getQueue" -> {
                val queueArgs = call.arguments.asMap()
                val queueLimit = (queueArgs?.get("limit") as? Number)?.toInt() ?: 0
                result.success(stateManager?.getQueue(queueLimit))
            }
            "setPrivacyMode" -> {
                (call.arguments as? Boolean)?.let { enabled ->
                    privacyModeEnabled = enabled
                    configManager?.privacyModeEnabled = enabled
                    prefs?.edit()?.putBoolean("bg_privacy_mode", enabled)?.apply()
                }
                result.success(true)
            }
            "clearQueue" -> {
                stateManager?.clearQueue()
                result.success(true)
            }
            "syncQueue" -> {
                val syncArgs = call.arguments.asMap()
                val syncLimit = (syncArgs?.get("limit") as? Number)?.toInt() ?: 0
                result.success(syncManager?.syncQueue(syncLimit))
            }
            "storeTripState" -> {
                val tripState = call.arguments.asMap()
                if (tripState == null) {
                    result.error("INVALID_ARGUMENT", "Expected trip state map", null)
                    return
                }
                stateManager?.storeTripState(tripState)
                result.success(true)
            }
            "readTripState" -> {
                result.success(stateManager?.readTripState())
            }
            "clearTripState" -> {
                stateManager?.clearTripState()
                result.success(true)
            }
            "getConfig" -> {
                result.success(buildConfigSnapshot())
            }
            "getDiagnosticsMetadata" -> {
                result.success(buildDiagnosticsMetadata())
            }
            "registerHeadlessTask" -> {
                when (val args = call.arguments) {
                    is Map<*, *> -> {
                        val map = args.asMap()
                        val dispatcher = map?.get("dispatcher") as? Number
                        val callback = map?.get("callback") as? Number
                        if (dispatcher != null && callback != null) {
                            prefs?.edit()
                                ?.putLong("bg_headless_dispatcher", dispatcher.toLong())
                                ?.putLong("bg_headless_callback", callback.toLong())
                                ?.apply()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
                        }
                    }
                    is Number -> {
                        prefs?.edit()?.putLong("bg_headless_callback", args.toLong())?.apply()
                        result.success(true)
                    }
                    else -> {
                        result.error("INVALID_ARGUMENT", "Expected headless callback handle", null)
                    }
                }
            }
            "startGeofences" -> {
                geofenceManager?.startGeofences(result)
            }
            "startSchedule" -> {
                configManager?.scheduleEnabled = true
                locationTracker?.emitScheduleEvent()
                scheduler?.start()
                scheduler?.applyScheduleState()
                result.success(true)
            }
            "stopSchedule" -> {
                configManager?.scheduleEnabled = false
                scheduler?.stop()
                result.success(true)
            }
            "sync" -> {
                syncManager?.resumeSync()
                locationTracker?.syncNow()
                result.success(true)
            }
            "resumeSync" -> {
                syncManager?.resumeSync()
                result.success(true)
            }
            "startBackgroundTask" -> {
                result.success(backgroundTaskManager?.start())
            }
            "stopBackgroundTask" -> {
                (call.arguments as? Number)?.let { num ->
                    backgroundTaskManager?.stop(num.toInt())
                }
                result.success(true)
            }
            "getLog" -> {
                result.success(stateManager?.readLogEntries(0))
            }
            "getBatteryStats" -> {
                result.success(buildBatteryStats())
            }
            "getPowerState" -> {
                result.success(buildPowerState())
            }
            "getNetworkType" -> {
                result.success(getNetworkType())
            }
            "isMeteredConnection" -> {
                result.success(isMeteredConnection())
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }
            "setSyncPolicy" -> {
                setSyncPolicy(call.arguments.asMap())
                result.success(true)
            }
            "isInActiveGeofence" -> {
                result.success(isInActiveGeofence())
            }
            "setSpoofDetection",
            "startSignificantChangeMonitoring",
            "stopSignificantChangeMonitoring" -> {
                // Handled on Dart side, just acknowledge
                result.success(true)
            }
            "setDynamicHeaders" -> {
                val headers = call.arguments.asMap()
                if (headers != null) {
                    configManager?.httpHeaders?.clear()
                    configManager?.httpHeaders?.putAll(headers)
                }
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        if (sharedPreferences != null && key != null) {
            preferenceEventHandler?.handlePreferenceChange(sharedPreferences, key)
        }
    }

    private fun getCurrentPosition(result: MethodChannel.Result) {
        val client = locationClient ?: run {
            result.error("NOT_INITIALIZED", "Location client not initialized", null)
            return
        }

        if (!client.hasPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        client.getCurrentPosition(object : LocationClient.LocationResultCallback {
            override fun onSuccess(location: Location) {
                val payload = locationTracker?.buildLocationPayload(location, "location")
                result.success(payload)
            }

            override fun onError(code: String, message: String) {
                result.error(code, message, null)
            }
        })
    }

    private fun emitConnectivityChange(payload: Map<String, Any>) {
        val event = mapOf(
            "type" to "connectivitychange",
            "data" to payload
        )
        eventDispatcher?.sendEvent(event)
    }

    private fun emitPowerSaveChange(enabled: Boolean) {
        val event = mapOf(
            "type" to "powersavechange",
            "data" to enabled
        )
        eventDispatcher?.sendEvent(event)
    }

    private fun emitGeofencesChange(added: List<String>, removed: List<String>) {
        val payload = mapOf(
            "on" to added,
            "off" to removed
        )
        val event = mapOf(
            "type" to "geofenceschange",
            "data" to payload
        )
        eventDispatcher?.sendEvent(event)
    }

    private fun applyStoredConfig() {
        val configJson = prefs?.getString("bg_last_config", null) ?: return
        try {
            val json = JSONObject(configJson)
            locationTracker?.applyConfig(json.toMap())
        } catch (e: JSONException) {
            Log.e(TAG, "Failed to restore config - clearing corrupted data: ${e.message}")

            // Clear the corrupted config to prevent repeated failures
            prefs?.edit()?.remove("bg_last_config")?.apply()

            // Emit error event to Dart layer for visibility
            val errorData = mapOf(
                "type" to "configError",
                "message" to "Failed to restore stored config: ${e.message}",
                "action" to "cleared"
            )
            val event = mapOf(
                "type" to "error",
                "data" to errorData
            )
            eventDispatcher?.sendEvent(event)
        }
    }

    private fun buildConfigSnapshot(): Map<String, Any> {
        val configJson = prefs?.getString("bg_last_config", null) ?: return emptyMap()
        return try {
            JSONObject(configJson).toMap()
        } catch (e: JSONException) {
            emptyMap()
        }
    }

    private fun buildDiagnosticsMetadata(): Map<String, Any> {
        return mapOf(
            "platform" to "android",
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "powerSaveMode" to (systemMonitor?.readPowerSaveState() ?: false),
            "hasLocationPermission" to hasLocationPermission(),
            "hasActivityPermission" to hasActivityPermission(),
            "hasBackgroundLocationPermission" to hasBackgroundLocationPermission()
        )
    }

    private fun hasLocationPermission(): Boolean {
        val context = androidContext ?: return false
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun hasActivityPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true
        }
        val context = androidContext ?: return false
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBackgroundLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true
        }
        val context = androidContext ?: return false
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val context = androidContext ?: return false
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun buildBatteryStats(): Map<String, Any> {
        val context = androidContext ?: return emptyMap()
        val batteryStatus = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )

        var batteryLevel = -1
        var isCharging = false

        batteryStatus?.let { status ->
            val level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            batteryLevel = if (level >= 0 && scale > 0) {
                ((level / scale.toDouble()) * 100.0).toInt()
            } else {
                50
            }
            isCharging = status.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ==
                    BatteryManager.BATTERY_STATUS_CHARGING
        }

        return trackingStats?.buildStats(batteryLevel, isCharging) ?: emptyMap()
    }

    private fun buildPowerState(): Map<String, Any> {
        val context = androidContext ?: return emptyMap()
        val batteryStatus = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )

        val state = mutableMapOf<String, Any>()

        batteryStatus?.let { status ->
            val level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val batteryLevel = if (level >= 0 && scale > 0) {
                ((level / scale.toDouble()) * 100.0).toInt()
            } else {
                -1
            }
            state["batteryLevel"] = batteryLevel
            val statusValue = status.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            state["isCharging"] = statusValue == BatteryManager.BATTERY_STATUS_CHARGING ||
                    statusValue == BatteryManager.BATTERY_STATUS_FULL
        } ?: run {
            state["batteryLevel"] = 50
            state["isCharging"] = false
        }

        state["isPowerSaveMode"] = systemMonitor?.readPowerSaveState() ?: false
        return state
    }

    private fun getNetworkType(): String {
        val context = androidContext ?: return "none"
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "none"
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "none"

        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
            else -> "unknown"
        }
    }

    private fun isMeteredConnection(): Boolean {
        val context = androidContext ?: return false
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        return cm.isActiveNetworkMetered
    }

    private fun setSyncPolicy(policyMap: Map<String, Any>?) {
        policyMap ?: return
        prefs?.edit()?.putString("bg_sync_policy", JSONObject(policyMap).toString())?.apply()
        // Apply policy to ConfigManager so SyncManager respects it immediately
        configManager?.applySyncPolicy(policyMap)
    }

    private fun isInActiveGeofence(): Boolean {
        val location = locationTracker?.getLastLocation() ?: return false
        val geofences = geofenceManager?.getGeofencesSync() ?: return false

        for (geofence in geofences) {
            val latitude = geofence["latitude"].toDoubleOrNull()
            val longitude = geofence["longitude"].toDoubleOrNull()
            val radius = geofence["radius"].toDoubleOrNull()

            if (latitude == null || longitude == null || radius == null) {
                continue
            }

            val results = FloatArray(1)
            Location.distanceBetween(
                location.latitude,
                location.longitude,
                latitude,
                longitude,
                results
            )
            if (results[0] <= radius) {
                return true
            }
        }
        return false
    }

    private fun Any?.toDoubleOrNull(): Double? {
        return when (this) {
            is Number -> this.toDouble()
            is String -> this.toDoubleOrNull()
            else -> null
        }
    }

    // Extension functions for type conversion
    @Suppress("UNCHECKED_CAST")
    private fun Any?.asMap(): Map<String, Any>? {
        return this as? Map<String, Any>
    }

    @Suppress("UNCHECKED_CAST")
    private fun Any?.asNonNullMap(): Map<String, Any>? {
        return this as? Map<String, Any>
    }

    @Suppress("UNCHECKED_CAST")
    private fun Any?.asList(): List<Any> {
        return (this as? List<Any>) ?: emptyList()
    }

    @Throws(JSONException::class)
    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val names = this.names() ?: return map
        for (i in 0 until names.length()) {
            val key = names.optString(i)
            when (val value = this.opt(key)) {
                is JSONObject -> map[key] = value.toMap()
                is JSONArray -> map[key] = value.toList()
                JSONObject.NULL -> { /* skip null values or map[key] = null */ }
                else -> value?.let { map[key] = it }
            }
        }
        return map
    }

    @Throws(JSONException::class)
    private fun JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until this.length()) {
            when (val value = this.opt(i)) {
                is JSONObject -> list.add(value.toMap())
                is JSONArray -> list.add(value.toList())
                JSONObject.NULL -> { /* skip null values */ }
                else -> value?.let { list.add(it) }
            }
        }
        return list
    }
}
