package dev.locus.core

import android.location.Location
import android.os.Build
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
            "is_mock_provider" to location.isMockProvider(),
            "odometer" to stateManager.odometerValue,
            "extras" to configManager.extras.toMap()
        )
    }
}

internal fun Location.isMockProvider(): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        isMock
    } else {
        @Suppress("DEPRECATION")
        isFromMockProvider
    }
