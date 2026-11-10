package dev.locus.core

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.locus.LocusPlugin
import dev.locus.location.Odometer
import dev.locus.storage.EncryptedStorage
import dev.locus.storage.LocationStore
import dev.locus.storage.LogStore
import dev.locus.storage.QueueStore
import dev.locus.storage.StorageUnavailableException
import dev.locus.storage.StoredLocationQuery
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

class StateManager(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

    val locationStore: LocationStore = LocationStore(context)
    val queueStore: QueueStore = QueueStore(context)
    val logStore: LogStore = LogStore(context)

    private class HeldLocation(val payload: Map<String, Any>, val maxDays: Int, val maxRecords: Int)

    /** Fixes that could not be written because storage was unavailable; in memory only, oldest first. */
    private val heldLocations = ArrayDeque<HeldLocation>()
    private val mainHandler = Handler(Looper.getMainLooper())
    val odometer: Odometer = Odometer(context)

    var odometerValue: Double
        get() = odometer.distance
        set(value) {
            odometer.setDistance(value)
        }

    fun updateOdometer(location: Location) {
        odometer.update(location)
    }

    /**
     * Runs [block] once the encrypted stores are ready, without ever blocking the caller.
     * Use it at main-thread entry points that persist or sync location data.
     */
    fun whenStorageReady(block: () -> Unit) {
        EncryptedStorage.runWhenReady(context, block)
    }

    fun clearLocations() {
        locationStore.clear()
        synchronized(heldLocations) { heldLocations.clear() }
    }

    fun getStoredLocations(limit: Int): List<Map<String, Any>> {
        flushHeldLocations()
        return locationStore.readLocations(limit)
            .mapNotNull { record -> buildPayloadFromRecord(record).takeIf { it.isNotEmpty() } }
    }

    internal fun queryStoredLocations(query: StoredLocationQuery): List<Map<String, Any>> =
        locationStore.queryLocations(query).map { record -> buildPayloadFromRecord(record) }

    /**
     * Writes [payload], after any fixes held earlier. If storage is unavailable the fix is held (at most
     * [MAX_HELD_LOCATIONS], oldest dropped first) and written by the next call that finds storage ready.
     * Main thread only: it never waits for storage preparation.
     */
    fun storeLocationPayload(payload: Map<String, Any>, maxDays: Int, maxRecords: Int) {
        synchronized(heldLocations) {
            heldLocations.addLast(HeldLocation(payload, maxDays, maxRecords))
            while (heldLocations.size > MAX_HELD_LOCATIONS) {
                heldLocations.removeFirst()
                Log.w(TAG, "Held location limit of $MAX_HELD_LOCATIONS exceeded; dropped the oldest unsaved fix")
            }
        }
        flushHeldLocations()
    }

    /**
     * Writes held fixes in order, at most [HELD_FLUSH_BATCH_SIZE] per main-thread turn so a long backlog
     * cannot stall the UI; the rest is posted to the next turn. Stops at the first fix storage still
     * cannot take. Main thread only.
     */
    fun flushHeldLocations() {
        val remaining = synchronized(heldLocations) {
            repeat(HELD_FLUSH_BATCH_SIZE) {
                val next = heldLocations.firstOrNull() ?: return
                try {
                    locationStore.insertPayload(next.payload, next.maxDays, next.maxRecords)
                } catch (error: StorageUnavailableException) {
                    Log.w(TAG, "Storage unavailable; holding ${heldLocations.size} unsaved fix(es): ${error.message}")
                    return
                }
                heldLocations.removeFirst()
            }
            heldLocations.size
        }
        if (remaining > 0) mainHandler.post(::flushHeldLocations)
    }

    fun enqueue(
        payload: Map<String, Any>,
        type: String,
        idempotencyKey: String,
        maxDays: Int,
        maxRecords: Int
    ): String = queueStore.insertPayload(payload, type, idempotencyKey, maxDays, maxRecords)

    fun getQueue(limit: Int): List<Map<String, Any>> =
        buildQueuePayload(queueStore.readQueue(limit))

    fun clearQueue() {
        queueStore.clear()
    }

    fun appendLog(level: String, message: String, maxDays: Int) {
        logStore.append(level, message, maxDays)
    }

    fun readLogEntries(limit: Int): List<Map<String, Any>> =
        logStore.readEntries(limit)

    fun storeTripState(tripState: Map<String, Any>) {
        prefs.edit().putString(KEY_TRIP_STATE, JSONObject(tripState).toString()).apply()
    }

    fun readTripState(): Map<String, Any>? {
        val tripJson = prefs.getString(KEY_TRIP_STATE, null) ?: return null
        return try {
            JSONObject(tripJson).toMap()
        } catch (e: JSONException) {
            null
        }
    }

    fun clearTripState() {
        prefs.edit().remove(KEY_TRIP_STATE).apply()
    }

    private fun buildPayloadFromRecord(record: Map<String, Any>?): Map<String, Any> {
        if (record == null) return emptyMap()

        val latitude = (record["latitude"] as? Number)?.toDouble() ?: 0.0
        val longitude = (record["longitude"] as? Number)?.toDouble() ?: 0.0
        val accuracy = (record["accuracy"] as? Number)?.toDouble() ?: 0.0
        val speed = (record["speed"] as? Number)?.toDouble() ?: 0.0
        val heading = (record["heading"] as? Number)?.toDouble() ?: 0.0
        val altitude = (record["altitude"] as? Number)?.toDouble() ?: 0.0

        val coords = mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracy" to accuracy,
            "speed" to speed,
            "heading" to heading,
            "altitude" to altitude
        )

        val activity = mutableMapOf<String, Any>().apply {
            (record["activity_type"] as? String)?.let { put("type", it) }
            (record["activity_confidence"] as? Number)?.let { put("confidence", it.toInt()) }
        }

        val timestamp = (record["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis()
        val uuid = (record["id"] as? String) ?: UUID.randomUUID().toString()

        return mutableMapOf<String, Any>(
            "uuid" to uuid,
            "timestamp" to Instant.ofEpochMilli(timestamp).toString(),
            "coords" to coords
        ).apply {
            if (activity.isNotEmpty()) put("activity", activity)
            record["event"]?.let { put("event", it) }
            record["is_moving"]?.let { put("is_moving", it) }
            record["odometer"]?.let { put("odometer", it) }
            when (val rawExtras = record["extras"]) {
                is Map<*, *> -> put("extras", rawExtras)
                else -> (record["extras_json"] as? String)?.takeIf { it.isNotBlank() }?.let { extrasJson ->
                    try {
                        put("extras", JSONObject(extrasJson).toMap())
                    } catch (_: JSONException) {
                    }
                }
            }
        }
    }

    private fun buildQueuePayload(records: List<Map<String, Any>>): List<Map<String, Any>> =
        records.map { record ->
            buildMap<String, Any> {
                record["id"]?.let { put("id", it) }

                (record["createdAt"] as? Number)?.let { createdAt ->
                    put("createdAt", Instant.ofEpochMilli(createdAt.toLong()).toString())
                }

                (record["retryCount"] as? Number)?.let { retryCount ->
                    put("retryCount", retryCount.toInt())
                }

                (record["nextRetryAt"] as? Number)?.let { nextRetryAt ->
                    put("nextRetryAt", Instant.ofEpochMilli(nextRetryAt.toLong()).toString())
                }

                (record["idempotencyKey"] as? String)?.let { put("idempotencyKey", it) }
                (record["type"] as? String)?.let { put("type", it) }

                (record["payload"] as? String)?.let { payloadJson ->
                    try {
                        put("payload", QueueStore.parsePayload(payloadJson))
                    } catch (ignored: JSONException) {
                    }
                }
            }
        }

    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val names = names() ?: return map

        for (i in 0 until names.length()) {
            val key = names.optString(i)
            when (val value = opt(key)) {
                is JSONObject -> map[key] = value.toMap()
                is JSONArray -> map[key] = value.toList()
                JSONObject.NULL -> { /* skip null values */ }
                else -> value?.let { map[key] = it }
            }
        }
        return map
    }

    private fun JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until length()) {
            when (val value = opt(i)) {
                is JSONObject -> list.add(value.toMap())
                is JSONArray -> list.add(value.toList())
                JSONObject.NULL -> { /* skip null values */ }
                else -> value?.let { list.add(it) }
            }
        }
        return list
    }

    companion object {
        private const val TAG = "locus.StateManager"
        private const val MAX_HELD_LOCATIONS = 1_000
        private const val HELD_FLUSH_BATCH_SIZE = 50
        private const val KEY_TRIP_STATE = "bg_trip_state"
    }
}
