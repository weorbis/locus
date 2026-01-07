package dev.locus.service

import android.content.Context
import android.content.Intent
import androidx.core.app.JobIntentService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.*

class HeadlessService : JobIntentService() {

    companion object {
        private const val CHANNEL = "locus/headless"
        private const val CACHE_KEY = "locus_headless_engine"
        private const val JOB_ID = 197812512
        private const val ENGINE_IDLE_TIMEOUT_MS = 60_000L

        fun enqueueWork(context: Context, intent: Intent) {
            enqueueWork(context, HeadlessService::class.java, JOB_ID, intent)
        }
    }

    override fun onHandleWork(intent: Intent) {
        val dispatcherHandle = intent.getLongExtra("dispatcher", 0L)
        val callbackHandle = intent.getLongExtra("callback", 0L)
        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            return
        }

        var engine = FlutterEngineCache.getInstance().get(CACHE_KEY)
        if (engine == null) {
            val injector = FlutterInjector.instance()
            injector.flutterLoader().startInitialization(applicationContext)
            injector.flutterLoader().ensureInitializationComplete(applicationContext, null)
            val appBundlePath = injector.flutterLoader().findAppBundlePath()

            val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
                ?: return

            engine = FlutterEngine(applicationContext)
            val callback = DartExecutor.DartCallback(
                assets,
                appBundlePath,
                info
            )
            engine.dartExecutor.executeDartCallback(callback)
            FlutterEngineCache.getInstance().put(CACHE_KEY, engine)
        }

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        val rawEvent = intent.getStringExtra("event")
        val args = mapOf(
            "callbackHandle" to callbackHandle,
            "event" to (rawEvent ?: "{\"type\":\"boot\"}")
        )
        channel.invokeMethod("headlessEvent", args)

        // Use coroutines instead of deprecated Handler
        CoroutineScope(Dispatchers.Main).launch {
            delay(ENGINE_IDLE_TIMEOUT_MS)
            FlutterEngineCache.getInstance().get(CACHE_KEY)?.let { cached ->
                cached.destroy()
                FlutterEngineCache.getInstance().remove(CACHE_KEY)
            }
        }
    }
}
