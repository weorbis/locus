package dev.locus.core

import android.content.Context
import android.content.SharedPreferences
import dev.locus.LocusPlugin
import java.util.concurrent.atomic.AtomicInteger

/**
 * Tracks runtime statistics for battery optimization and diagnostics.
 *
 * These metrics are persisted across sessions to provide accurate
 * long-term tracking statistics.
 */
class TrackingStats(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

    // In-memory counters for current session
    private var sessionLocationUpdates: Int = 0
    private val sessionSyncRequests = AtomicInteger(0)
    private var sessionTotalAccuracy: Double = 0.0
    private var sessionAccuracyCount: Int = 0
    private var sessionStartTime: Long = 0

    /**
     * Called when tracking starts.
     */
    fun onTrackingStart() {
        sessionStartTime = System.currentTimeMillis()
        sessionLocationUpdates = 0
        sessionSyncRequests.set(0)
        sessionTotalAccuracy = 0.0
        sessionAccuracyCount = 0

        // Accrue any dangling state time from a previous run, then reset the marker
        updateTimeByState(prefs.getBoolean(KEY_LAST_STATE_MOVING, false))

        // Always set a fresh session start marker for accurate session durations
        prefs.edit().putLong(KEY_TRACKING_START, sessionStartTime).apply()

        // Initialize state tracking
        prefs.edit()
            .putLong(KEY_LAST_STATE_CHANGE, sessionStartTime)
            .putBoolean(KEY_LAST_STATE_MOVING, false)
            .apply()
    }

    /**
     * Called when tracking stops.
     */
    @Synchronized
    fun onTrackingStop() {
        if (sessionStartTime > 0) {
            val totalUpdates = prefs.getInt(KEY_LOCATION_UPDATES, 0) + sessionLocationUpdates
            val totalSyncs = prefs.getInt(KEY_SYNC_REQUESTS, 0) + sessionSyncRequests.get()
            val totalAccuracy = prefs.getFloat(KEY_TOTAL_ACCURACY, 0f) + sessionTotalAccuracy.toFloat()
            val accuracyCount = prefs.getInt(KEY_ACCURACY_COUNT, 0) + sessionAccuracyCount
            val accumulatedMs = prefs.getLong(KEY_TRACKING_ACCUM, 0)
            val sessionMs = System.currentTimeMillis() - sessionStartTime
            val nextAccum = accumulatedMs + maxOf(sessionMs, 0)

            prefs.edit()
                .putInt(KEY_LOCATION_UPDATES, totalUpdates)
                .putInt(KEY_SYNC_REQUESTS, totalSyncs)
                .putFloat(KEY_TOTAL_ACCURACY, totalAccuracy)
                .putInt(KEY_ACCURACY_COUNT, accuracyCount)
                .putLong(KEY_TRACKING_ACCUM, nextAccum)
                .apply()

            // Update time by state
            updateTimeByState(prefs.getBoolean(KEY_LAST_STATE_MOVING, false))
        }
        sessionStartTime = 0
    }

    /**
     * Records a location update.
     */
    @Synchronized
    fun onLocationUpdate(accuracy: Float) {
        sessionLocationUpdates++
        if (accuracy > 0) {
            sessionTotalAccuracy += accuracy
            sessionAccuracyCount++
        }
    }

    /**
     * Records a sync request.
     */
    fun onSyncRequest() {
        sessionSyncRequests.incrementAndGet()
    }

    /**
     * Records a motion state change.
     */
    fun onMotionChange(isMoving: Boolean) {
        updateTimeByState(!isMoving) // Update time for previous state
        prefs.edit()
            .putLong(KEY_LAST_STATE_CHANGE, System.currentTimeMillis())
            .putBoolean(KEY_LAST_STATE_MOVING, isMoving)
            .apply()
    }

    /**
     * Records an accuracy downgrade event.
     */
    fun onAccuracyDowngrade() {
        val count = prefs.getInt(KEY_ACCURACY_DOWNGRADE, 0)
        prefs.edit().putInt(KEY_ACCURACY_DOWNGRADE, count + 1).apply()
    }

    /**
     * Records a GPS disabled event.
     */
    fun onGpsDisabled() {
        val count = prefs.getInt(KEY_GPS_DISABLED, 0)
        prefs.edit().putInt(KEY_GPS_DISABLED, count + 1).apply()
    }

    /**
     * Resets all statistics.
     */
    fun reset() {
        prefs.edit()
            .remove(KEY_LOCATION_UPDATES)
            .remove(KEY_SYNC_REQUESTS)
            .remove(KEY_TRACKING_START)
            .remove(KEY_TOTAL_ACCURACY)
            .remove(KEY_ACCURACY_COUNT)
            .remove(KEY_ACCURACY_DOWNGRADE)
            .remove(KEY_GPS_DISABLED)
            .remove(KEY_MOVING_TIME)
            .remove(KEY_STATIONARY_TIME)
            .remove(KEY_LAST_STATE_CHANGE)
            .remove(KEY_LAST_STATE_MOVING)
            .remove(KEY_TRACKING_ACCUM)
            .apply()

        sessionLocationUpdates = 0
        sessionSyncRequests.set(0)
        sessionTotalAccuracy = 0.0
        sessionAccuracyCount = 0
        sessionStartTime = 0
    }

    /**
     * Builds the battery stats map for the Dart layer.
     */
    fun buildStats(currentBatteryLevel: Int, isCharging: Boolean): Map<String, Any> {
        val now = System.currentTimeMillis()

        // Location updates (persisted + session)
        val totalUpdates = prefs.getInt(KEY_LOCATION_UPDATES, 0) + sessionLocationUpdates

        // Sync requests (persisted + session)
        val totalSyncs = prefs.getInt(KEY_SYNC_REQUESTS, 0) + sessionSyncRequests.get()

        // Average accuracy
        val totalAccuracy = prefs.getFloat(KEY_TOTAL_ACCURACY, 0f) + sessionTotalAccuracy
        val accuracyCount = prefs.getInt(KEY_ACCURACY_COUNT, 0) + sessionAccuracyCount
        val avgAccuracy = if (accuracyCount > 0) totalAccuracy / accuracyCount else 0.0

        // Tracking duration
        val accumulatedMs = prefs.getLong(KEY_TRACKING_ACCUM, 0)
        val activeMs = if (sessionStartTime > 0) now - sessionStartTime else 0
        val totalTrackingMs = accumulatedMs + maxOf(activeMs, 0)
        val trackingMinutes = (totalTrackingMs / 60000L).toInt()

        // Time by state
        val movingMs = prefs.getLong(KEY_MOVING_TIME, 0)
        val stationaryMs = prefs.getLong(KEY_STATIONARY_TIME, 0)
        val timeByState = mapOf(
            "moving" to movingMs / 1000, // seconds
            "stationary" to stationaryMs / 1000 // seconds
        )

        // Estimated drain (rough estimate based on updates and duration)
        val (estimatedDrainPercent, estimatedDrainPerHour) = if (trackingMinutes > 0 && totalUpdates > 0) {
            val drain = totalUpdates * 0.005
            drain to (drain / trackingMinutes) * 60
        } else {
            0.0 to 0.0
        }

        // GPS on time (estimate based on tracking duration)
        val timeByStateTotal = movingMs + stationaryMs
        val gpsOnTimePercent = if (totalTrackingMs > 0 && timeByStateTotal > 0) {
            minOf(100.0, (timeByStateTotal / totalTrackingMs.toDouble()) * 100.0)
        } else {
            0.0
        }

        // Optimization level
        val optimizationLevel = when {
            avgAccuracy > 100 -> "aggressive"
            avgAccuracy > 50 -> "moderate"
            else -> "none"
        }

        return mapOf(
            "currentBatteryLevel" to currentBatteryLevel,
            "isCharging" to isCharging,
            "locationUpdatesCount" to totalUpdates,
            "syncRequestsCount" to totalSyncs,
            "averageAccuracyMeters" to avgAccuracy,
            "trackingDurationMinutes" to trackingMinutes,
            "accuracyDowngradeCount" to prefs.getInt(KEY_ACCURACY_DOWNGRADE, 0),
            "gpsDisabledCount" to prefs.getInt(KEY_GPS_DISABLED, 0),
            "timeByState" to timeByState,
            "estimatedDrainPercent" to estimatedDrainPercent,
            "estimatedDrainPerHour" to estimatedDrainPerHour,
            "gpsOnTimePercent" to gpsOnTimePercent,
            "optimizationLevel" to optimizationLevel
        )
    }

    private fun updateTimeByState(wasMoving: Boolean) {
        val lastChange = prefs.getLong(KEY_LAST_STATE_CHANGE, 0)
        if (lastChange == 0L) return

        val elapsed = System.currentTimeMillis() - lastChange
        val key = if (wasMoving) KEY_MOVING_TIME else KEY_STATIONARY_TIME
        val current = prefs.getLong(key, 0)
        prefs.edit().putLong(key, current + elapsed).apply()
    }

    companion object {
        private const val KEY_LOCATION_UPDATES = "stats_location_updates"
        private const val KEY_SYNC_REQUESTS = "stats_sync_requests"
        private const val KEY_TRACKING_START = "stats_tracking_start"
        private const val KEY_TOTAL_ACCURACY = "stats_total_accuracy"
        private const val KEY_ACCURACY_COUNT = "stats_accuracy_count"
        private const val KEY_ACCURACY_DOWNGRADE = "stats_accuracy_downgrade"
        private const val KEY_GPS_DISABLED = "stats_gps_disabled"
        private const val KEY_MOVING_TIME = "stats_moving_time"
        private const val KEY_STATIONARY_TIME = "stats_stationary_time"
        private const val KEY_TRACKING_ACCUM = "stats_tracking_accum"
        private const val KEY_LAST_STATE_CHANGE = "stats_last_state_change"
        private const val KEY_LAST_STATE_MOVING = "stats_last_state_moving"
    }
}
