package dev.locus.core;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.HashMap;
import java.util.Map;

import dev.locus.LocusPlugin;

/**
 * Tracks runtime statistics for battery optimization and diagnostics.
 * 
 * These metrics are persisted across sessions to provide accurate
 * long-term tracking statistics.
 */
public class TrackingStats {

    private static final String KEY_LOCATION_UPDATES = "stats_location_updates";
    private static final String KEY_SYNC_REQUESTS = "stats_sync_requests";
    private static final String KEY_TRACKING_START = "stats_tracking_start";
    private static final String KEY_TOTAL_ACCURACY = "stats_total_accuracy";
    private static final String KEY_ACCURACY_COUNT = "stats_accuracy_count";
    private static final String KEY_ACCURACY_DOWNGRADE = "stats_accuracy_downgrade";
    private static final String KEY_GPS_DISABLED = "stats_gps_disabled";
    private static final String KEY_MOVING_TIME = "stats_moving_time";
    private static final String KEY_STATIONARY_TIME = "stats_stationary_time";
    private static final String KEY_TRACKING_ACCUM = "stats_tracking_accum";
    private static final String KEY_LAST_STATE_CHANGE = "stats_last_state_change";
    private static final String KEY_LAST_STATE_MOVING = "stats_last_state_moving";

    private final SharedPreferences prefs;

    // In-memory counters for current session
    private int sessionLocationUpdates = 0;
    private final java.util.concurrent.atomic.AtomicInteger sessionSyncRequests = new java.util.concurrent.atomic.AtomicInteger(0);
    private double sessionTotalAccuracy = 0.0;
    private int sessionAccuracyCount = 0;
    private long sessionStartTime = 0;

    public TrackingStats(Context context) {
        this.prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
    }

    /**
     * Called when tracking starts.
     */
    public void onTrackingStart() {
        sessionStartTime = System.currentTimeMillis();
        sessionLocationUpdates = 0;
        sessionSyncRequests.set(0);
        sessionTotalAccuracy = 0.0;
        sessionAccuracyCount = 0;

        // Accrue any dangling state time from a previous run, then reset the marker
        updateTimeByState(prefs.getBoolean(KEY_LAST_STATE_MOVING, false));

        // Always set a fresh session start marker for accurate session durations
        prefs.edit().putLong(KEY_TRACKING_START, sessionStartTime).apply();
        
        // Initialize state tracking
        prefs.edit()
            .putLong(KEY_LAST_STATE_CHANGE, sessionStartTime)
            .putBoolean(KEY_LAST_STATE_MOVING, false)
            .apply();
    }

    /**
     * Called when tracking stops.
     */
    public void onTrackingStop() {
        // Persist session stats
        if (sessionStartTime > 0) {
            int totalUpdates = prefs.getInt(KEY_LOCATION_UPDATES, 0) + sessionLocationUpdates;
            int totalSyncs = prefs.getInt(KEY_SYNC_REQUESTS, 0) + sessionSyncRequests.get();
            double totalAccuracy = prefs.getFloat(KEY_TOTAL_ACCURACY, 0f) + (float) sessionTotalAccuracy;
            int accuracyCount = prefs.getInt(KEY_ACCURACY_COUNT, 0) + sessionAccuracyCount;
            long accumulatedMs = prefs.getLong(KEY_TRACKING_ACCUM, 0);
            long sessionMs = System.currentTimeMillis() - sessionStartTime;
            long nextAccum = accumulatedMs + Math.max(sessionMs, 0);

            prefs.edit()
                .putInt(KEY_LOCATION_UPDATES, totalUpdates)
                .putInt(KEY_SYNC_REQUESTS, totalSyncs)
                .putFloat(KEY_TOTAL_ACCURACY, (float) totalAccuracy)
                .putInt(KEY_ACCURACY_COUNT, accuracyCount)
                .putLong(KEY_TRACKING_ACCUM, nextAccum)
                .apply();
            
            // Update time by state
            updateTimeByState(prefs.getBoolean(KEY_LAST_STATE_MOVING, false));
        }
        sessionStartTime = 0;
    }

    /**
     * Records a location update.
     */
    public void onLocationUpdate(float accuracy) {
        sessionLocationUpdates++;
        if (accuracy > 0) {
            sessionTotalAccuracy += accuracy;
            sessionAccuracyCount++;
        }
    }

    /**
     * Records a sync request.
     */
    public void onSyncRequest() {
        sessionSyncRequests.incrementAndGet();
    }

    /**
     * Records a motion state change.
     */
    public void onMotionChange(boolean isMoving) {
        updateTimeByState(!isMoving); // Update time for previous state
        prefs.edit()
            .putLong(KEY_LAST_STATE_CHANGE, System.currentTimeMillis())
            .putBoolean(KEY_LAST_STATE_MOVING, isMoving)
            .apply();
    }

    /**
     * Records an accuracy downgrade event.
     */
    public void onAccuracyDowngrade() {
        int count = prefs.getInt(KEY_ACCURACY_DOWNGRADE, 0);
        prefs.edit().putInt(KEY_ACCURACY_DOWNGRADE, count + 1).apply();
    }

    /**
     * Records a GPS disabled event.
     */
    public void onGpsDisabled() {
        int count = prefs.getInt(KEY_GPS_DISABLED, 0);
        prefs.edit().putInt(KEY_GPS_DISABLED, count + 1).apply();
    }

    /**
     * Resets all statistics.
     */
    public void reset() {
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
            .apply();
        
        sessionLocationUpdates = 0;
        sessionSyncRequests.set(0);
        sessionTotalAccuracy = 0.0;
        sessionAccuracyCount = 0;
        sessionStartTime = 0;
    }

    /**
     * Builds the battery stats map for the Dart layer.
     */
    public Map<String, Object> buildStats(int currentBatteryLevel, boolean isCharging) {
        Map<String, Object> stats = new HashMap<>();
        
        // Battery info
        stats.put("currentBatteryLevel", currentBatteryLevel);
        stats.put("isCharging", isCharging);
        
        // Location updates (persisted + session)
        int totalUpdates = prefs.getInt(KEY_LOCATION_UPDATES, 0) + sessionLocationUpdates;
        stats.put("locationUpdatesCount", totalUpdates);
        
        // Sync requests (persisted + session)
        int totalSyncs = prefs.getInt(KEY_SYNC_REQUESTS, 0) + sessionSyncRequests.get();
        stats.put("syncRequestsCount", totalSyncs);
        
        // Average accuracy
        double totalAccuracy = prefs.getFloat(KEY_TOTAL_ACCURACY, 0f) + sessionTotalAccuracy;
        int accuracyCount = prefs.getInt(KEY_ACCURACY_COUNT, 0) + sessionAccuracyCount;
        double avgAccuracy = accuracyCount > 0 ? totalAccuracy / accuracyCount : 0.0;
        stats.put("averageAccuracyMeters", avgAccuracy);
        
        // Tracking duration
        long now = System.currentTimeMillis();
        long trackingStart = prefs.getLong(KEY_TRACKING_START, 0);
        long accumulatedMs = prefs.getLong(KEY_TRACKING_ACCUM, 0);
        long activeMs = sessionStartTime > 0 ? now - sessionStartTime : 0;
        long totalTrackingMs = accumulatedMs + Math.max(activeMs, 0);
        int trackingMinutes = (int) (totalTrackingMs / 60000);
        stats.put("trackingDurationMinutes", trackingMinutes);
        
        // Downgrade/disable counts
        stats.put("accuracyDowngradeCount", prefs.getInt(KEY_ACCURACY_DOWNGRADE, 0));
        stats.put("gpsDisabledCount", prefs.getInt(KEY_GPS_DISABLED, 0));
        
        // Time by state
        Map<String, Object> timeByState = new HashMap<>();
        long movingMs = prefs.getLong(KEY_MOVING_TIME, 0);
        long stationaryMs = prefs.getLong(KEY_STATIONARY_TIME, 0);
        timeByState.put("moving", movingMs / 1000); // seconds
        timeByState.put("stationary", stationaryMs / 1000); // seconds
        stats.put("timeByState", timeByState);
        
        // Estimated drain (rough estimate based on updates and duration)
        double estimatedDrainPercent = 0.0;
        double estimatedDrainPerHour = 0.0;
        if (trackingMinutes > 0 && totalUpdates > 0) {
            // Rough estimate: ~0.5% per 100 location updates
            estimatedDrainPercent = totalUpdates * 0.005;
            estimatedDrainPerHour = (estimatedDrainPercent / trackingMinutes) * 60;
        }
        stats.put("estimatedDrainPercent", estimatedDrainPercent);
        stats.put("estimatedDrainPerHour", estimatedDrainPerHour);
        
        // GPS on time (estimate based on tracking duration)
        double gpsOnTimePercent = 0.0;
        long timeByStateTotal = movingMs + stationaryMs;
        if (totalTrackingMs > 0 && timeByStateTotal > 0) {
            gpsOnTimePercent = Math.min(100.0, (timeByStateTotal / (double) totalTrackingMs) * 100.0);
        }
        stats.put("gpsOnTimePercent", gpsOnTimePercent);
        
        // Optimization level
        String optimizationLevel = "none";
        if (avgAccuracy > 100) {
            optimizationLevel = "aggressive";
        } else if (avgAccuracy > 50) {
            optimizationLevel = "moderate";
        }
        stats.put("optimizationLevel", optimizationLevel);
        
        return stats;
    }

    private void updateTimeByState(boolean wasMoving) {
        long lastChange = prefs.getLong(KEY_LAST_STATE_CHANGE, 0);
        if (lastChange == 0) return;
        
        long elapsed = System.currentTimeMillis() - lastChange;
        String key = wasMoving ? KEY_MOVING_TIME : KEY_STATIONARY_TIME;
        long current = prefs.getLong(key, 0);
        prefs.edit().putLong(key, current + elapsed).apply();
    }
}
