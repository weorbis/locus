import Foundation

class StorageManager {
    static let shared = StorageManager()
    
    private let geofenceStoreKey = "bg_geofences"
    private let locationStoreKey = "bg_locations"
    private let queueStoreKey = "bg_queue"
    private let odometerKey = "bg_odometer"
    
    // MARK: - Geofences
    
    func readGeofences() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: geofenceStoreKey) as? [[String: Any]] ?? []
    }
    
    func writeGeofences(_ geofences: [[String: Any]]) {
        UserDefaults.standard.setValue(geofences, forKey: geofenceStoreKey)
    }
    
    // MARK: - Locations
    
    func readLocations() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: locationStoreKey) as? [[String: Any]] ?? []
    }
    
    func writeLocations(_ locations: [[String: Any]]) {
        UserDefaults.standard.setValue(locations, forKey: locationStoreKey)
    }
    
    func saveLocation(_ payload: [String: Any], maxDays: Int, maxRecords: Int) {
        var stored = readLocations()
        stored.append(payload)
        
        if maxDays > 0 {
            let cutoff = Date().addingTimeInterval(TimeInterval(-maxDays * 24 * 60 * 60))
            let formatter = ISO8601DateFormatter()
            stored = stored.filter {
                if let ts = $0["timestamp"] as? String, let date = formatter.date(from: ts) {
                    return date >= cutoff
                }
                return false
            }
        }
        
        if maxRecords > 0 && stored.count > maxRecords {
            stored = Array(stored.suffix(maxRecords))
        }
        
        writeLocations(stored)
    }
    
    func removeLocations(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var stored = readLocations()
        stored.removeAll { payload in
            if let uuid = payload["uuid"] as? String {
                return ids.contains(uuid)
            }
            return false
        }
        writeLocations(stored)
    }
    
    // MARK: - Odometer
    
    func readOdometer() -> Double {
        return UserDefaults.standard.double(forKey: odometerKey)
    }
    
    func writeOdometer(_ value: Double) {
        UserDefaults.standard.setValue(value, forKey: odometerKey)
    }
    
    // MARK: - Queue
    
    func readQueue() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: queueStoreKey) as? [[String: Any]] ?? []
    }
    
    func writeQueue(_ items: [[String: Any]]) {
        UserDefaults.standard.setValue(items, forKey: queueStoreKey)
    }
    
    func addToQueue(_ entry: [String: Any]) {
        var stored = readQueue()
        stored.append(entry)
        writeQueue(stored)
    }

    func addToQueue(payload: [String: Any], type: String?, idempotencyKey: String) -> String {
        let id = UUID().uuidString
        var entry: [String: Any] = [
            "id": id,
            "payload": payload,
            "idempotencyKey": idempotencyKey,
            "created": ISO8601DateFormatter().string(from: Date()),
            "retryCount": 0
        ]
        if let type = type {
            entry["type"] = type
        }
        addToQueue(entry)
        return id
    }
    
    func removeQueueItems(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var stored = readQueue()
        stored.removeAll { item in
            if let id = item["id"] as? String {
                return ids.contains(id)
            }
            return false
        }
        writeQueue(stored)
    }
    
    func updateQueueItem(_ id: String, attempt: Int, nextRetry: String) {
        var stored = readQueue()
        if let index = stored.firstIndex(where: { ($0["id"] as? String) == id }) {
            var item = stored[index]
            item["retryCount"] = attempt
            item["nextRetryAt"] = nextRetry
            stored[index] = item
            writeQueue(stored)
        }
    }
}
