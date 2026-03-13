package dev.locus.core

import android.location.Location
import dev.locus.activity.MotionManager
import java.time.Instant
import java.util.UUID

class LocationPayloadBuilder(
    private val configManager: ConfigManager,
    private val motionManager: MotionManager,
    private val stateManager: StateManager
) {
    fun build(location: Location, eventName: String): Map<String, Any> {
        val coords = mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to location.accuracy,
            "speed" to location.speed,
            "heading" to location.bearing,
            "altitude" to location.altitude
        )

        val activity = mapOf(
            "type" to motionManager.lastActivityType,
            "confidence" to motionManager.lastActivityConfidence
        )

        return mapOf(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to Instant.ofEpochMilli(location.time).toString(),
            "coords" to coords,
            "activity" to activity,
            "event" to eventName,
            "is_moving" to motionManager.isMoving,
            "odometer" to stateManager.odometerValue,
            "extras" to configManager.extras.toMap()
        )
    }
}
