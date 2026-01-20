package dev.locus.core

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.locus.service.HeadlessValidationService
import org.json.JSONArray
import org.json.JSONObject

/**
 * Dispatcher for headless pre-sync validation.
 * 
 * When the Flutter app is terminated but location sync is needed,
 * this dispatcher invokes a registered Dart callback to validate
 * locations before syncing. This allows business logic validation
 * even when the app UI is not running.
 */
class HeadlessValidationDispatcher(
    private val context: Context,
    private val config: ConfigManager,
    private val prefs: SharedPreferences?
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Validates locations and extras via headless callback.
     * 
     * @param locations List of location data to validate
     * @param extras Additional metadata for validation
     * @param callback Callback with validation result (true = proceed, false = abort)
     * @param timeoutMs Maximum time to wait for validation response
     */
    fun validate(
        locations: List<Map<String, Any>>,
        extras: Map<String, Any>,
        callback: (Boolean) -> Unit,
        timeoutMs: Long = 10_000L
    ) {
        if (!config.enableHeadless || prefs == null) {
            Log.d(TAG, "Headless disabled or no prefs, allowing sync")
            callback(true)
            return
        }

        val dispatcher = prefs.getLong(KEY_VALIDATION_DISPATCHER, 0L)
        val validationCallback = prefs.getLong(KEY_VALIDATION_CALLBACK, 0L)

        // If no validation callback registered, allow sync by default
        if (dispatcher == 0L || validationCallback == 0L) {
            Log.d(TAG, "No validation callback registered, allowing sync")
            callback(true)
            return
        }

        runCatching {
            val locationsJson = JSONArray().apply {
                locations.forEach { loc ->
                    put(JSONObject(loc))
                }
            }

            val extrasJson = JSONObject(extras)

            val payload = JSONObject().apply {
                put("type", "validatePreSync")
                put("locations", locationsJson)
                put("extras", extrasJson)
            }

            val intent = Intent(context, HeadlessValidationService::class.java).apply {
                putExtra("dispatcher", dispatcher)
                putExtra("callback", validationCallback)
                putExtra("payload", payload.toString())
                putExtra("timeoutMs", timeoutMs)
            }

            HeadlessValidationService.enqueueWork(context, intent) { result ->
                mainHandler.post { callback(result) }
            }
        }.onFailure { e ->
            Log.e(TAG, "Failed to dispatch validation: ${e.message}")
            // Proceed with sync on error to avoid blocking permanently
            callback(true)
        }
    }

    /**
     * Checks if headless validation is available.
     */
    fun isAvailable(): Boolean {
        if (!config.enableHeadless || prefs == null) return false
        val dispatcher = prefs.getLong(KEY_VALIDATION_DISPATCHER, 0L)
        val validationCallback = prefs.getLong(KEY_VALIDATION_CALLBACK, 0L)
        return dispatcher != 0L && validationCallback != 0L
    }

    companion object {
        private const val TAG = "locus.HeadlessValidation"
        const val KEY_VALIDATION_DISPATCHER = "bg_headless_validation_dispatcher"
        const val KEY_VALIDATION_CALLBACK = "bg_headless_validation_callback"
    }
}
