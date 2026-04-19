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
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import dev.locus.activity.MotionManager
import dev.locus.core.BackgroundTaskManager
import dev.locus.core.AutoSyncChecker
import dev.locus.core.ConfigManager
import dev.locus.core.EventDispatcher
import dev.locus.core.ForegroundServiceController
import dev.locus.service.ForegroundService
import dev.locus.core.GeofenceEventProcessor
import dev.locus.core.HeadlessDispatcher
import dev.locus.core.HeadlessHeadersDispatcher
import dev.locus.core.HeadlessValidationDispatcher
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

        /**
         * Singleton guard for multi-engine environments.
         *
         * flutter_background_service and other plugins can create additional Flutter engines.
         * Each engine triggers GeneratedPluginRegistrant which creates a new LocusPlugin instance.
         * Only one instance should own native resources to prevent:
         * - SharedPreferences races (privacy mode reset, config overwrites)
         * - Duplicate Activity Recognition PendingIntents being unregistered
         * - Database access conflicts (SQLite contention)
         * - Resource cleanup on secondary engine detach killing primary tracking
         */
        @Volatile
        private var primaryInstance: LocusPlugin? = null
    }

    private var isPrimary = false

    /**
     * True when this primary plugin's FlutterEngine detached while `stopOnTerminate`
     * was false and tracking was active. In that case we keep [primaryInstance]
     * alive so the foreground service and its managers continue running; on the next
     * primary-engine attach, the new plugin instance detects this flag and takes
     * over ownership of the shared managers via [takeOverFrom].
     */
    @Volatile
    private var isSoftDetached = false

    /**
     * Set on a new plugin instance when its [onAttachedToEngine] finds a
     * soft-detached predecessor but cannot yet confirm that this engine is the UI
     * engine (background isolates created by [HeadlessService] etc. also attach
     * LocusPlugin via `GeneratedPluginRegistrant`). Takeover is deferred to
     * [onAttachedToActivity]; if that callback never fires (pure-background engine),
     * the predecessor keeps ownership of the managers and this plugin stays in a
     * no-op secondary state until its own engine detaches.
     */
    @Volatile
    private var pendingPredecessor: LocusPlugin? = null

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var androidContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var prefs: SharedPreferences? = null
    private var isListenerRegistered = false

    private var configManager: ConfigManager? = null
    private var stateManager: StateManager? = null
    private var logManager: LogManager? = null
    private var headlessDispatcher: HeadlessDispatcher? = null
    private var headlessHeadersDispatcher: HeadlessHeadersDispatcher? = null
    private var headlessValidationDispatcher: HeadlessValidationDispatcher? = null
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

        // Always set up method/event channels so this engine can handle calls.
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }

        // Four possible paths:
        //   1) No existing primary      → fresh init (this plugin becomes primary).
        //   2) Soft-detached predecessor, and this IS the UI engine → defer takeover
        //      to onAttachedToActivity (only UI engines get an Activity binding;
        //      background isolates from HeadlessService must never hijack primary).
        //   3) Same instance re-attached → defensive no-op.
        //   4) Live secondary engine    → stay secondary (flutter_background_service etc.).
        synchronized(LocusPlugin::class.java) {
            val existing = primaryInstance
            when {
                existing == null -> {
                    primaryInstance = this
                    isPrimary = true
                }
                existing === this -> {
                    isPrimary = true
                    isSoftDetached = false
                }
                existing.isSoftDetached -> {
                    // Provisional: we don't yet know if this is a UI engine or a
                    // HeadlessService background isolate. Both call onAttachedToEngine
                    // identically. Wait for onAttachedToActivity to confirm UI.
                    pendingPredecessor = existing
                    isPrimary = false
                    return
                }
                else -> {
                    Log.w(TAG, "LocusPlugin: secondary engine attached - native resources owned by primary instance, skipping init")
                    isPrimary = false
                    return
                }
            }
        }

        if (configManager == null) {
            initNativeResources()
            reconcilePersistedTrackingState()
        }

        if (prefs != null && !isListenerRegistered) {
            prefs?.registerOnSharedPreferenceChangeListener(this)
            isListenerRegistered = true
        }
    }

    /**
     * Completes a deferred takeover from a soft-detached predecessor. Fires only for
     * UI FlutterEngines (background isolates created via [FlutterEngine(Context)] do
     * not receive activity bindings). See [onAttachedToEngine] path #2.
     */
    private fun finalizeTakeOver() {
        val pending = pendingPredecessor ?: return
        val takeOver: Boolean = synchronized(LocusPlugin::class.java) {
            if (primaryInstance === pending && pending.isSoftDetached) {
                primaryInstance = this
                isPrimary = true
                pendingPredecessor = null
                true
            } else {
                // Predecessor was reclaimed by another UI attach, or process died.
                pendingPredecessor = null
                false
            }
        }
        if (!takeOver) return

        Log.i(TAG, "LocusPlugin: taking over from soft-detached predecessor (UI re-attached)")
        takeOverFrom(pending)
        pending.clearSoftDetachedState()

        if (prefs != null && !isListenerRegistered) {
            prefs?.registerOnSharedPreferenceChangeListener(this)
            isListenerRegistered = true
        }
    }

    /**
     * Cold-start reconciliation: if the process was killed while tracking was active
     * (e.g. swipe-away under a stopOnTerminate:false config followed by OS reap, or
     * force-stop), the persisted flag is still `true`. Re-arm tracking so that
     * [Locus.isTracking] reports accurately and locations keep flowing on the new
     * process. Silent no-op when permissions were revoked or nothing was active.
     */
    private fun reconcilePersistedTrackingState() {
        val config = configManager ?: return
        val tracker = locationTracker ?: return
        val client = locationClient ?: return

        if (!config.isTrackingActivePersisted()) return
        if (tracker.isEnabled()) return
        if (!client.hasPermission()) {
            Log.w(TAG, "reconcilePersistedTrackingState: tracking flag is set but location permission is missing — clearing flag")
            config.setTrackingActive(false)
            return
        }

        Log.i(TAG, "reconcilePersistedTrackingState: re-arming tracking after process restart (bg_tracking_active=true)")
        tracker.startTracking()
    }

    /**
     * Creates all native managers for a fresh primary plugin. Called exactly once per
     * process on first primary attach. A second primary attach after a hard detach
     * (process still alive, stopOnTerminate=true or nothing was tracking) will also
     * land here.
     */
    private fun initNativeResources() {
        prefs = androidContext?.let { it.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

        // IMPORTANT: Always start with privacy mode disabled on fresh plugin attach.
        // This prevents stale persisted values from blocking location sync before Locus.ready() is called.
        // Privacy mode should only be enabled explicitly via setPrivacyMode() API or config.
        privacyModeEnabled = false
        prefs?.edit()?.remove("bg_privacy_mode")?.apply()

        val context = androidContext ?: return
        val preferences = prefs ?: return

        // Privacy mode is always false on attach. Use setPrivacyMode() or config to enable.
        val config = ConfigManager(context).also {
            it.privacyModeEnabled = privacyModeEnabled
        }
        configManager = config

        // Log the initial privacy mode state for debugging
        Log.d(TAG, "LocusPlugin initialized - privacyModeEnabled=${privacyModeEnabled} (always false on attach)")

        val state = StateManager(context)
        stateManager = state

        val stats = TrackingStats(context)
        trackingStats = stats

        val logs = LogManager(config, state.logStore)
        logManager = logs

        val headless = HeadlessDispatcher(context, config, preferences)
        headlessDispatcher = headless
        val headlessHeaders = HeadlessHeadersDispatcher(context, config, preferences)
        headlessHeadersDispatcher = headlessHeaders

        val headlessValidation = HeadlessValidationDispatcher(context, config, preferences)
        headlessValidationDispatcher = headlessValidation

        val events = EventDispatcher(headless)
        eventDispatcher = events

        systemMonitor = SystemMonitor(context, buildSystemMonitorListener())

        backgroundTaskManager = BackgroundTaskManager(context)

        val fgController = ForegroundServiceController(context)
        foregroundServiceController = fgController

        val geofence = GeofenceManager(context, buildGeofenceListener())
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
            buildSyncListener()
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
        val payloadBuilder = LocationPayloadBuilder(config, motion, state)
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

        scheduler = Scheduler(config, buildSchedulerListener())

        applyStoredConfig()
        systemMonitor?.registerConnectivity()
        systemMonitor?.registerPowerSave()
    }

    /**
     * Transfers manager references from a soft-detached primary to this new primary,
     * then rebinds the manager listeners so their callbacks reference this plugin
     * (rather than the dead engine's MethodChannel / EventSink).
     */
    private fun takeOverFrom(old: LocusPlugin) {
        androidContext = old.androidContext ?: androidContext
        prefs = old.prefs
        privacyModeEnabled = old.privacyModeEnabled

        configManager = old.configManager
        stateManager = old.stateManager
        logManager = old.logManager
        headlessDispatcher = old.headlessDispatcher
        headlessHeadersDispatcher = old.headlessHeadersDispatcher
        headlessValidationDispatcher = old.headlessValidationDispatcher
        eventDispatcher = old.eventDispatcher
        systemMonitor = old.systemMonitor
        backgroundTaskManager = old.backgroundTaskManager
        foregroundServiceController = old.foregroundServiceController
        geofenceManager = old.geofenceManager
        locationClient = old.locationClient
        motionManager = old.motionManager
        syncManager = old.syncManager
        locationTracker = old.locationTracker
        scheduler = old.scheduler
        preferenceEventHandler = old.preferenceEventHandler
        trackingStats = old.trackingStats

        // Rebind listeners whose callbacks capture methodChannel / emit* methods of
        // the old plugin. Without this, invokeMethod would target the dead engine.
        systemMonitor?.setListener(buildSystemMonitorListener())
        syncManager?.setListener(buildSyncListener())
        geofenceManager?.setListener(buildGeofenceListener())
        scheduler?.setListener(buildSchedulerListener())
    }

    private fun clearSoftDetachedState() {
        // Unregister the prefs listener from the old (this) plugin BEFORE the new
        // primary registers its own. Done here — and not in onDetachedFromEngine's
        // soft-detach path — so broadcast-receiver writes that arrive between
        // detach and takeover are delivered to the shared PreferenceEventHandler.
        if (prefs != null && isListenerRegistered) {
            prefs?.unregisterOnSharedPreferenceChangeListener(this)
            isListenerRegistered = false
        }
        isSoftDetached = false
        isPrimary = false
        // Drop refs so GC can reclaim this (old) plugin promptly.
        configManager = null
        stateManager = null
        logManager = null
        headlessDispatcher = null
        headlessHeadersDispatcher = null
        headlessValidationDispatcher = null
        eventDispatcher = null
        systemMonitor = null
        backgroundTaskManager = null
        foregroundServiceController = null
        geofenceManager = null
        locationClient = null
        motionManager = null
        syncManager = null
        locationTracker = null
        scheduler = null
        preferenceEventHandler = null
        trackingStats = null
        prefs = null
        methodChannel = null
        eventChannel = null
        androidContext = null
    }

    private fun buildSystemMonitorListener(): SystemMonitor.Listener =
        object : SystemMonitor.Listener {
            override fun onConnectivityChange(payload: Map<String, Any>) {
                emitConnectivityChange(payload)
            }

            override fun onPowerSaveChange(enabled: Boolean) {
                emitPowerSaveChange(enabled)
            }
        }

    private fun buildGeofenceListener(): GeofenceManager.GeofenceListener =
        GeofenceManager.GeofenceListener { added, removed ->
            emitGeofencesChange(added, removed)
        }

    private fun buildSchedulerListener(): Scheduler.SchedulerListener =
        Scheduler.SchedulerListener { shouldBeEnabled ->
            val tracker = locationTracker
            if (tracker == null) {
                shouldBeEnabled
            } else {
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
        }

    private fun buildSyncListener(): SyncManager.SyncListener =
        object : SyncManager.SyncListener {
            override fun onHttpEvent(eventData: Map<String, Any>) {
                eventDispatcher?.sendEvent(eventData)
            }

            override fun onLog(level: String, message: String) {
                logManager?.log(level, message)
            }

            override fun onSyncRequest() {
                trackingStats?.onSyncRequest()
            }

            override fun buildSyncBody(
                locations: List<Map<String, Any>>,
                extras: Map<String, Any>,
                callback: (JSONObject?) -> Unit
            ) {
                val channel = methodChannel
                if (channel == null) {
                    callback(null)
                    return
                }
                // Must invoke on main thread for Flutter MethodChannel
                mainHandler.post {
                    val args = mapOf(
                        "locations" to locations,
                        "extras" to extras
                    )
                    channel.invokeMethod("buildSyncBody", args, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            @Suppress("UNCHECKED_CAST")
                            val body = when (result) {
                                is Map<*, *> -> JSONObject(result as Map<String, Any>)
                                is String -> try { JSONObject(result) } catch (e: Exception) { null }
                                else -> null
                            }
                            callback(body)
                        }
                        override fun error(code: String, message: String?, details: Any?) {
                            Log.e(TAG, "buildSyncBody error: $code - $message")
                            callback(null)
                        }
                        override fun notImplemented() {
                            callback(null)
                        }
                    })
                }
            }

            override fun onPreSyncValidation(
                locations: List<Map<String, Any>>,
                extras: Map<String, Any>,
                callback: (Boolean) -> Unit
            ) {
                val channel = methodChannel
                if (channel == null) {
                    // No method channel available (engine detached or app terminated).
                    // Use headless validation if a callback is registered, otherwise proceed.
                    val headlessValidator = headlessValidationDispatcher
                    if (headlessValidator != null && headlessValidator.isAvailable()) {
                        Log.d(TAG, "Using headless validation for pre-sync check")
                        headlessValidator.validate(locations, extras, callback)
                    } else {
                        callback(true)
                    }
                    return
                }
                mainHandler.post {
                    val args = mapOf(
                        "locations" to locations,
                        "extras" to extras
                    )
                    channel.invokeMethod("validatePreSync", args, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            callback(result as? Boolean ?: true)
                        }
                        override fun error(code: String, message: String?, details: Any?) {
                            Log.e(TAG, "validatePreSync error: $code - $message")
                            // Proceed on error to avoid blocking sync permanently
                            callback(true)
                        }
                        override fun notImplemented() {
                            callback(true)
                        }
                    })
                }
            }

            override fun onHeadersRefresh(callback: (Map<String, String>?) -> Unit) {
                val channel = methodChannel
                if (channel != null) {
                    var responded = false
                    val timeoutRunnable = Runnable {
                        if (!responded) {
                            responded = true
                            Log.w(TAG, "refreshDynamicHeaders timed out after 10s")
                            callback(null)
                        }
                    }
                    mainHandler.postDelayed(timeoutRunnable, 10_000L)
                    mainHandler.post {
                        channel.invokeMethod("refreshDynamicHeaders", null, object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                if (responded) return
                                responded = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                @Suppress("UNCHECKED_CAST")
                                val headers = (result as? Map<*, *>)?.entries?.mapNotNull { entry ->
                                    val key = entry.key?.toString() ?: return@mapNotNull null
                                    val value = entry.value?.toString() ?: return@mapNotNull null
                                    key to value
                                }?.toMap()
                                callback(headers)
                            }
                            override fun error(code: String, message: String?, details: Any?) {
                                if (responded) return
                                responded = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                Log.e(TAG, "refreshDynamicHeaders error: $code - $message")
                                callback(null)
                            }
                            override fun notImplemented() {
                                if (responded) return
                                responded = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                callback(null)
                            }
                        })
                    }
                    return
                }

                val dispatcher = headlessHeadersDispatcher
                if (dispatcher != null && dispatcher.isAvailable()) {
                    dispatcher.refreshHeaders(callback)
                } else {
                    callback(null)
                }
            }
        }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Secondary engines always tear down their own channels and do nothing else.
        // They must NOT touch shared native resources.
        if (!isPrimary) {
            eventChannel?.setStreamHandler(null)
            methodChannel?.setMethodCallHandler(null)
            Log.d(TAG, "LocusPlugin: secondary engine detached - skipping native resource cleanup")
            return
        }

        // Primary engine detach. Choose soft vs hard teardown based on the documented
        // always-on contract: when stopOnTerminate=false AND tracking is active, we
        // MUST keep the foreground service + managers alive so locations keep flowing
        // while the UI is gone. The next primary attach reclaims ownership via
        // takeOverFrom() (see onAttachedToEngine).
        val config = configManager
        val tracker = locationTracker
        val shouldSoftDetach = config != null &&
            !config.stopOnTerminate &&
            tracker?.isEnabled() == true

        if (shouldSoftDetach) {
            Log.i(TAG, "LocusPlugin: soft detach - keeping native resources alive (stopOnTerminate=false, tracking active)")
            // The BinaryMessenger is about to die; clear channel handlers so the framework
            // doesn't dispatch to us, and null the sink so events route to headless.
            eventChannel?.setStreamHandler(null)
            methodChannel?.setMethodCallHandler(null)
            eventDispatcher?.setEventSink(null)
            // Keep the prefs listener REGISTERED until takeover completes. Broadcast
            // receivers (ActivityRecognized, Geofence, NotificationAction) write
            // transient events to SharedPreferences; unregistering here would drop any
            // that arrive before the next primary attaches. PreferenceEventHandler
            // holds no reference to this plugin — it routes through the shared
            // EventDispatcher (whose headless fallback fires when eventSink is null).
            isSoftDetached = true
            // NB: primaryInstance is intentionally NOT cleared — this plugin keeps the
            // managers alive (via field references) until takeover.
            tracker?.releaseListeners()
            return
        }

        Log.i(TAG, "LocusPlugin: hard detach - releasing native resources")
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)

        synchronized(LocusPlugin::class.java) {
            if (primaryInstance === this) {
                primaryInstance = null
            }
            isPrimary = false
        }

        if (config?.stopOnTerminate == true) {
            tracker?.stopTracking()
        }
        motionManager?.stop()
        locationTracker?.releaseAll()
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
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (!isPrimary) return
        eventDispatcher?.setEventSink(events)
        systemMonitor?.readConnectivityEvent()?.let { emitConnectivityChange(it) }
        systemMonitor?.readPowerSaveState()?.let { emitPowerSaveChange(it) }
    }

    override fun onCancel(arguments: Any?) {
        if (!isPrimary) return
        eventDispatcher?.setEventSink(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        // Activity binding only fires for UI FlutterEngines, not for background
        // isolates spawned by HeadlessService. This is our one reliable signal
        // that we are the UI, so a deferred takeover is safe here.
        if (pendingPredecessor != null) {
            finalizeTakeOver()
        }
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
        // Secondary engines must not interact with native resources
        if (!isPrimary) {
            Log.d(TAG, "LocusPlugin: ignoring '${call.method}' on secondary engine")
            result.success(null)
            return
        }

        when (call.method) {
            "ready" -> {
                val missingPermissions = validateManifestPermissions()
                if (missingPermissions.isNotEmpty()) {
                    Log.w(TAG, "Missing manifest permissions: $missingPermissions")
                    emitPermissionError(
                        "ERR_MISSING_MANIFEST",
                        "Required permissions not declared in AndroidManifest.xml: ${missingPermissions.joinToString(", ")}",
                        mapOf("permissions" to missingPermissions)
                    )
                }
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
            "updateNotification" -> {
                if (locationTracker?.isEnabled() != true) {
                    result.success(false)
                    return
                }
                val args = call.arguments.asMap()
                val title = args?.get("title") as? String
                val text = args?.get("text") as? String
                val context = androidContext
                if (context != null) {
                    result.success(ForegroundService.updateNotification(context, title, text))
                } else {
                    result.success(false)
                }
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
            "pauseSync" -> {
                syncManager?.pause()
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
            "setSyncBodyBuilderEnabled" -> {
                val enabled = call.arguments as? Boolean ?: false
                syncManager?.syncBodyBuilderEnabled = enabled
                result.success(true)
            }
            "registerHeadlessSyncBodyBuilder" -> {
                when (val args = call.arguments) {
                    is Map<*, *> -> {
                        val map = args.asMap()
                        val dispatcher = map?.get("dispatcher") as? Number
                        val callback = map?.get("callback") as? Number
                        if (dispatcher != null && callback != null) {
                            prefs?.edit()
                                ?.putLong("bg_headless_sync_body_dispatcher", dispatcher.toLong())
                                ?.putLong("bg_headless_sync_body_callback", callback.toLong())
                                ?.apply()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
                        }
                    }
                    else -> {
                        result.error("INVALID_ARGUMENT", "Expected map argument", null)
                    }
                }
            }
            "registerHeadlessValidationCallback" -> {
                when (val args = call.arguments) {
                    is Map<*, *> -> {
                        val map = args.asMap()
                        val dispatcher = map?.get("dispatcher") as? Number
                        val callback = map?.get("callback") as? Number
                        if (dispatcher != null && callback != null) {
                            prefs?.edit()
                                ?.putLong(HeadlessValidationDispatcher.KEY_VALIDATION_DISPATCHER, dispatcher.toLong())
                                ?.putLong(HeadlessValidationDispatcher.KEY_VALIDATION_CALLBACK, callback.toLong())
                                ?.apply()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
                        }
                    }
                    else -> {
                        result.error("INVALID_ARGUMENT", "Expected map argument", null)
                    }
                }
            }
            "registerHeadlessHeadersCallback" -> {
                when (val args = call.arguments) {
                    is Map<*, *> -> {
                        val map = args.asMap()
                        val dispatcher = map?.get("dispatcher") as? Number
                        val callback = map?.get("callback") as? Number
                        if (dispatcher != null && callback != null) {
                            prefs?.edit()
                                ?.putLong(
                                    HeadlessHeadersDispatcher.KEY_HEADERS_DISPATCHER,
                                    dispatcher.toLong(),
                                )
                                ?.putLong(
                                    HeadlessHeadersDispatcher.KEY_HEADERS_CALLBACK,
                                    callback.toLong(),
                                )
                                ?.apply()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Expected dispatcher and callback handles", null)
                        }
                    }
                    else -> {
                        result.error("INVALID_ARGUMENT", "Expected map argument", null)
                    }
                }
            }
            "getLocationSyncBacklog" -> {
                result.success(syncManager?.getLocationSyncBacklog() ?: emptyMap<String, Any?>())
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

    private fun validateManifestPermissions(): List<String> {
        val context = androidContext ?: return emptyList()
        return try {
            val packageInfo = context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_PERMISSIONS
            )
            val declared = packageInfo.requestedPermissions?.toSet() ?: emptySet()
            val required = listOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
            required.filter { it !in declared }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to validate manifest permissions: ${e.message}")
            emptyList()
        }
    }

    private fun emitPermissionError(code: String, message: String, details: Map<String, Any>? = null) {
        val errorData = mutableMapOf<String, Any>(
            "code" to code,
            "message" to message
        )
        details?.let { errorData.putAll(it) }
        val event = mapOf(
            "type" to "error",
            "data" to errorData
        )
        eventDispatcher?.sendEvent(event)
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
        return runCatching {
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
    }

    private fun isMeteredConnection(): Boolean {
        val context = androidContext ?: return false
        return runCatching {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return@runCatching false
            cm.isActiveNetworkMetered
        }.getOrElse { e ->
            Log.w(TAG, "Failed to check metered connection: ${e.message}")
            false
        }
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
