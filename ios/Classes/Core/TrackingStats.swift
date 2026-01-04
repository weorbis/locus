import Foundation

/// Tracks runtime statistics for battery optimization and diagnostics.
/// These metrics are persisted across sessions to provide accurate long-term tracking statistics.
class TrackingStats {
    
    private static let kLocationUpdates = "stats_location_updates"
    private static let kSyncRequests = "stats_sync_requests"
    private static let kTrackingStart = "stats_tracking_start"
    private static let kTotalAccuracy = "stats_total_accuracy"
    private static let kAccuracyCount = "stats_accuracy_count"
    private static let kAccuracyDowngrade = "stats_accuracy_downgrade"
    private static let kGpsDisabled = "stats_gps_disabled"
    private static let kMovingTime = "stats_moving_time"
    private static let kStationaryTime = "stats_stationary_time"
    private static let kLastStateChange = "stats_last_state_change"
    private static let kLastStateMoving = "stats_last_state_moving"
    private static let kTrackingAccum = "stats_tracking_accum"
    
    private let defaults: UserDefaults
    
    // In-memory counters for current session
    private var sessionLocationUpdates: Int = 0
    private var sessionSyncRequests: Int = 0
    private var sessionTotalAccuracy: Double = 0.0
    private var sessionAccuracyCount: Int = 0
    private var sessionStartTime: Date?
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// Called when tracking starts.
    func onTrackingStart() {
        sessionStartTime = Date()
        sessionLocationUpdates = 0
        sessionSyncRequests = 0
        sessionTotalAccuracy = 0.0
        sessionAccuracyCount = 0
        
        // Accrue any dangling state time from a previous run, then reset the marker
        updateTimeByState(wasMoving: defaults.bool(forKey: TrackingStats.kLastStateMoving))

        // Always set a fresh session start marker for accurate session durations
        let nowMs = Date().timeIntervalSince1970 * 1000
        defaults.set(nowMs, forKey: TrackingStats.kTrackingStart)
        
        // Initialize state tracking
        defaults.set(Date().timeIntervalSince1970, forKey: TrackingStats.kLastStateChange)
        defaults.set(false, forKey: TrackingStats.kLastStateMoving)
    }
    
    /// Called when tracking stops.
    func onTrackingStop() {
        guard sessionStartTime != nil else { return }
        
        // Persist session stats
        let totalUpdates = defaults.integer(forKey: TrackingStats.kLocationUpdates) + sessionLocationUpdates
        let totalSyncs = defaults.integer(forKey: TrackingStats.kSyncRequests) + sessionSyncRequests
        let totalAccuracy = defaults.double(forKey: TrackingStats.kTotalAccuracy) + sessionTotalAccuracy
        let accuracyCount = defaults.integer(forKey: TrackingStats.kAccuracyCount) + sessionAccuracyCount
        let accumulatedMs = defaults.double(forKey: TrackingStats.kTrackingAccum)
        let nowMs = Date().timeIntervalSince1970 * 1000
        let sessionStartMs = (sessionStartTime?.timeIntervalSince1970 ?? (nowMs / 1000)) * 1000
        let sessionMs = nowMs - sessionStartMs
        let nextAccum = accumulatedMs + max(sessionMs, 0)
        
        defaults.set(totalUpdates, forKey: TrackingStats.kLocationUpdates)
        defaults.set(totalSyncs, forKey: TrackingStats.kSyncRequests)
        defaults.set(totalAccuracy, forKey: TrackingStats.kTotalAccuracy)
        defaults.set(accuracyCount, forKey: TrackingStats.kAccuracyCount)
        defaults.set(nextAccum, forKey: TrackingStats.kTrackingAccum)
        
        // Update time by state
        updateTimeByState(wasMoving: defaults.bool(forKey: TrackingStats.kLastStateMoving))
        
        sessionStartTime = nil
    }
    
    /// Records a location update.
    func onLocationUpdate(accuracy: Double) {
        sessionLocationUpdates += 1
        if accuracy > 0 {
            sessionTotalAccuracy += accuracy
            sessionAccuracyCount += 1
        }
    }
    
    /// Records a sync request.
    func onSyncRequest() {
        sessionSyncRequests += 1
    }
    
    /// Records a motion state change.
    func onMotionChange(isMoving: Bool) {
        // Update time for previous state
        let wasMoving = defaults.bool(forKey: TrackingStats.kLastStateMoving)
        updateTimeByState(wasMoving: wasMoving)
        
        defaults.set(Date().timeIntervalSince1970, forKey: TrackingStats.kLastStateChange)
        defaults.set(isMoving, forKey: TrackingStats.kLastStateMoving)
    }
    
    /// Records an accuracy downgrade event.
    func onAccuracyDowngrade() {
        let count = defaults.integer(forKey: TrackingStats.kAccuracyDowngrade)
        defaults.set(count + 1, forKey: TrackingStats.kAccuracyDowngrade)
    }
    
    /// Records a GPS disabled event.
    func onGpsDisabled() {
        let count = defaults.integer(forKey: TrackingStats.kGpsDisabled)
        defaults.set(count + 1, forKey: TrackingStats.kGpsDisabled)
    }
    
    /// Resets all statistics.
    func reset() {
        defaults.removeObject(forKey: TrackingStats.kLocationUpdates)
        defaults.removeObject(forKey: TrackingStats.kSyncRequests)
        defaults.removeObject(forKey: TrackingStats.kTrackingStart)
        defaults.removeObject(forKey: TrackingStats.kTotalAccuracy)
        defaults.removeObject(forKey: TrackingStats.kAccuracyCount)
        defaults.removeObject(forKey: TrackingStats.kAccuracyDowngrade)
        defaults.removeObject(forKey: TrackingStats.kGpsDisabled)
        defaults.removeObject(forKey: TrackingStats.kMovingTime)
        defaults.removeObject(forKey: TrackingStats.kStationaryTime)
        defaults.removeObject(forKey: TrackingStats.kLastStateChange)
        defaults.removeObject(forKey: TrackingStats.kLastStateMoving)
        defaults.removeObject(forKey: TrackingStats.kTrackingAccum)
        
        sessionLocationUpdates = 0
        sessionSyncRequests = 0
        sessionTotalAccuracy = 0.0
        sessionAccuracyCount = 0
        sessionStartTime = nil
    }
    
    /// Builds the battery stats dictionary for the Dart layer.
    func buildStats(currentBatteryLevel: Int, isCharging: Bool) -> [String: Any] {
        var stats: [String: Any] = [:]
        
        // Battery info
        stats["currentBatteryLevel"] = currentBatteryLevel
        stats["isCharging"] = isCharging
        
        // Location updates (persisted + session)
        let totalUpdates = defaults.integer(forKey: TrackingStats.kLocationUpdates) + sessionLocationUpdates
        stats["locationUpdatesCount"] = totalUpdates
        
        // Sync requests (persisted + session)
        let totalSyncs = defaults.integer(forKey: TrackingStats.kSyncRequests) + sessionSyncRequests
        stats["syncRequestsCount"] = totalSyncs
        
        // Average accuracy
        let totalAccuracy = defaults.double(forKey: TrackingStats.kTotalAccuracy) + sessionTotalAccuracy
        let accuracyCount = defaults.integer(forKey: TrackingStats.kAccuracyCount) + sessionAccuracyCount
        let avgAccuracy = accuracyCount > 0 ? totalAccuracy / Double(accuracyCount) : 0.0
        stats["averageAccuracyMeters"] = avgAccuracy
        
        // Tracking duration
        let nowMs = Date().timeIntervalSince1970 * 1000
        let accumulatedMs = defaults.double(forKey: TrackingStats.kTrackingAccum)
        let sessionStartMs = (sessionStartTime?.timeIntervalSince1970 ?? (nowMs / 1000)) * 1000
        let activeMs = (sessionStartTime != nil) ? (nowMs - sessionStartMs) : 0
        let totalTrackingMs = accumulatedMs + max(activeMs, 0)
        let trackingMinutes = Int(totalTrackingMs / 60000)
        stats["trackingDurationMinutes"] = trackingMinutes
        
        // Downgrade/disable counts
        stats["accuracyDowngradeCount"] = defaults.integer(forKey: TrackingStats.kAccuracyDowngrade)
        stats["gpsDisabledCount"] = defaults.integer(forKey: TrackingStats.kGpsDisabled)
        
        // Time by state
        let movingTime = defaults.double(forKey: TrackingStats.kMovingTime)
        let stationaryTime = defaults.double(forKey: TrackingStats.kStationaryTime)
        stats["timeByState"] = [
            "moving": Int(movingTime),
            "stationary": Int(stationaryTime)
        ]
        
        // Estimated drain (rough estimate based on updates and duration)
        var estimatedDrainPercent = 0.0
        var estimatedDrainPerHour = 0.0
        if trackingMinutes > 0 && totalUpdates > 0 {
            // Rough estimate: ~0.5% per 100 location updates
            estimatedDrainPercent = Double(totalUpdates) * 0.005
            estimatedDrainPerHour = (estimatedDrainPercent / Double(trackingMinutes)) * 60
        }
        stats["estimatedDrainPercent"] = estimatedDrainPercent
        stats["estimatedDrainPerHour"] = estimatedDrainPerHour
        
        // GPS on time (estimate based on tracking duration)
        let timeByStateTotal = movingTime + stationaryTime
        let gpsOnTimePercent = (totalTrackingMs > 0 && timeByStateTotal > 0) ? min(100.0, (timeByStateTotal / totalTrackingMs) * 100.0) : 0.0
        stats["gpsOnTimePercent"] = gpsOnTimePercent
        
        // Optimization level
        var optimizationLevel = "none"
        if avgAccuracy > 100 {
            optimizationLevel = "aggressive"
        } else if avgAccuracy > 50 {
            optimizationLevel = "moderate"
        }
        stats["optimizationLevel"] = optimizationLevel
        
        return stats
    }
    
    private func updateTimeByState(wasMoving: Bool) {
        let lastChange = defaults.double(forKey: TrackingStats.kLastStateChange)
        guard lastChange > 0 else { return }
        
        let elapsed = Date().timeIntervalSince1970 - lastChange
        let key = wasMoving ? TrackingStats.kMovingTime : TrackingStats.kStationaryTime
        let current = defaults.double(forKey: key)
        defaults.set(current + elapsed, forKey: key)
    }
}
