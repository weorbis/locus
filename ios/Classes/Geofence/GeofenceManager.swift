import Foundation
import CoreLocation

protocol GeofenceManagerDelegate: AnyObject {
    func onGeofencesChange(added: [String], removed: [String])
    func onGeofenceEvent(identifier: String, action: String)
}

class GeofenceManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()
    
    weak var delegate: GeofenceManagerDelegate?
    private let locationManager = CLLocationManager()
    private let config = ConfigManager.shared
    private let storage = StorageManager.shared
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func addGeofence(_ geofence: [String: Any], store: Bool = true) {
        guard let identifier = geofence["identifier"] as? String,
              let latitude = geofence["latitude"] as? Double,
              let longitude = geofence["longitude"] as? Double,
              let radius = geofence["radius"] as? Double else {
            return
        }
        
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                      radius: radius,
                                      identifier: identifier)
        region.notifyOnEntry = geofence["notifyOnEntry"] as? Bool ?? true
        region.notifyOnExit = geofence["notifyOnExit"] as? Bool ?? true
        
        locationManager.startMonitoring(for: region)
        
        if store {
            var stored = storage.readGeofences()
            stored.append(geofence)
            stored = enforceMaxMonitoredGeofences(stored)
            storage.writeGeofences(stored)
            delegate?.onGeofencesChange(added: [identifier], removed: [])
        }
    }
    
    func removeGeofence(_ identifier: String) {
        for region in locationManager.monitoredRegions {
            if region.identifier == identifier {
                locationManager.stopMonitoring(for: region)
            }
        }
        
        var stored = storage.readGeofences()
        stored.removeAll { ($0["identifier"] as? String) == identifier }
        storage.writeGeofences(stored)
        delegate?.onGeofencesChange(added: [], removed: [identifier])
    }
    
    func removeAllGeofences() {
        let stored = storage.readGeofences()
        let removedIds = stored.compactMap { $0["identifier"] as? String }
        
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        
        storage.writeGeofences([])
        if !removedIds.isEmpty {
            delegate?.onGeofencesChange(added: [], removed: removedIds)
        }
    }
    
    func getGeofence(_ identifier: String) -> [String: Any]? {
        let stored = storage.readGeofences()
        return stored.first { ($0["identifier"] as? String) == identifier }
    }
    
    func startStoredGeofences() {
        let stored = enforceMaxMonitoredGeofences(storage.readGeofences())
        for geofence in stored {
            addGeofence(geofence, store: false)
        }
    }
    
    private func enforceMaxMonitoredGeofences(_ geofences: [[String: Any]]) -> [[String: Any]] {
        if config.maxMonitoredGeofences <= 0 || geofences.count <= config.maxMonitoredGeofences {
            return geofences
        }
        
        let overflow = geofences.count - config.maxMonitoredGeofences
        let removed = geofences.prefix(overflow)
        let remaining = Array(geofences.suffix(config.maxMonitoredGeofences))
        
        for item in removed {
            if let identifier = item["identifier"] as? String {
                for region in locationManager.monitoredRegions where region.identifier == identifier {
                    locationManager.stopMonitoring(for: region)
                }
            }
        }
        
        let removedIds = removed.compactMap { $0["identifier"] as? String }
        if !removedIds.isEmpty {
            delegate?.onGeofencesChange(added: [], removed: removedIds)
        }
        
        return remaining
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        delegate?.onGeofenceEvent(identifier: region.identifier, action: "enter")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        delegate?.onGeofenceEvent(identifier: region.identifier, action: "exit")
    }
}
