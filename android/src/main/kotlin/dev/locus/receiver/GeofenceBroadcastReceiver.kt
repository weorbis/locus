package dev.locus.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import dev.locus.LocusPlugin
import dev.locus.service.HeadlessService
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val event = GeofencingEvent.fromIntent(intent)
        if (event == null) {
            Log.w(TAG, "GeofencingEvent is null")
            return
        }
        if (event.hasError()) {
            Log.w(TAG, "GeofencingEvent error: ${event.errorCode}")
            return
        }

        val transition = event.geofenceTransition
        val action = when (transition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "dwell"
            else -> "unknown"
        }

        val ids = event.triggeringGeofences?.map { it.requestId } ?: emptyList()

        val payload = JSONObject().apply {
            try {
                put("action", action)
                put("identifiers", JSONArray(ids))
                event.triggeringLocation?.let { loc ->
                    val location = JSONObject().apply {
                        put("latitude", loc.latitude)
                        put("longitude", loc.longitude)
                        put("accuracy", loc.accuracy)
                    }
                    put("location", location)
                }
            } catch (e: JSONException) {
                Log.e(TAG, "Failed to encode geofence event", e)
            }
        }

        val preferences = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

        // Check privacy mode
        if (preferences.getBoolean("bg_privacy_mode", false)) {
            return
        }

        preferences.edit()
            .putString(LocusPlugin.KEY_GEOFENCE_EVENT, payload.toString())
            .apply()

        // Dispatch to headless service if enabled
        if (preferences.getBoolean("bg_enable_headless", false)) {
            val dispatcher = preferences.getLong("bg_headless_dispatcher", 0L)
            val callback = preferences.getLong("bg_headless_callback", 0L)
            if (dispatcher != 0L && callback != 0L) {
                val eventPayload = try {
                    JSONObject().apply {
                        put("type", "geofence")
                        put("data", payload)
                    }
                } catch (e: JSONException) {
                    Log.w(TAG, "Failed to wrap geofence event for headless", e)
                    null
                }

                eventPayload?.let {
                    val headlessIntent = Intent(context, HeadlessService::class.java).apply {
                        putExtra("dispatcher", dispatcher)
                        putExtra("callback", callback)
                        putExtra("event", it.toString())
                    }
                    HeadlessService.enqueueWork(context, headlessIntent)
                }
            }
        }
    }
}
