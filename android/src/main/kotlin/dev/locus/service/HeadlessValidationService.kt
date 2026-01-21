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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Service for headless pre-sync validation.
 * 
 * Runs validation callbacks in a background Flutter engine when the app
 * is terminated. This allows custom business logic to approve or reject
 * location syncs even without the main app running.
 */
class HeadlessValidationService : JobIntentService() {

    companion object {
        private const val TAG = "locus.ValidationService"
        private const val CHANNEL = "locus/headless_validation"
        private const val CACHE_KEY = "locus_validation_engine"
        private const val JOB_ID = 197812513
        private const val ENGINE_IDLE_TIMEOUT_MS = 30_000L
        private const val DEFAULT_TIMEOUT_MS = 10_000L
        private const val PREFS_NAME = "locus_plugin"
        private const val KEY_ENABLE_HEADLESS = "enableHeadless"

        private val pendingCallbacks = mutableMapOf<String, (Boolean) -> Unit>()
        private var callbackCounter = 0

        fun enqueueWork(context: Context, intent: Intent, callback: (Boolean) -> Unit) {
            val callbackId = "validation_${++callbackCounter}"
            pendingCallbacks[callbackId] = callback
            intent.putExtra("callbackId", callbackId)
            enqueueWork(context, HeadlessValidationService::class.java, JOB_ID, intent)
        }

        internal fun resolveCallback(callbackId: String, result: Boolean) {
            pendingCallbacks.remove(callbackId)?.invoke(result)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onHandleWork(intent: Intent) {
        val dispatcherHandle = intent.getLongExtra("dispatcher", 0L)
        val callbackHandle = intent.getLongExtra("callback", 0L)
        val callbackId = intent.getStringExtra("callbackId") ?: ""
        val timeoutMs = intent.getLongExtra("timeoutMs", DEFAULT_TIMEOUT_MS)

        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            Log.d(TAG, "Invalid dispatcher ($dispatcherHandle) or callback ($callbackHandle) handle")
            resolveCallback(callbackId, true) // Allow by default
            return
        }

        // Check if headless mode is enabled
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val headlessEnabled = prefs.getBoolean(KEY_ENABLE_HEADLESS, false)
        if (!headlessEnabled) {
            Log.d(TAG, "Headless mode disabled, allowing sync")
            resolveCallback(callbackId, true)
            return
        }

        val payload = intent.getStringExtra("payload") ?: "{}"
        val result = AtomicBoolean(true) // Default to allow
        val latch = CountDownLatch(1)

        mainHandler.post {
            try {
                var engine = FlutterEngineCache.getInstance().get(CACHE_KEY)
                if (engine == null) {
                    engine = createFlutterEngine(dispatcherHandle)
                    if (engine == null) {
                        latch.countDown()
                        return@post
                    }
                    FlutterEngineCache.getInstance().put(CACHE_KEY, engine)
                }

                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                
                val args = mapOf(
                    "callbackHandle" to callbackHandle,
                    "payload" to payload
                )

                channel.invokeMethod("validatePreSync", args, object : MethodChannel.Result {
                    override fun success(resultValue: Any?) {
                        val validated = resultValue as? Boolean ?: true
                        Log.d(TAG, "Validation result: $validated")
                        result.set(validated)
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.e(TAG, "Validation error: $code - $message")
                        result.set(true) // Allow on error
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        Log.d(TAG, "Validation not implemented, allowing sync")
                        result.set(true)
                        latch.countDown()
                    }
                })

                // Schedule engine cleanup after idle timeout
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
                Log.e(TAG, "Error in validation service: ${e.message}")
                latch.countDown()
            }
        }

        // Wait for validation result with timeout
        try {
            if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) {
                Log.w(TAG, "Validation timed out after ${timeoutMs}ms, allowing sync")
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            Log.w(TAG, "Validation interrupted")
        }

        resolveCallback(callbackId, result.get())
    }

    private fun createFlutterEngine(dispatcherHandle: Long): FlutterEngine? {
        return try {
            val injector = FlutterInjector.instance()
            injector.flutterLoader().startInitialization(applicationContext)
            injector.flutterLoader().ensureInitializationComplete(applicationContext, null)
            val appBundlePath = injector.flutterLoader().findAppBundlePath()

            val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
            if (info == null) {
                Log.w(TAG, "Could not lookup callback info for handle: $dispatcherHandle")
                return null
            }

            val engine = FlutterEngine(applicationContext)
            val callback = DartExecutor.DartCallback(assets, appBundlePath, info)
            engine.dartExecutor.executeDartCallback(callback)
            engine
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create FlutterEngine: ${e.message}")
            null
        }
    }
}
