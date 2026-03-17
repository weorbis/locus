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

class HeadlessService : JobIntentService() {

    companion object {
        private const val TAG = "locus.HeadlessService"
        private const val CHANNEL = "locus/headless"
        private const val CACHE_KEY = "locus_headless_engine"
        private const val JOB_ID = 197812512
        private const val PREFS_NAME = "dev.locus.preferences"
        private const val KEY_ENABLE_HEADLESS = "bg_enable_headless"

        private var engine: FlutterEngine? = null
        private var channel: MethodChannel? = null
        private val pendingEvents: MutableList<Map<String, Any>> =
            Collections.synchronizedList(LinkedList())

        // Counts down when the Dart dispatcher signals readiness AND all
        // queued events have been drained. onHandleWork awaits this instead
        // of polling — deterministic, no Thread.sleep.
        private var dispatcherReady = CountDownLatch(1)

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
        if (!headlessEnabled) {
            dispatcherReady.countDown()
            return
        }

        val dispatcherHandle = prefs.getLong("bg_headless_dispatcher", 0L)
        if (dispatcherHandle == 0L) {
            dispatcherReady.countDown()
            return
        }

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
                        dispatcherReady.countDown()
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
                    // drain any events that queued while the isolate started,
                    // and finally count down the latch so onHandleWork unblocks.
                    newChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                        if (call.method == "dispatcher#initialized") {
                            result.success(true)
                            synchronized(pendingEvents) {
                                for (event in pendingEvents) {
                                    newChannel.invokeMethod("headlessEvent", event)
                                }
                                pendingEvents.clear()
                            }
                            dispatcherReady.countDown()
                        } else {
                            result.notImplemented()
                        }
                    }

                    engine = newEngine
                    channel = newChannel
                    FlutterEngineCache.getInstance().put(CACHE_KEY, newEngine)

                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start background isolate: ${e.message}", e)
                    dispatcherReady.countDown()
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

        // If dispatcher is already ready, dispatch immediately on the main thread.
        if (dispatcherReady.count == 0L && channel != null) {
            val latch = CountDownLatch(1)
            mainHandler.post {
                try {
                    channel?.invokeMethod("headlessEvent", args)
                } finally {
                    latch.countDown()
                }
            }
            latch.await()
        } else {
            // Queue the event — it will be dispatched when the Dart dispatcher
            // signals readiness (dispatcher#initialized handler drains the queue
            // and counts down the latch).
            synchronized(pendingEvents) {
                pendingEvents.add(args)
            }
            dispatcherReady.await()
            if (channel == null) {
                Log.w(TAG, "Dispatcher initialization failed, event dropped")
            }
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }
}
