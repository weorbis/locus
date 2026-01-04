import Foundation
import CoreLocation
import UIKit

protocol LocationClientDelegate: AnyObject {
    func onLocationUpdate(_ location: CLLocation)
    func onLocationError(_ error: Error)
    func onAuthorizationChange()
}

class LocationClient: NSObject, CLLocationManagerDelegate {
    static let shared = LocationClient()
    
    weak var delegate: LocationClientDelegate?
    private let locationManager = CLLocationManager()
    private let config = ConfigManager.shared
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .other
        
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String], backgroundModes.contains("location") {
            locationManager.allowsBackgroundLocationUpdates = true
        }
    }
    
    func applyConfig() {
        locationManager.desiredAccuracy = config.desiredAccuracy
        // Distance filter is dynamic based on motion, but we set initial
        locationManager.distanceFilter = config.distanceFilter 
        locationManager.pausesLocationUpdatesAutomatically = config.pausesLocationUpdatesAutomatically
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = config.showsBackgroundLocationIndicator
        }
    }
    
    func setDistanceFilter(_ distance: Double) {
        locationManager.distanceFilter = distance
    }
    
    func requestLocation() {
        applyConfig()
        locationManager.requestLocation()
    }
    
    func start() {
        locationManager.startUpdatingLocation()
        let auth = getAuthorizationStatus()
        if (!config.stopOnTerminate || config.startOnBoot) && auth == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }
    
    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
    }
    
    func requestPermissions() {
        let status = getAuthorizationStatus()
        
        switch status {
        case .notDetermined:
            // First, request "when in use" permission
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Already have when in use, request "always" for background
            locationManager.requestAlwaysAuthorization()
        default:
            // Permission already granted or denied
            break
        }
    }
    
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }
    
    func getAccuracyAuthorization() -> CLAccuracyAuthorization {
        if #available(iOS 14.0, *) {
            return locationManager.accuracyAuthorization
        }
        return .fullAccuracy
    }
    
    func isLocationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        delegate?.onLocationUpdate(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.onLocationError(error)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.onAuthorizationChange()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.onAuthorizationChange()
    }
    
    // Pass-through for other delegate methods if needed
}
