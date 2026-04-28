package dev.locus.core

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import dev.locus.LocusPlugin
import dev.locus.activity.MotionManager
import dev.locus.geofence.GeofenceManager
import dev.locus.location.LocationClient
import dev.locus.service.ForegroundService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

/**
 * Process-lifetime holder for every long-lived native resource Locus owns:
 * configuration, storage, location + activity subscriptions, geofencing,
 * sync, foreground service control, scheduler, headless dispatchers.
 *
 * All state that must survive the Flutter UI engine being destroyed (swipe-
 * away, task removal) lives here. [LocusPlugin] is a thin per-engine adapter
 * that routes MethodChannel calls to this container and forwards native events
 * back to Dart via an optional [DartBridge].
 *
 * ### Why this is separate from LocusPlugin
 *
 * Flutter plugins are engine-scoped: a new `FlutterEngine` creates a new
 * plugin instance, and engine destruction destroys it. Native resources that
 * must outlive engine destruction cannot live in the plugin. Previously we
 * tried to solve this with a soft-detach + takeover dance on the plugin
 * itself, which was fragile (HeadlessService's background isolate would
 * spuriously take over, listener closures had to be rebuilt, etc.). With the
 * container, a new plugin simply calls [acquire] and gets the same instance
 * that a soft-detached predecessor left behind.
 *
 * ### Teardown
 *
 * The container has no [release] method. It lives for the OS process. On
 * process death, the OS reclaims all native resources. Tracking state is
 * persisted through `ConfigManager.setTrackingActive(...)`, so on cold
 * restart, [reconcilePersistedTrackingState] re-arms tracking if needed.
 */
internal class LocusContainer private constructor(private val context: Context) {

    /**
     * Optional bridge back to a live FlutterEngine's Dart side. Set by a
     * [LocusPlugin] when Dart subscribes to the event channel; cleared on
     * engine detach. When null, events fall back to [HeadlessDispatcher] and
     * method-channel invocations fall back to the headless dispatchers (if
     * their callbacks are registered).
     */
    interface DartBridge {
        fun invokeBuildSyncBody(
            locations: List<Map<String, Any>>,
            extras: Map<String, Any>,
            callback: (JSONObject?) -> Unit,
        )

        fun invokeValidatePreSync(
            locations: List<Map<String, Any>>,
            extras: Map<String, Any>,
            callback: (Boolean) -> Unit,
        )

        fun invokeRefreshHeaders(callback: (Map<String, String>?) -> Unit)
    }

    @Volatile
    private var bridge: DartBridge? = null

    /**
     * Install a bridge to the active UI engine. Last-writer-wins; safe to
     * call from the main thread only. Passing `null` detaches the bridge so
     * subsequent events route to headless dispatchers.
     */
    fun setBridge(b: DartBridge?) {
        bridge = b
    }

    // Process-lifetime managers. Each is initialized exactly once in `init`.
    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())

    val configManager: ConfigManager
    val stateManager: StateManager
    val trackingStats: TrackingStats
    val logManager: LogManager
    val headlessDispatcher: HeadlessDispatcher
    val headlessHeadersDispatcher: HeadlessHeadersDispatcher
    val headlessValidationDispatcher: HeadlessValidationDispatcher
    val eventDispatcher: EventDispatcher
    val systemMonitor: SystemMonitor
    val backgroundTaskManager: BackgroundTaskManager
    val foregroundServiceController: ForegroundServiceController
    val geofenceManager: GeofenceManager
    val locationClient: LocationClient
    val motionManager: MotionManager
    val syncManager: SyncManager
    val locationTracker: LocationTracker
    val scheduler: Scheduler
    val preferenceEventHandler: PreferenceEventHandler

    init {
        // Privacy mode: always start disabled on fresh container construction.
        // Stale persisted values could otherwise block location sync before
        // Locus.ready() is called.
        prefs.edit().remove("bg_privacy_mode").apply()

        configManager = ConfigManager(context).also { it.privacyModeEnabled = false }
        Log.d(TAG, "LocusContainer initialized - privacyModeEnabled=false")

        stateManager = StateManager(context)
        trackingStats = TrackingStats(context)
        logManager = LogManager(configManager, stateManager.logStore)

        headlessDispatcher = HeadlessDispatcher(context, configManager, prefs)
        headlessHeadersDispatcher = HeadlessHeadersDispatcher(context, configManager, prefs)
        headlessValidationDispatcher = HeadlessValidationDispatcher(context, configManager, prefs)

        eventDispatcher = EventDispatcher(headlessDispatcher)

        systemMonitor = SystemMonitor(context, object : SystemMonitor.Listener {
            override fun onConnectivityChange(payload: Map<String, Any>) {
                emitEvent("connectivitychange", payload)
            }

            override fun onPowerSaveChange(enabled: Boolean) {
                emitEvent("powersavechange", enabled)
            }
        })

        backgroundTaskManager = BackgroundTaskManager(context)
        foregroundServiceController = ForegroundServiceController(context)

        geofenceManager = GeofenceManager(context) { added, removed ->
            emitEvent("geofenceschange", mapOf("on" to added, "off" to removed))
        }

        locationClient = LocationClient(context, configManager)
        motionManager = MotionManager(context, configManager)

        syncManager = SyncManager(
            context,
            configManager,
            stateManager.locationStore,
            stateManager.queueStore,
            object : SyncManager.SyncListener {
                override fun onHttpEvent(eventData: Map<String, Any>) {
                    eventDispatcher.sendEvent(eventData)
                }

                override fun onLog(level: String, message: String) {
                    logManager.log(level, message)
                }

                override fun onSyncRequest() {
                    trackingStats.onSyncRequest()
                }

                override fun buildSyncBody(
                    locations: List<Map<String, Any>>,
                    extras: Map<String, Any>,
                    callback: (JSONObject?) -> Unit,
                ) {
                    val b = bridge
                    if (b == null) {
                        callback(null)
                    } else {
                        b.invokeBuildSyncBody(locations, extras, callback)
                    }
                }

                override fun onPreSyncValidation(
                    locations: List<Map<String, Any>>,
                    extras: Map<String, Any>,
                    callback: (Boolean) -> Unit,
                ) {
                    val b = bridge
                    if (b != null) {
                        b.invokeValidatePreSync(locations, extras, callback)
                        return
                    }
                    // Bridge not attached (UI engine gone). Fall back to
                    // headless validation if registered; otherwise proceed
                    // rather than stalling sync indefinitely.
                    if (headlessValidationDispatcher.isAvailable()) {
                        Log.d(TAG, "Using headless validation for pre-sync check")
                        headlessValidationDispatcher.validate(locations, extras, callback)
                    } else {
                        callback(true)
                    }
                }

                override fun onHeadersRefresh(callback: (Map<String, String>?) -> Unit) {
                    val b = bridge
                    if (b != null) {
                        b.invokeRefreshHeaders(callback)
                        return
                    }
                    if (headlessHeadersDispatcher.isAvailable()) {
                        headlessHeadersDispatcher.refreshHeaders(callback)
                    } else {
                        callback(null)
                    }
                }
            },
        )

        val autoSyncChecker = AutoSyncChecker {
            systemMonitor.isAutoSyncAllowed(configManager)
        }

        val locationEventProcessor = LocationEventProcessor(
            configManager,
            stateManager,
            syncManager,
            eventDispatcher,
            autoSyncChecker,
        )

        val providerMonitor = LocationProviderMonitor(context)
        val trackingEventEmitter = TrackingEventEmitter(eventDispatcher, providerMonitor)
        val payloadBuilder = LocationPayloadBuilder(configManager, motionManager, stateManager)
        val locationUpdateProcessor = LocationUpdateProcessor(
            stateManager,
            trackingStats,
            payloadBuilder,
            locationEventProcessor,
            logManager,
        )
        val trackingLifecycleController = TrackingLifecycleController(
            configManager,
            locationClient,
            motionManager,
            geofenceManager,
            foregroundServiceController,
            trackingEventEmitter,
            logManager,
            trackingStats,
        )
        val trackingConfigApplier = TrackingConfigApplier(
            configManager,
            motionManager,
            geofenceManager,
            locationClient,
        ) { locationTracker.restartHeartbeat() }
        val geofenceEventProcessor = GeofenceEventProcessor(
            configManager,
            motionManager,
            geofenceManager,
            stateManager,
            syncManager,
            eventDispatcher,
            autoSyncChecker,
        )

        locationTracker = LocationTracker(
            configManager,
            locationClient,
            motionManager,
            stateManager,
            locationEventProcessor,
            payloadBuilder,
            locationUpdateProcessor,
            trackingLifecycleController,
            trackingConfigApplier,
        )

        preferenceEventHandler = PreferenceEventHandler(
            configManager,
            motionManager,
            geofenceEventProcessor,
            eventDispatcher,
        )

        scheduler = Scheduler(configManager) { shouldBeEnabled ->
            when {
                shouldBeEnabled && !locationTracker.isEnabled() -> {
                    locationTracker.startTracking()
                    locationTracker.emitScheduleEvent()
                    true
                }
                !shouldBeEnabled && locationTracker.isEnabled() -> {
                    locationTracker.stopTracking()
                    false
                }
                else -> shouldBeEnabled
            }
        }

        applyStoredConfig()
        systemMonitor.registerConnectivity()
        systemMonitor.registerPowerSave()

        // Cold-start reconciliation: if tracking was active before the process
        // died, re-arm now. No-op on first install or after an explicit stop.
        reconcilePersistedTrackingState()
    }

    // -------------------------------------------------------------------------
    //  Method-channel handling
    // -------------------------------------------------------------------------

    /**
     * Handle a method call from any engine. Thread-safety: call on the main
     * thread (matches MethodChannel dispatch convention).
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                val missing = validateManifestPermissions()
                if (missing.isNotEmpty()) {
                    Log.w(TAG, "Missing manifest permissions: $missing")
                    emitPermissionError(
                        "ERR_MISSING_MANIFEST",
                        "Required permissions not declared in AndroidManifest.xml: ${missing.joinToString(", ")}",
                        mapOf("permissions" to missing),
                    )
                }
                locationTracker.applyConfig(call.arguments.asMap())
                result.success(locationTracker.buildState())
            }
            "start" -> {
                locationTracker.startTracking()
                result.success(locationTracker.buildState())
            }
            "stop" -> {
                locationTracker.stopTracking()
                result.success(locationTracker.buildState())
            }
            "getState" -> result.success(locationTracker.buildState())
            "updateNotification" -> {
                if (!locationTracker.isEnabled()) {
                    result.success(false)
                    return
                }
                val args = call.arguments.asMap()
                result.success(
                    ForegroundService.updateNotification(
                        context,
                        args?.get("title") as? String,
                        args?.get("text") as? String,
                    ),
                )
            }
            "getCurrentPosition" -> getCurrentPosition(result)
            "hasPreciseLocationPermission" -> {
                val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            "setConfig", "reset" -> {
                locationTracker.applyConfig(call.arguments.asMap())
                result.success(true)
            }
            "setOdometer" -> {
                (call.arguments as? Number)?.let { num ->
                    val v = num.toDouble()
                    stateManager.odometerValue = v
                    result.success(v)
                } ?: result.error("INVALID_ARGUMENT", "Expected numeric odometer value", null)
            }
            "changePace" -> {
                (call.arguments as? Boolean)?.let { locationTracker.changePace(it) }
                result.success(true)
            }
            "addGeofence" -> call.arguments.asMap()
                ?.let { geofenceManager.addGeofence(it, result) }
                ?: result.error("INVALID_ARGUMENT", "Expected map argument", null)
            "addGeofences" -> geofenceManager.addGeofences(call.arguments.asList(), result)
            "removeGeofence" -> geofenceManager.removeGeofence(call.arguments, result)
            "removeGeofences" -> geofenceManager.removeGeofences(result)
            "getGeofence" -> geofenceManager.getGeofence(call.arguments, result)
            "getGeofences" -> geofenceManager.getGeofences(result)
            "geofenceExists" -> geofenceManager.geofenceExists(call.arguments, result)
            "destroyLocations" -> {
                stateManager.clearLocations()
                result.success(true)
            }
            "getLocations" -> {
                val limit = (call.arguments.asMap()?.get("limit") as? Number)?.toInt() ?: 0
                result.success(stateManager.getStoredLocations(limit))
            }
            "enqueue" -> handleEnqueue(call, result)
            "getQueue" -> {
                val limit = (call.arguments.asMap()?.get("limit") as? Number)?.toInt() ?: 0
                result.success(stateManager.getQueue(limit))
            }
            "setPrivacyMode" -> {
                (call.arguments as? Boolean)?.let { enabled ->
                    configManager.privacyModeEnabled = enabled
                    prefs.edit().putBoolean("bg_privacy_mode", enabled).apply()
                }
                result.success(true)
            }
            "clearQueue" -> {
                stateManager.clearQueue()
                result.success(true)
            }
            "syncQueue" -> {
                val limit = (call.arguments.asMap()?.get("limit") as? Number)?.toInt() ?: 0
                result.success(syncManager.syncQueue(limit))
            }
            "storeTripState" -> {
                val tripState = call.arguments.asMap()
                if (tripState == null) {
                    result.error("INVALID_ARGUMENT", "Expected trip state map", null)
                } else {
                    stateManager.storeTripState(tripState)
                    result.success(true)
                }
            }
            "readTripState" -> result.success(stateManager.readTripState())
            "clearTripState" -> {
                stateManager.clearTripState()
                result.success(true)
            }
            "getConfig" -> result.success(buildConfigSnapshot())
            "getDiagnosticsMetadata" -> result.success(buildDiagnosticsMetadata())
            "registerHeadlessTask" -> handleRegisterHeadlessTask(call, result)
            "startGeofences" -> geofenceManager.startGeofences(result)
            "startSchedule" -> {
                configManager.scheduleEnabled = true
                locationTracker.emitScheduleEvent()
                scheduler.start()
                scheduler.applyScheduleState()
                result.success(true)
            }
            "stopSchedule" -> {
                configManager.scheduleEnabled = false
                scheduler.stop()
                result.success(true)
            }
            "sync" -> {
                syncManager.resumeSync()
                locationTracker.syncNow()
                result.success(true)
            }
            "pauseSync" -> {
                syncManager.pause()
                result.success(true)
            }
            "resumeSync" -> {
                syncManager.resumeSync()
                result.success(true)
            }
            "startBackgroundTask" -> result.success(backgroundTaskManager.start())
            "stopBackgroundTask" -> {
                (call.arguments as? Number)?.let { backgroundTaskManager.stop(it.toInt()) }
                result.success(true)
            }
            "getLog" -> result.success(stateManager.readLogEntries(0))
            "getBatteryStats" -> result.success(buildBatteryStats())
            "getPowerState" -> result.success(buildPowerState())
            "getNetworkType" -> result.success(getNetworkType())
            "isMeteredConnection" -> result.success(isMeteredConnection())
            "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
            "setSyncPolicy" -> {
                setSyncPolicy(call.arguments.asMap())
                result.success(true)
            }
            "isInActiveGeofence" -> result.success(isInActiveGeofence())
            "setSpoofDetection",
            "startSignificantChangeMonitoring",
            "stopSignificantChangeMonitoring" -> result.success(true) // Handled on Dart side
            "setDynamicHeaders" -> {
                call.arguments.asMap()?.let { headers ->
                    configManager.httpHeaders.clear()
                    configManager.httpHeaders.putAll(headers)
                }
                result.success(true)
            }
            "setSyncBodyBuilderEnabled" -> {
                syncManager.syncBodyBuilderEnabled = call.arguments as? Boolean ?: false
                result.success(true)
            }
            "registerHeadlessSyncBodyBuilder" -> handleRegisterCallbackPair(
                call,
                result,
                dispatcherKey = "bg_headless_sync_body_dispatcher",
                callbackKey = "bg_headless_sync_body_callback",
            )
            "registerHeadlessValidationCallback" -> handleRegisterCallbackPair(
                call,
                result,
                dispatcherKey = HeadlessValidationDispatcher.KEY_VALIDATION_DISPATCHER,
                callbackKey = HeadlessValidationDispatcher.KEY_VALIDATION_CALLBACK,
            )
            "registerHeadlessHeadersCallback" -> handleRegisterCallbackPair(
                call,
                result,
                dispatcherKey = HeadlessHeadersDispatcher.KEY_HEADERS_DISPATCHER,
                callbackKey = HeadlessHeadersDispatcher.KEY_HEADERS_CALLBACK,
            )
            "getLocationSyncBacklog" -> result.success(
                syncManager.getLocationSyncBacklog() ?: emptyMap<String, Any?>(),
            )
            "getSyncPauseState" -> result.success(syncManager.getSyncPauseState())
            else -> result.notImplemented()
        }
    }

    /** Handle a SharedPreferences change (routed from the adapter). */
    fun handlePreferenceChange(prefs: SharedPreferences, key: String?) {
        if (key == null) return
        preferenceEventHandler.handlePreferenceChange(prefs, key)
    }

    // -------------------------------------------------------------------------
    //  Event emission (called on the main thread from manager callbacks)
    // -------------------------------------------------------------------------

    /** Wraps a payload in the standard `{type, data}` envelope and dispatches. */
    private fun emitEvent(type: String, payload: Any) {
        eventDispatcher.sendEvent(mapOf("type" to type, "data" to payload))
    }

    /**
     * Replays the latest connectivity + power-save state to a freshly-attached
     * event sink. Called by the adapter when onListen fires so Dart doesn't
     * have to wait for the next state change to see a value.
     */
    fun replayInitialState() {
        systemMonitor.readConnectivityEvent().let { emitEvent("connectivitychange", it) }
        systemMonitor.readPowerSaveState().let { emitEvent("powersavechange", it) }
        // Replay the current pause state so newly-attached Dart listeners don't have
        // to poll: if we cold-started in a persisted 401/403 pause, this is how the
        // UI learns about it.
        syncManager.replaySyncPauseState()
    }

    private fun emitPermissionError(code: String, message: String, details: Map<String, Any>? = null) {
        val data = mutableMapOf<String, Any>("code" to code, "message" to message)
        details?.let { data.putAll(it) }
        emitEvent("error", data)
    }

    // -------------------------------------------------------------------------
    //  Startup + persistence
    // -------------------------------------------------------------------------

    private fun applyStoredConfig() {
        val configJson = prefs.getString("bg_last_config", null) ?: return
        try {
            locationTracker.applyConfig(JSONObject(configJson).toMap())
        } catch (e: JSONException) {
            Log.e(TAG, "Failed to restore config - clearing corrupted data: ${e.message}")
            prefs.edit().remove("bg_last_config").apply()
            emitEvent(
                "error",
                mapOf(
                    "type" to "configError",
                    "message" to "Failed to restore stored config: ${e.message}",
                    "action" to "cleared",
                ),
            )
        }
    }

    /**
     * If [ConfigManager.isTrackingActivePersisted] returns true (set on the
     * last successful [LocationTracker.startTracking] and cleared only by
     * explicit stop), re-arm tracking now. Used after a process cold start
     * so [Locus.isTracking] reflects reality and location events keep flowing.
     */
    private fun reconcilePersistedTrackingState() {
        if (!configManager.isTrackingActivePersisted()) return
        if (locationTracker.isEnabled()) return
        if (!locationClient.hasPermission()) {
            Log.w(TAG, "reconcilePersistedTrackingState: flag set but location permission missing — clearing")
            configManager.setTrackingActive(false)
            return
        }
        Log.i(TAG, "reconcilePersistedTrackingState: re-arming tracking after process restart (bg_tracking_active=true)")
        locationTracker.startTracking()
    }

    // -------------------------------------------------------------------------
    //  Command helpers (split out to keep handleMethodCall readable)
    // -------------------------------------------------------------------------

    private fun handleEnqueue(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments.asMap()
        if (args == null) {
            result.error("INVALID_ARGUMENT", "Expected payload map", null)
            return
        }
        val payloadObj = args["payload"]
        if (payloadObj !is Map<*, *>) {
            result.error("INVALID_ARGUMENT", "Missing payload map", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val payload = payloadObj as Map<String, Any>
        val type = args["type"] as? String ?: "location"
        val idempotencyKey = (args["idempotencyKey"] as? String) ?: UUID.randomUUID().toString()
        val id = stateManager.enqueue(
            payload,
            type,
            idempotencyKey,
            configManager.queueMaxDays.takeIf { it > 0 } ?: 7,
            configManager.queueMaxRecords.takeIf { it > 0 } ?: 500,
        )
        result.success(id)
    }

    private fun handleRegisterHeadlessTask(call: MethodCall, result: MethodChannel.Result) {
        when (val args = call.arguments) {
            is Map<*, *> -> {
                val map = args.asMap()
                val dispatcher = map?.get("dispatcher") as? Number
                val callback = map?.get("callback") as? Number
                if (dispatcher != null && callback != null) {
                    prefs.edit()
                        .putLong("bg_headless_dispatcher", dispatcher.toLong())
                        .putLong("bg_headless_callback", callback.toLong())
                        .apply()
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
                }
            }
            is Number -> {
                prefs.edit().putLong("bg_headless_callback", args.toLong()).apply()
                result.success(true)
            }
            else -> result.error("INVALID_ARGUMENT", "Expected headless callback handle", null)
        }
    }

    private fun handleRegisterCallbackPair(
        call: MethodCall,
        result: MethodChannel.Result,
        dispatcherKey: String,
        callbackKey: String,
    ) {
        val map = (call.arguments as? Map<*, *>)?.asMap()
        val dispatcher = map?.get("dispatcher") as? Number
        val callback = map?.get("callback") as? Number
        if (dispatcher != null && callback != null) {
            prefs.edit()
                .putLong(dispatcherKey, dispatcher.toLong())
                .putLong(callbackKey, callback.toLong())
                .apply()
            result.success(true)
        } else {
            result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
        }
    }

    private fun getCurrentPosition(result: MethodChannel.Result) {
        if (!locationClient.hasPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }
        locationClient.getCurrentPosition(object : LocationClient.LocationResultCallback {
            override fun onSuccess(location: android.location.Location) {
                result.success(locationTracker.buildLocationPayload(location, "location"))
            }

            override fun onError(code: String, message: String) {
                result.error(code, message, null)
            }
        })
    }

    private fun buildConfigSnapshot(): Map<String, Any> {
        val configJson = prefs.getString("bg_last_config", null) ?: return emptyMap()
        return try {
            JSONObject(configJson).toMap()
        } catch (e: JSONException) {
            emptyMap()
        }
    }

    private fun buildDiagnosticsMetadata(): Map<String, Any> = mapOf(
        "platform" to "android",
        "sdkInt" to Build.VERSION.SDK_INT,
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "powerSaveMode" to systemMonitor.readPowerSaveState(),
        "hasLocationPermission" to hasLocationPermission(),
        "hasActivityPermission" to hasActivityPermission(),
        "hasBackgroundLocationPermission" to hasBackgroundLocationPermission(),
    )

    private fun validateManifestPermissions(): List<String> = try {
        val packageInfo = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_PERMISSIONS,
        )
        val declared = packageInfo.requestedPermissions?.toSet() ?: emptySet()
        listOf(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        ).filter { it !in declared }
    } catch (e: Exception) {
        Log.e(TAG, "Failed to validate manifest permissions: ${e.message}")
        emptyList()
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun hasActivityPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBackgroundLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun buildBatteryStats(): Map<String, Any> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        var level = -1
        var charging = false
        battery?.let {
            val l = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val s = it.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            level = if (l >= 0 && s > 0) ((l / s.toDouble()) * 100.0).toInt() else 50
            charging = it.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ==
                BatteryManager.BATTERY_STATUS_CHARGING
        }
        return trackingStats.buildStats(level, charging)
    }

    private fun buildPowerState(): Map<String, Any> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val state = mutableMapOf<String, Any>()
        if (battery != null) {
            val l = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val s = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            state["batteryLevel"] = if (l >= 0 && s > 0) ((l / s.toDouble()) * 100.0).toInt() else -1
            val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            state["isCharging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        } else {
            state["batteryLevel"] = 50
            state["isCharging"] = false
        }
        state["isPowerSaveMode"] = systemMonitor.readPowerSaveState()
        return state
    }

    private fun getNetworkType(): String = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return@runCatching "none"
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return@runCatching "none"
        when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
            else -> "unknown"
        }
    }.getOrElse { e ->
        Log.w(TAG, "Failed to get network type: ${e.message}")
        "none"
    }

    private fun isMeteredConnection(): Boolean = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return@runCatching false
        cm.isActiveNetworkMetered
    }.getOrElse { e ->
        Log.w(TAG, "Failed to check metered connection: ${e.message}")
        false
    }

    private fun setSyncPolicy(policyMap: Map<String, Any>?) {
        policyMap ?: return
        prefs.edit().putString("bg_sync_policy", JSONObject(policyMap).toString()).apply()
        configManager.applySyncPolicy(policyMap)
    }

    private fun isInActiveGeofence(): Boolean {
        val location = locationTracker.getLastLocation() ?: return false
        val geofences = geofenceManager.getGeofencesSync() ?: return false
        for (g in geofences) {
            val lat = g["latitude"].toDoubleOrNull()
            val lng = g["longitude"].toDoubleOrNull()
            val radius = g["radius"].toDoubleOrNull()
            if (lat == null || lng == null || radius == null) continue
            val results = FloatArray(1)
            android.location.Location.distanceBetween(
                location.latitude, location.longitude, lat, lng, results,
            )
            if (results[0] <= radius) return true
        }
        return false
    }

    /**
     * Register the plugin's prefs listener. The adapter does this in
     * [LocusPlugin.onAttachedToEngine] / onReattachedToActivityForConfigChanges.
     * Having it here keeps the prefs handle + listener-tracking in one place.
     */
    fun registerPreferenceListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    fun unregisterPreferenceListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
    }

    companion object {
        private const val TAG = "locus"

        @Volatile
        private var instance: LocusContainer? = null

        /**
         * Returns the process-lifetime container, creating it on first call.
         * Idempotent and thread-safe — all LocusPlugin instances in the
         * process share a single container.
         */
        fun acquire(context: Context): LocusContainer {
            return instance ?: synchronized(LocusContainer::class.java) {
                instance ?: LocusContainer(context.applicationContext).also { instance = it }
            }
        }

        /**
         * Returns the container if it has been initialized; `null` otherwise.
         * Used by code paths (e.g. receivers) that must not trigger
         * construction but want to reach the running container if present.
         */
        fun peek(): LocusContainer? = instance
    }
}

// -----------------------------------------------------------------------------
//  File-private helpers (shared by LocusContainer and its extensions)
// -----------------------------------------------------------------------------

@Suppress("UNCHECKED_CAST")
private fun Any?.asMap(): Map<String, Any>? = this as? Map<String, Any>

@Suppress("UNCHECKED_CAST")
private fun Any?.asList(): List<Any> = (this as? List<Any>) ?: emptyList()

private fun Any?.toDoubleOrNull(): Double? = when (this) {
    is Number -> this.toDouble()
    is String -> this.toDoubleOrNull()
    else -> null
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
            JSONObject.NULL -> Unit
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
            JSONObject.NULL -> Unit
            else -> value?.let { list.add(it) }
        }
    }
    return list
}
