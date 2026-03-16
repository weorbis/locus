package dev.locus.service

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.JobIntentService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.*
import java.util.Collections
import java.util.LinkedList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class HeadlessService : JobIntentService() {

    companion object {
        private const val TAG = "locus.HeadlessService"
        private const val CHANNEL = "locus/headless"
        private const val CACHE_KEY = "locus_headless_engine"
        private const val JOB_ID = 197812512
        private const val ENGINE_IDLE_TIMEOUT_MS = 60_000L
        private const val LATCH_TIMEOUT_SECONDS = 30L
        private const val PREFS_NAME = "dev.locus.preferences"
        private const val KEY_ENABLE_HEADLESS = "bg_enable_headless"

        private var engine: FlutterEngine? = null
        private var channel: MethodChannel? = null
        private val isDispatcherReady = AtomicBoolean(false)
        private val pendingEvents: MutableList<Map<String, Any>> =
            Collections.synchronizedList(LinkedList())

        fun enqueueWork(context: Context, intent: Intent) {
            enqueueWork(context, HeadlessService::class.java, JOB_ID, intent)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate() {
        super.onCreate()
        // Start the background isolate early (like firebase_messaging does).
        // By the time onHandleWork is called, the isolate may already be ready.
        if (engine == null) {
            startBackgroundIsolate()
        }
    }

    private fun startBackgroundIsolate() {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val headlessEnabled = prefs.getBoolean(KEY_ENABLE_HEADLESS, false)
        if (!headlessEnabled) return

        val dispatcherHandle = prefs.getLong("bg_headless_dispatcher", 0L)
        if (dispatcherHandle == 0L) return

        val loader = FlutterInjector.instance().flutterLoader()

        // Use ensureInitializationCompleteAsync (like firebase_messaging) to
        // allow the main looper to process pending Flutter init between loader
        // init and engine creation. The synchronous version blocks the main
        // thread, preventing the engine from fully initializing.
        mainHandler.post {
            loader.startInitialization(applicationContext)
            loader.ensureInitializationCompleteAsync(
                applicationContext,
                null,
                mainHandler
            ) {
                val appBundlePath = loader.findAppBundlePath()

                try {
                    val newEngine = FlutterEngine(applicationContext)

                    val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
                    if (info == null) {
                        Log.w(TAG, "Could not lookup dispatcher callback for handle: $dispatcherHandle")
                        return@ensureInitializationCompleteAsync
                    }

                    // Set up MethodChannel BEFORE executeDartCallback (like FCM does).
                    // The Dart dispatcher calls invokeMethod('dispatcher#initialized')
                    // immediately on startup — the channel must be listening first.
                    val newChannel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CHANNEL)

                    val callback = DartExecutor.DartCallback(
                        applicationContext.assets,
                        appBundlePath,
                        info
                    )
                    newEngine.dartExecutor.executeDartCallback(callback)

                    // Listen for the Dart dispatcher's readiness signal, then
                    // process any events that queued while the isolate started.
                    newChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                        if (call.method == "dispatcher#initialized") {
                            isDispatcherReady.set(true)
                            result.success(true)
                            synchronized(pendingEvents) {
                                for (event in pendingEvents) {
                                    newChannel.invokeMethod("headlessEvent", event)
                                }
                                pendingEvents.clear()
                            }
                        } else {
                            result.notImplemented()
                        }
                    }

                    engine = newEngine
                    channel = newChannel
                    FlutterEngineCache.getInstance().put(CACHE_KEY, newEngine)

                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start background isolate: ${e.message}", e)
                }
            }
        }
    }

    override fun onHandleWork(intent: Intent) {
        val callbackHandle = intent.getLongExtra("callback", 0L)
        if (callbackHandle == 0L) return

        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val headlessEnabled = prefs.getBoolean(KEY_ENABLE_HEADLESS, false)
        if (!headlessEnabled) return

        val rawEvent = intent.getStringExtra("event")
        val args = mapOf<String, Any>(
            "callbackHandle" to callbackHandle,
            "event" to (rawEvent ?: "{\"type\":\"boot\"}")
        )

        // If dispatcher is ready, dispatch immediately.
        // Otherwise, queue the event — it will be sent when the dispatcher
        // signals readiness (same pattern as firebase_messaging).
        if (isDispatcherReady.get() && channel != null) {
            val latch = CountDownLatch(1)
            mainHandler.post {
                try {
                    channel?.invokeMethod("headlessEvent", args)
                } finally {
                    latch.countDown()
                }
            }
            try {
                latch.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        } else {
            synchronized(pendingEvents) {
                pendingEvents.add(args)
            }
            // Wait for the dispatcher to process the queued event.
            val startTime = System.currentTimeMillis()
            while (!isDispatcherReady.get() &&
                System.currentTimeMillis() - startTime < LATCH_TIMEOUT_SECONDS * 1000
            ) {
                Thread.sleep(100)
            }
            if (isDispatcherReady.get()) {
                // Give a moment for queued events to be processed on main thread.
                Thread.sleep(500)
            } else {
                Log.w(TAG, "Timed out waiting for Dart dispatcher")
            }
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }
}
