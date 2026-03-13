package dev.locus.core

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.locus.service.HeadlessHeadersService

class HeadlessHeadersDispatcher(
    private val context: Context,
    private val config: ConfigManager,
    private val prefs: SharedPreferences?,
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun refreshHeaders(
        callback: (Map<String, String>?) -> Unit,
        timeoutMs: Long = 10_000L,
    ) {
        if (!config.enableHeadless || prefs == null) {
            callback(null)
            return
        }

        val dispatcher = prefs.getLong(KEY_HEADERS_DISPATCHER, 0L)
        val headersCallback = prefs.getLong(KEY_HEADERS_CALLBACK, 0L)
        if (dispatcher == 0L || headersCallback == 0L) {
            callback(null)
            return
        }

        runCatching {
            val intent = Intent(context, HeadlessHeadersService::class.java).apply {
                putExtra("dispatcher", dispatcher)
                putExtra("callback", headersCallback)
                putExtra("timeoutMs", timeoutMs)
            }

            HeadlessHeadersService.enqueueWork(context, intent) { headers ->
                mainHandler.post { callback(headers) }
            }
        }.onFailure { error ->
            Log.e(TAG, "Failed to dispatch headless headers refresh: ${error.message}")
            callback(null)
        }
    }

    fun isAvailable(): Boolean {
        if (!config.enableHeadless || prefs == null) return false
        val dispatcher = prefs.getLong(KEY_HEADERS_DISPATCHER, 0L)
        val callback = prefs.getLong(KEY_HEADERS_CALLBACK, 0L)
        return dispatcher != 0L && callback != 0L
    }

    companion object {
        private const val TAG = "locus.HeadlessHeaders"
        const val KEY_HEADERS_DISPATCHER = "bg_headless_headers_dispatcher"
        const val KEY_HEADERS_CALLBACK = "bg_headless_headers_callback"
    }
}
