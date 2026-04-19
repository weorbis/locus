package dev.locus.core

import android.annotation.SuppressLint
import android.location.Location
import dev.locus.activity.MotionManager
import dev.locus.location.LocationClient

class LocationTracker(
    private val config: ConfigManager,
    private val locationClient: LocationClient,
    private val motionManager: MotionManager,
    private val stateManager: StateManager,
    private val eventProcessor: LocationEventProcessor,
    private val payloadBuilder: LocationPayloadBuilder,
    private val locationUpdateProcessor: LocationUpdateProcessor,
    private val trackingLifecycleController: TrackingLifecycleController,
    private val trackingConfigApplier: TrackingConfigApplier
) {
    private val heartbeatScheduler = HeartbeatScheduler()
    private var lastLocation: Location? = null
    private var enabled = false

    init {
        locationClient.setListener(object : LocationClient.LocationClientListener {
            override fun onLocation(location: Location) {
                lastLocation = location
                locationUpdateProcessor.handleLocation(location)
            }

            override fun onLocationError(code: String, message: String) {
                locationUpdateProcessor.handleError(message)
            }
        })

        motionManager.setListener(object : MotionManager.MotionListener {
            override fun onMotionChange(isMoving: Boolean) {
                locationClient.updateRequest(isMoving)
                trackingLifecycleController.onMotionChange(isMoving)
                lastLocation?.let { emitLocationEvent(it, "motionchange") }
            }

            override fun onActivityChange(type: String, confidence: Int) {
                lastLocation?.let { emitLocationEvent(it, "activitychange") }
            }
        })
    }

    fun isEnabled(): Boolean = enabled

    fun isMoving(): Boolean = motionManager.isMoving

    fun getLastLocation(): Location? = lastLocation

    fun buildState(): Map<String, Any> = buildMap {
        put("enabled", enabled)
        put("isMoving", motionManager.isMoving)
        put("odometer", stateManager.odometerValue)
        lastLocation?.let { location ->
            put("location", payloadBuilder.build(location, "location"))
        }
    }

    fun buildLocationPayload(location: Location, eventName: String): Map<String, Any> {
        return payloadBuilder.build(location, eventName)
    }

    fun applyConfig(configMap: Map<String, Any>?) {
        trackingConfigApplier.apply(configMap, enabled)
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        if (enabled) return

        if (!trackingLifecycleController.start()) {
            return
        }

        enabled = true
        config.setTrackingActive(true)
        startHeartbeat()
    }

    fun stopTracking() {
        if (!enabled) return

        enabled = false
        config.setTrackingActive(false)
        trackingLifecycleController.stop()
        stopHeartbeat()
    }

    fun changePace(moving: Boolean) {
        motionManager.setPace(moving)
    }

    fun emitScheduleEvent() {
        if (!config.scheduleEnabled) return
        lastLocation?.let { emitLocationEvent(it, "configManager.schedule") }
    }

    fun syncNow() {
        val payload = lastLocation?.let { payloadBuilder.build(it, "location") }
        eventProcessor.syncNow(payload)
    }

    fun startHeartbeat() {
        heartbeatScheduler.start(config.heartbeatIntervalSeconds) {
            if (enabled) {
                lastLocation?.let { emitLocationEvent(it, "heartbeat") }
            }
        }
    }

    fun stopHeartbeat() {
        heartbeatScheduler.stop()
    }

    /**
     * Restarts the heartbeat with the current configuration.
     * Call when heartbeat interval changes dynamically.
     */
    fun restartHeartbeat() {
        heartbeatScheduler.restart(config.heartbeatIntervalSeconds) {
            if (enabled) {
                lastLocation?.let { emitLocationEvent(it, "heartbeat") }
            }
        }
    }

    private fun emitLocationEvent(location: Location, eventName: String) {
        val payload = payloadBuilder.build(location, eventName)
        eventProcessor.dispatch(eventName, payload)
    }

    /**
     * Full teardown: stops tracking and shuts the lifecycle controller down. Call
     * this when the owning container is itself shutting down. Not called during
     * normal FlutterEngine detach — the container outlives engine detach and the
     * tracker keeps running so the foreground service survives UI teardown.
     */
    fun releaseAll() {
        stopTracking()
        trackingLifecycleController.shutdown()
    }
}
