package dev.locus

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.locus.core.LocusContainer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Per-FlutterEngine adapter between Dart and Locus's process-lifetime native
 * state. All actual work — configuration, storage, location subscriptions,
 * sync, foreground service, geofencing — lives in [LocusContainer] which is a
 * process-scoped singleton.
 *
 * ### Lifecycle
 *
 * Every engine that runs `GeneratedPluginRegistrant.registerWith(...)` gets
 * its own plugin instance: the UI FlutterActivity, any `FlutterFragment`, and
 * each background isolate created by [HeadlessService]/[HeadlessHeadersService]/
 * [HeadlessValidationService]. Each instance holds only:
 *
 *  * its own [MethodChannel] + [EventChannel] — tied to a specific engine's
 *    [BinaryMessenger] and therefore NOT shareable across engines;
 *  * a strong reference to the one shared [LocusContainer];
 *  * a [LocusContainer.DartBridge] that routes outgoing Dart calls through
 *    this engine's channels, active only when this engine's [EventChannel] has
 *    a subscriber.
 *
 * When a plugin instance detaches (engine destroyed), it simply drops its
 * channel handlers and releases its bridge. The container keeps running. The
 * next plugin to attach picks up the same container and can resume operation
 * immediately — no takeover, no listener rebinding, no singleton hand-off.
 *
 * ### Previous design (for reviewers)
 *
 * Before this refactor, LocusPlugin owned every manager as a field and the
 * detach path tried to preserve managers via a soft-detach + primary-takeover
 * state machine. That introduced subtle bugs (`HeadlessService`'s background
 * isolate would hijack primary; listener closures captured the dead engine's
 * MethodChannel, requiring setListener rebinding on every manager). Moving
 * process-scoped state into [LocusContainer] eliminates that entire class of
 * problems.
 */
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

    private val mainHandler = Handler(Looper.getMainLooper())
    private var container: LocusContainer? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var isListenerRegistered = false
    private var bridgeBound = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val c = LocusContainer.acquire(binding.applicationContext)
        container = c

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }

        if (!isListenerRegistered) {
            c.registerPreferenceListener(this)
            isListenerRegistered = true
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel = null
        methodChannel = null

        val c = container
        if (c != null) {
            if (bridgeBound) {
                c.setBridge(null)
                c.eventDispatcher.setEventSink(null)
                bridgeBound = false
            }
            if (isListenerRegistered) {
                c.unregisterPreferenceListener(this)
                isListenerRegistered = false
            }
        }
        container = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val c = container ?: return
        val sink = events ?: return
        // Route incoming events through this sink. EventDispatcher falls back
        // to HeadlessDispatcher automatically when the sink is null, so
        // background isolates needn't subscribe.
        c.eventDispatcher.setEventSink(sink)
        // Route outbound invokeMethod calls (buildSyncBody, validatePreSync,
        // refreshDynamicHeaders) through this engine's MethodChannel. Last-
        // writer-wins: if two engines subscribe, the latest one owns these
        // callbacks. In practice only the UI engine ever subscribes here.
        c.setBridge(buildBridge())
        bridgeBound = true
        // Replay latest connectivity + power-save state so Dart doesn't wait
        // for the next change.
        c.replayInitialState()
    }

    override fun onCancel(arguments: Any?) {
        val c = container ?: return
        if (bridgeBound) {
            c.setBridge(null)
            c.eventDispatcher.setEventSink(null)
            bridgeBound = false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val c = container
        if (c == null) {
            result.error("NOT_INITIALIZED", "Locus container not available", null)
            return
        }
        c.handleMethodCall(call, result)
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        val c = container ?: return
        if (sharedPreferences != null) {
            c.handlePreferenceChange(sharedPreferences, key)
        }
    }

    // ActivityAware: no-op. The container is not activity-scoped.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) = Unit
    override fun onDetachedFromActivityForConfigChanges() = Unit
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = Unit
    override fun onDetachedFromActivity() = Unit

    // -------------------------------------------------------------------------
    //  DartBridge — routes outbound calls through this plugin's channels.
    //  The bridge holds captures of `sink`, `methodChannel`, and `mainHandler`
    //  that are valid for the lifetime of this plugin's engine. When the
    //  engine detaches, [setBridge(null)] installs a `null` bridge and events
    //  fall back to HeadlessDispatcher.
    // -------------------------------------------------------------------------

    private fun buildBridge(): LocusContainer.DartBridge {
        val channel = methodChannel
        val handler = mainHandler
        return object : LocusContainer.DartBridge {
            // Events flow through EventDispatcher (set up in onListen). The
            // bridge only handles outgoing native→Dart invokeMethod calls.

            override fun invokeBuildSyncBody(
                locations: List<Map<String, Any>>,
                extras: Map<String, Any>,
                callback: (JSONObject?) -> Unit,
            ) {
                val ch = channel
                if (ch == null) {
                    callback(null)
                    return
                }
                handler.post {
                    ch.invokeMethod(
                        "buildSyncBody",
                        mapOf("locations" to locations, "extras" to extras),
                        object : MethodChannel.Result {
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
                            override fun notImplemented() { callback(null) }
                        },
                    )
                }
            }

            override fun invokeValidatePreSync(
                locations: List<Map<String, Any>>,
                extras: Map<String, Any>,
                callback: (Boolean) -> Unit,
            ) {
                val ch = channel
                if (ch == null) {
                    callback(true)
                    return
                }
                handler.post {
                    ch.invokeMethod(
                        "validatePreSync",
                        mapOf("locations" to locations, "extras" to extras),
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                callback(result as? Boolean ?: true)
                            }
                            override fun error(code: String, message: String?, details: Any?) {
                                Log.e(TAG, "validatePreSync error: $code - $message")
                                callback(true)
                            }
                            override fun notImplemented() { callback(true) }
                        },
                    )
                }
            }

            override fun invokeRefreshHeaders(callback: (Map<String, String>?) -> Unit) {
                val ch = channel
                if (ch == null) {
                    callback(null)
                    return
                }
                var responded = false
                val timeout = Runnable {
                    if (!responded) {
                        responded = true
                        Log.w(TAG, "refreshDynamicHeaders timed out after 10s")
                        callback(null)
                    }
                }
                handler.postDelayed(timeout, 10_000L)
                handler.post {
                    ch.invokeMethod("refreshDynamicHeaders", null, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            if (responded) return
                            responded = true
                            handler.removeCallbacks(timeout)
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
                            handler.removeCallbacks(timeout)
                            Log.e(TAG, "refreshDynamicHeaders error: $code - $message")
                            callback(null)
                        }
                        override fun notImplemented() {
                            if (responded) return
                            responded = true
                            handler.removeCallbacks(timeout)
                            callback(null)
                        }
                    })
                }
            }
        }
    }
}
