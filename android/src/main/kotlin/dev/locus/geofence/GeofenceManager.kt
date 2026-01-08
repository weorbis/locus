package dev.locus.geofence

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import dev.locus.LocusPlugin
import dev.locus.receiver.GeofenceBroadcastReceiver
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class GeofenceManager(
    private val context: Context,
    private val listener: GeofenceListener?
) {
    private val geofencingClient: GeofencingClient =
        LocationServices.getGeofencingClient(context)

    private val prefs by lazy {
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)
    }

    private var maxMonitoredGeofences: Int = 0
    private var geofencePendingIntent: PendingIntent? = null

    fun interface GeofenceListener {
        fun onGeofencesChanged(addedIds: List<String>, removedIds: List<String>)
    }

    fun setMaxMonitoredGeofences(max: Int) {
        maxMonitoredGeofences = max
    }

    @SuppressLint("MissingPermission")
    fun addGeofence(geofenceMap: Map<String, Any>, result: MethodChannel.Result) {
        try {
            val geofence = buildGeofence(geofenceMap)
            val identifier = geofenceMap["identifier"] as? String

            val request = GeofencingRequest.Builder().apply {
                val notifyOnEntry = geofenceMap["notifyOnEntry"] as? Boolean ?: true
                setInitialTrigger(
                    if (notifyOnEntry) GeofencingRequest.INITIAL_TRIGGER_ENTER else 0
                )
                addGeofence(geofence)
            }.build()

            geofencePendingIntent = createGeofencePendingIntent()

            geofencingClient.addGeofences(request, geofencePendingIntent!!)
                .addOnSuccessListener {
                    storeGeofence(geofenceMap)
                    enforceMaxMonitoredGeofences()
                    identifier?.let { id ->
                        listener?.onGeofencesChanged(listOf(id), emptyList())
                    }
                    result.success(true)
                }
                .addOnFailureListener { e ->
                    result.error("GEOFENCE_ERROR", e.message, null)
                }
        } catch (e: Exception) {
            result.error("GEOFENCE_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    fun addGeofences(geofences: List<Any>, result: MethodChannel.Result) {
        try {
            val geofenceList = mutableListOf<Geofence>()
            val stored = readGeofenceStore()
            val addedIds = mutableListOf<String>()
            var initialTrigger = 0

            geofences.forEach { obj ->
                val map = obj.asMap() ?: return@forEach
                geofenceList.add(buildGeofence(map))
                (map["identifier"] as? String)?.let { addedIds.add(it) }
                stored.put(JSONObject(map))

                // Respect per-geofence initial trigger preferences
                val notifyOnEntry = map["notifyOnEntry"] as? Boolean ?: true
                val notifyOnDwell = map["notifyOnDwell"] as? Boolean ?: false
                if (notifyOnEntry) {
                    initialTrigger = initialTrigger or GeofencingRequest.INITIAL_TRIGGER_ENTER
                }
                if (notifyOnDwell) {
                    initialTrigger = initialTrigger or GeofencingRequest.INITIAL_TRIGGER_DWELL
                }
            }

            val request = GeofencingRequest.Builder().apply {
                addGeofences(geofenceList)
                if (initialTrigger != 0) {
                    setInitialTrigger(initialTrigger)
                }
            }.build()

            geofencePendingIntent = createGeofencePendingIntent()

            geofencingClient.addGeofences(request, geofencePendingIntent!!)
                .addOnSuccessListener {
                    writeGeofenceStore(stored)
                    enforceMaxMonitoredGeofences()
                    if (addedIds.isNotEmpty()) {
                        listener?.onGeofencesChanged(addedIds, emptyList())
                    }
                    result.success(true)
                }
                .addOnFailureListener { e ->
                    result.error("GEOFENCE_ERROR", e.message, null)
                }
        } catch (e: Exception) {
            result.error("GEOFENCE_ERROR", e.message, null)
        }
    }

    fun removeGeofence(identifier: Any?, result: MethodChannel.Result) {
        val id = identifier as? String
        if (id == null) {
            result.error("INVALID_ARGUMENT", "Expected geofence identifier string", null)
            return
        }

        geofencingClient.removeGeofences(listOf(id))
            .addOnSuccessListener {
                removeGeofenceFromStore(id)
                listener?.onGeofencesChanged(emptyList(), listOf(id))
                result.success(true)
            }
            .addOnFailureListener { e ->
                result.error("GEOFENCE_ERROR", e.message, null)
            }
    }

    fun removeGeofences(result: MethodChannel.Result) {
        val stored = readGeofenceStore()
        val removedIds = extractIdentifiers(stored)

        geofencingClient.removeGeofences(createGeofencePendingIntent())
            .addOnSuccessListener {
                writeGeofenceStore(JSONArray())
                if (removedIds.isNotEmpty()) {
                    listener?.onGeofencesChanged(emptyList(), removedIds)
                }
                result.success(true)
            }
            .addOnFailureListener { e ->
                result.error("GEOFENCE_ERROR", e.message, null)
            }
    }

    fun getGeofence(identifier: Any?, result: MethodChannel.Result) {
        val id = identifier as? String
        if (id == null) {
            result.success(null)
            return
        }
        result.success(getGeofenceSync(id))
    }

    fun getGeofenceSync(identifier: String): Map<String, Any>? {
        val array = readGeofenceStore()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (identifier == obj.optString("identifier")) {
                return try {
                    obj.toMap()
                } catch (e: JSONException) {
                    null
                }
            }
        }
        return null
    }

    fun getGeofences(result: MethodChannel.Result) {
        val array = readGeofenceStore()
        val list = mutableListOf<Map<String, Any>>()

        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            try {
                list.add(obj.toMap())
            } catch (e: JSONException) {
                // ignore malformed entries
            }
        }
        result.success(list)
    }

    fun getGeofencesSync(): List<Map<String, Any>> {
        val array = readGeofenceStore()
        val list = mutableListOf<Map<String, Any>>()

        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            try {
                list.add(obj.toMap())
            } catch (e: JSONException) {
                // ignore malformed entries
            }
        }
        return list
    }

    fun geofenceExists(identifier: Any?, result: MethodChannel.Result) {
        val id = identifier as? String
        if (id == null) {
            result.error("INVALID_ARGUMENT", "Expected geofence identifier string", null)
            return
        }

        val array = readGeofenceStore()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (id == obj.optString("identifier")) {
                result.success(true)
                return
            }
        }
        result.success(false)
    }

    fun startGeofences(result: MethodChannel.Result) {
        startGeofencesInternal()
        result.success(true)
    }

    @SuppressLint("MissingPermission")
    fun startGeofencesInternal() {
        var stored = readGeofenceStore()

        if (maxMonitoredGeofences > 0 && stored.length() > maxMonitoredGeofences) {
            trimGeofenceStore(stored, stored.length() - maxMonitoredGeofences)
            stored = readGeofenceStore()
        }

        if (stored.length() == 0) return

        val geofences = mutableListOf<Geofence>()
        var initialTrigger = 0

        for (i in 0 until stored.length()) {
            val obj = stored.optJSONObject(i) ?: continue
            try {
                val map = obj.toMap()
                geofences.add(buildGeofence(map))

                // Respect per-geofence initial trigger preferences
                val notifyOnEntry = map["notifyOnEntry"] as? Boolean ?: true
                val notifyOnDwell = map["notifyOnDwell"] as? Boolean ?: false

                if (notifyOnEntry) {
                    initialTrigger = initialTrigger or GeofencingRequest.INITIAL_TRIGGER_ENTER
                }
                if (notifyOnDwell) {
                    initialTrigger = initialTrigger or GeofencingRequest.INITIAL_TRIGGER_DWELL
                }
            } catch (e: JSONException) {
                // Ignore malformed
            }
        }

        if (geofences.isEmpty()) return

        val request = GeofencingRequest.Builder().apply {
            addGeofences(geofences)
            if (initialTrigger != 0) {
                setInitialTrigger(initialTrigger)
            }
        }.build()

        geofencePendingIntent = createGeofencePendingIntent()
        val storedIds = extractIdentifiers(stored)

        geofencingClient.addGeofences(request, geofencePendingIntent!!)
            .addOnFailureListener {
                // Clean up persisted store so Dart stays in sync when geofencing cannot start
                writeGeofenceStore(JSONArray())
                if (storedIds.isNotEmpty()) {
                    listener?.onGeofencesChanged(emptyList(), storedIds)
                }
            }
    }

    private fun buildGeofence(map: Map<String, Any>): Geofence {
        val identifier = map["identifier"] as? String
            ?: throw IllegalArgumentException("Geofence 'identifier' is required and must be a String")

        val radius = (map["radius"] as? Number)?.toDouble()
            ?: throw IllegalArgumentException("Geofence 'radius' is required and must be a Number")

        val lat = (map["latitude"] as? Number)?.toDouble()
            ?: throw IllegalArgumentException("Geofence 'latitude' is required and must be a Number")

        val lon = (map["longitude"] as? Number)?.toDouble()
            ?: throw IllegalArgumentException("Geofence 'longitude' is required and must be a Number")

        val notifyOnEntry = map["notifyOnEntry"] as? Boolean ?: true
        val notifyOnExit = map["notifyOnExit"] as? Boolean ?: true
        val notifyOnDwell = map["notifyOnDwell"] as? Boolean ?: false
        val loiteringDelay = (map["loiteringDelay"] as? Number)?.toInt() ?: 0

        var transitionTypes = 0
        if (notifyOnEntry) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_ENTER
        if (notifyOnExit) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_EXIT
        if (notifyOnDwell) transitionTypes = transitionTypes or Geofence.GEOFENCE_TRANSITION_DWELL

        return Geofence.Builder().apply {
            setRequestId(identifier)
            setCircularRegion(lat, lon, radius.toFloat())
            setExpirationDuration(Geofence.NEVER_EXPIRE)
            setTransitionTypes(transitionTypes)
            if (notifyOnDwell && loiteringDelay > 0) {
                setLoiteringDelay(loiteringDelay)
            }
        }.build()
    }

    private fun storeGeofence(geofenceMap: Map<String, Any>) {
        val array = readGeofenceStore()
        array.put(JSONObject(geofenceMap))
        writeGeofenceStore(array)
    }

    private fun removeGeofenceFromStore(identifier: String) {
        val array = readGeofenceStore()
        val updated = JSONArray()

        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (identifier != obj.optString("identifier")) {
                updated.put(obj)
            }
        }
        writeGeofenceStore(updated)
    }

    private fun enforceMaxMonitoredGeofences() {
        if (maxMonitoredGeofences <= 0) return

        val stored = readGeofenceStore()
        val overflow = stored.length() - maxMonitoredGeofences
        if (overflow <= 0) return

        trimGeofenceStore(stored, overflow)
    }

    private fun trimGeofenceStore(stored: JSONArray, overflow: Int) {
        val removeIds = mutableListOf<String>()
        val remaining = JSONArray()

        for (i in 0 until stored.length()) {
            val obj = stored.optJSONObject(i) ?: continue
            if (i < overflow) {
                obj.readIdentifier()?.let { removeIds.add(it) }
            } else {
                remaining.put(obj)
            }
        }

        if (removeIds.isNotEmpty()) {
            geofencingClient.removeGeofences(removeIds)
            listener?.onGeofencesChanged(emptyList(), removeIds)
        }
        writeGeofenceStore(remaining)
    }

    private fun readGeofenceStore(): JSONArray {
        val raw = prefs.getString(KEY_GEOFENCE_STORE, "[]")
        return try {
            JSONArray(raw)
        } catch (e: JSONException) {
            JSONArray()
        }
    }

    private fun writeGeofenceStore(array: JSONArray) {
        prefs.edit().putString(KEY_GEOFENCE_STORE, array.toString()).apply()
    }

    private fun createGeofencePendingIntent(): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= 31) {
            // Geofencing requires FLAG_MUTABLE so the system can add geofence data to the intent
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    // Extension functions for JSON conversion
    @Suppress("UNCHECKED_CAST")
    private fun Any?.asMap(): Map<String, Any>? = this as? Map<String, Any>

    @Throws(JSONException::class)
    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        keys().forEach { key ->
            when (val value = get(key)) {
                is JSONArray -> map[key] = value.toList()
                is JSONObject -> map[key] = value.toMap()
                JSONObject.NULL -> { /* skip null values */ }
                else -> map[key] = value
            }
        }
        return map
    }

    @Throws(JSONException::class)
    private fun JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until length()) {
            when (val value = get(i)) {
                is JSONArray -> list.add(value.toList())
                is JSONObject -> list.add(value.toMap())
                JSONObject.NULL -> { /* skip null values */ }
                else -> list.add(value)
            }
        }
        return list
    }

    private fun extractIdentifiers(array: JSONArray): List<String> {
        return (0 until array.length()).mapNotNull { i ->
            array.optJSONObject(i)?.readIdentifier()
        }
    }

    private fun JSONObject.readIdentifier(): String? {
        val identifier = optString("identifier")
        return identifier.takeIf { it.isNotEmpty() }
    }

    companion object {
        private const val KEY_GEOFENCE_STORE = "bg_geofences"
    }
}
