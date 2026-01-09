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
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class HeadlessService : JobIntentService() {

    companion object {
        private const val TAG = "locus.HeadlessService"
        private const val CHANNEL = "locus/headless"
        private const val CACHE_KEY = "locus_headless_engine"
        private const val JOB_ID = 197812512
        private const val ENGINE_IDLE_TIMEOUT_MS = 60_000L
        private const val LATCH_TIMEOUT_SECONDS = 30L
        private const val PREFS_NAME = "locus_plugin"
        private const val KEY_ENABLE_HEADLESS = "enableHeadless"

        fun enqueueWork(context: Context, intent: Intent) {
            enqueueWork(context, HeadlessService::class.java, JOB_ID, intent)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onHandleWork(intent: Intent) {
        val dispatcherHandle = intent.getLongExtra("dispatcher", 0L)
        val callbackHandle = intent.getLongExtra("callback", 0L)
        
        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            Log.d(TAG, "Invalid dispatcher ($dispatcherHandle) or callback ($callbackHandle) handle, skipping")
            return
        }

        // Check if headless mode is enabled
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val headlessEnabled = prefs.getBoolean(KEY_ENABLE_HEADLESS, false)
        if (!headlessEnabled) {
            Log.d(TAG, "Headless mode not enabled, skipping")
            return
        }

        val rawEvent = intent.getStringExtra("event")
        
        // Use CountDownLatch to wait for main thread operations
        val latch = CountDownLatch(1)
        
        // Flutter Engine must be created on main thread
        mainHandler.post {
            try {
                var engine = FlutterEngineCache.getInstance().get(CACHE_KEY)
                if (engine == null) {
                    val injector = FlutterInjector.instance()
                    injector.flutterLoader().startInitialization(applicationContext)
                    injector.flutterLoader().ensureInitializationComplete(applicationContext, null)
                    val appBundlePath = injector.flutterLoader().findAppBundlePath()

                    val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
                    if (info == null) {
                        Log.w(TAG, "Could not lookup callback information for dispatcher handle: $dispatcherHandle")
                        latch.countDown()
                        return@post
                    }

                    try {
                        engine = FlutterEngine(applicationContext)
                        val callback = DartExecutor.DartCallback(
                            assets,
                            appBundlePath,
                            info
                        )
                        engine.dartExecutor.executeDartCallback(callback)
                        FlutterEngineCache.getInstance().put(CACHE_KEY, engine)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to create or initialize FlutterEngine: ${e.message}")
                        latch.countDown()
                        return@post
                    }
                }

                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                val args = mapOf(
                    "callbackHandle" to callbackHandle,
                    "event" to (rawEvent ?: "{\"type\":\"boot\"}")
                )
                channel.invokeMethod("headlessEvent", args)

                // Schedule engine cleanup
                CoroutineScope(Dispatchers.Main).launch {
                    delay(ENGINE_IDLE_TIMEOUT_MS)
                    FlutterEngineCache.getInstance().get(CACHE_KEY)?.let { cached ->
                        try {
                            cached.destroy()
                        } catch (e: Exception) {
                            Log.w(TAG, "Error destroying cached engine: ${e.message}")
                        }
                        FlutterEngineCache.getInstance().remove(CACHE_KEY)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unhandled error in headless service: ${e.message}")
            } finally {
                latch.countDown()
            }
        }
        
        // Wait for main thread work to complete before returning (with timeout)
        try {
            if (!latch.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                Log.w(TAG, "Timed out waiting for FlutterEngine initialization")
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            Log.w(TAG, "Interrupted while waiting for FlutterEngine initialization")
        }
    }
}
