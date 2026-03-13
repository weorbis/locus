@file:Suppress("DEPRECATION")

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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class HeadlessHeadersService : JobIntentService() {
    companion object {
        private const val TAG = "locus.HeadersService"
        private const val CHANNEL = "locus/headless_headers"
        private const val CACHE_KEY = "locus_headers_engine"
        private const val JOB_ID = 197812514
        private const val ENGINE_IDLE_TIMEOUT_MS = 30_000L
        private const val DEFAULT_TIMEOUT_MS = 10_000L
        private const val PREFS_NAME = "dev.locus.preferences"
        private const val KEY_ENABLE_HEADLESS = "bg_enable_headless"

        private val pendingCallbacks =
            java.util.concurrent.ConcurrentHashMap<String, (Map<String, String>?) -> Unit>()
        private val callbackCounter = AtomicInteger(0)

        fun enqueueWork(
            context: Context,
            intent: Intent,
            callback: (Map<String, String>?) -> Unit,
        ) {
            val callbackId = "headers_${callbackCounter.incrementAndGet()}"
            pendingCallbacks[callbackId] = callback
            intent.putExtra("callbackId", callbackId)
            enqueueWork(context, HeadlessHeadersService::class.java, JOB_ID, intent)
        }

        internal fun resolveCallback(callbackId: String, headers: Map<String, String>?) {
            pendingCallbacks.remove(callbackId)?.invoke(headers)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onHandleWork(intent: Intent) {
        val dispatcherHandle = intent.getLongExtra("dispatcher", 0L)
        val callbackHandle = intent.getLongExtra("callback", 0L)
        val callbackId = intent.getStringExtra("callbackId") ?: ""
        val timeoutMs = intent.getLongExtra("timeoutMs", DEFAULT_TIMEOUT_MS)

        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            resolveCallback(callbackId, null)
            return
        }

        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val headlessEnabled = prefs.getBoolean(KEY_ENABLE_HEADLESS, false)
        if (!headlessEnabled) {
            resolveCallback(callbackId, null)
            return
        }

        val result = AtomicReference<Map<String, String>?>(null)
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
                val args = mapOf("callbackHandle" to callbackHandle)
                channel.invokeMethod("getHeaders", args, object : MethodChannel.Result {
                    override fun success(resultValue: Any?) {
                        @Suppress("UNCHECKED_CAST")
                        result.set((resultValue as? Map<*, *>)?.entries?.mapNotNull { entry ->
                            val key = entry.key?.toString()
                            val value = entry.value?.toString()
                            if (key == null || value == null) null else key to value
                        }?.toMap())
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.e(TAG, "Headers callback error: $code - $message")
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                })

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
                Log.e(TAG, "Error in headers service: ${e.message}")
                latch.countDown()
            }
        }

        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
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
                ?: return null

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
