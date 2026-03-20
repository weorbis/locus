package dev.locus.core

import dev.locus.activity.MotionManager
import dev.locus.geofence.GeofenceManager
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

class GeofenceEventProcessor(
    private val config: ConfigManager,
    private val motionManager: MotionManager,
    private val geofenceManager: GeofenceManager,
    private val stateManager: StateManager,
    private val syncManager: SyncManager,
    private val eventDispatcher: EventDispatcher,
    private val autoSyncChecker: AutoSyncChecker
) {
    fun handle(raw: String) {
        val obj = try {
            JSONObject(raw)
        } catch (e: JSONException) {
            throw e
        }
        handle(obj)
    }

    fun handle(obj: JSONObject) {
        val event = buildGeofenceEvent(obj) ?: return
        val locationPayload = extractLocationPayload(event)

        locationPayload?.let { payload ->
            if (PersistencePolicy.shouldPersist(config, "geofence")) {
                stateManager.storeLocationPayload(payload, config.maxDaysToPersist, config.maxRecordsToPersist)
            }
            if (config.autoSync && !config.httpUrl.isNullOrEmpty() && autoSyncChecker.isAutoSyncAllowed()) {
                if (config.batchSync) {
                    syncManager.attemptBatchSync()
                } else {
                    syncManager.syncNow(payload)
                }
            }
        }

        eventDispatcher.sendEvent(event)
    }

    private fun buildGeofenceEvent(obj: JSONObject): Map<String, Any>? {
        val action = obj.optString("action", "unknown")
        val identifiers = mutableListOf<String>()

        obj.optJSONArray("identifiers")?.let { ids ->
            for (i in 0 until ids.length()) {
                ids.optString(i)?.let { identifiers.add(it) }
            }
        }

        val geofenceData = identifiers.firstOrNull()
            ?.let { geofenceManager.getGeofenceSync(it) }
            ?: mutableMapOf<String, Any?>("identifier" to (identifiers.firstOrNull() ?: "unknown"))

        val location = obj.optJSONObject("location")?.let { loc ->
            mapOf(
                "uuid" to UUID.randomUUID().toString(),
                "timestamp" to Instant.now().toString(),
                "coords" to loc.toMap(),
                "event" to "geofence",
                "is_moving" to motionManager.isMoving,
                "odometer" to stateManager.odometerValue,
                "extras" to config.extras.toMap()
            )
        }

        val payload = buildMap<String, Any> {
            put("geofence", geofenceData)
            put("action", action)
            location?.let { put("location", it) }
        }

        return mapOf(
            "type" to "geofence",
            "data" to payload
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun extractLocationPayload(event: Map<String, Any>): Map<String, Any>? {
        val data = event["data"] as? Map<String, Any>
        val location = data?.get("location") as? Map<String, Any?>
        return location
            ?.filterValues { it != null }
            ?.mapValues { it.value as Any }
    }

    private fun JSONObject.toMap(): Map<String, Any> = buildMap {
        // Make a defensive copy of keys to prevent ConcurrentModificationException
        val keyList = keys().asSequence().toList()
        keyList.forEach { key ->
            opt(key)?.takeIf { it != JSONObject.NULL }?.let { put(key, it) }
        }
    }
}
