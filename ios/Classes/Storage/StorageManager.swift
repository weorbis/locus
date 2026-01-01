import Foundation

/// Storage manager that provides a unified interface for persistent storage.
/// Now backed by SQLite for better scalability (previously UserDefaults).
class StorageManager {
    static let shared = StorageManager()
    
    /// The SQLite storage backend (primary storage)
    private let sqliteStorage = SQLiteStorage.shared
    
    /// UserDefaults is now only used for small scalar values (odometer, config)
    private let odometerKey = "bg_odometer"
    
    // MARK: - Geofences
    
    func readGeofences() -> [[String: Any]] {
        return sqliteStorage.readGeofences()
    }
    
    func writeGeofences(_ geofences: [[String: Any]]) {
        // Clear and re-write all geofences
        sqliteStorage.clearGeofences()
        for geofence in geofences {
            sqliteStorage.insertGeofence(geofence)
        }
    }
    
    func addGeofence(_ geofence: [String: Any]) {
        sqliteStorage.insertGeofence(geofence)
    }
    
    func removeGeofence(_ identifier: String) {
        sqliteStorage.removeGeofence(identifier)
    }
    
    // MARK: - Locations
    
    func readLocations() -> [[String: Any]] {
        return sqliteStorage.readLocations()
    }
    
    func writeLocations(_ locations: [[String: Any]]) {
        // Clear and re-write all locations
        sqliteStorage.clearLocations()
        for location in locations {
            sqliteStorage.insertLocation(location)
        }
    }
    
    func saveLocation(_ payload: [String: Any], maxDays: Int, maxRecords: Int) {
        sqliteStorage.insertLocation(payload)
        
        // Prune old locations
        if maxDays > 0 || maxRecords > 0 {
            sqliteStorage.pruneLocations(maxDays: maxDays, maxRecords: maxRecords)
        }
    }
    
    func removeLocations(_ ids: [String]) {
        sqliteStorage.removeLocations(ids)
    }
    
    func destroyLocations() {
        sqliteStorage.clearLocations()
    }
    
    func locationCount() -> Int {
        return sqliteStorage.locationCount()
    }
    
    // MARK: - Odometer (small value, keep in UserDefaults)
    
    func readOdometer() -> Double {
        return UserDefaults.standard.double(forKey: odometerKey)
    }
    
    func writeOdometer(_ value: Double) {
        UserDefaults.standard.setValue(value, forKey: odometerKey)
    }
    
    // MARK: - Queue
    
    func readQueue() -> [[String: Any]] {
        return sqliteStorage.readQueue()
    }
    
    func writeQueue(_ queue: [[String: Any]]) {
        // Clear and re-write all queue items
        sqliteStorage.clearQueue()
        for item in queue {
            sqliteStorage.insertQueueItem(item)
        }
    }
    
    func addToQueue(_ item: [String: Any]) {
        sqliteStorage.insertQueueItem(item)
    }
    
    func removeQueueItems(_ ids: [String]) {
        sqliteStorage.removeQueueItems(ids)
    }
    
    func updateQueueItem(_ id: String, attempt: Int, nextRetry: String) {
        sqliteStorage.updateQueueItem(id, retryCount: attempt, nextRetryAt: nextRetry)
    }
    
    func clearQueue() {
        sqliteStorage.clearQueue()
    }
    
    // MARK: - Dead Letter Queue
    
    func moveToDeadLetter(_ id: String) {
        sqliteStorage.moveToDeadLetter(id)
    }
    
    func readDeadLetter() -> [[String: Any]] {
        return sqliteStorage.readDeadLetter()
    }
    
    func clearDeadLetter() {
        sqliteStorage.clearDeadLetter()
    }
}
