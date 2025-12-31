import Foundation
import CoreLocation
import CoreMotion
import UIKit

extension SwiftLocusPlugin {
  func buildLocationPayload(_ location: CLLocation, eventName: String) -> [String: Any] {
    let coords: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "speed": location.speed,
      "heading": location.course,
      "altitude": location.altitude
    ]

    let activity: [String: Any] = [
      "type": motionDetector.lastActivityType,
      "confidence": motionDetector.lastActivityConfidence
    ]

    return [
      "uuid": UUID().uuidString,
      "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
      "coords": coords,
      "activity": activity,
      "event": eventName,
      "is_moving": motionDetector.isMoving,
      "odometer": storage.readOdometer()
    ]
  }

  func emitLocationEvent(_ location: CLLocation, eventName: String, completion: ((Bool) -> Void)? = nil) {
    updateOdometer(location)
    lastLocation = location

    let payload = buildLocationPayload(location, eventName: eventName)

    let event: [String: Any] = [
      "type": eventName,
      "data": payload
    ]
    sendEvent(event)

    if shouldPersist(eventName: eventName) {
      storage.saveLocation(payload, maxDays: configManager.maxDaysToPersist, maxRecords: configManager.maxRecordsToPersist)
    }

    syncManager.syncNow(currentPayload: payload)
    completion?(true)
  }

  func updateOdometer(_ location: CLLocation) {
    if let last = lastLocation {
      let delta = location.distance(from: last)
      if delta > 0 {
        let current = storage.readOdometer() + delta
        storage.writeOdometer(current)
      }
    }
  }

  func emitProviderChange() {
    let status = locationClient.getAuthorizationStatus()
    let authorizationStatus: String
    switch status {
    case .authorizedAlways:
      authorizationStatus = "always"
    case .authorizedWhenInUse:
      authorizationStatus = "whenInUse"
    case .denied:
      authorizationStatus = "denied"
    case .restricted:
      authorizationStatus = "restricted"
    case .notDetermined:
      fallthrough
    @unknown default:
      authorizationStatus = "notDetermined"
    }

    let accuracyAuthorization: String
    let auth = locationClient.getAccuracyAuthorization()
    accuracyAuthorization = auth == .fullAccuracy ? "full" : "reduced"

    let payload: [String: Any] = [
      "enabled": locationClient.isLocationServicesEnabled(),
      "status": locationClient.isLocationServicesEnabled() ? "enabled" : "disabled",
      "availability": locationClient.isLocationServicesEnabled() ? "available" : "unavailable",
      "authorizationStatus": authorizationStatus,
      "accuracyAuthorization": accuracyAuthorization
    ]

    let event: [String: Any] = [
      "type": "providerchange",
      "data": payload
    ]
    sendEvent(event)
  }

  func emitEnabledChange(_ enabled: Bool) {
    let event: [String: Any] = [
      "type": "enabledchange",
      "data": enabled
    ]
    sendEvent(event)
  }

  func emitConnectivityChange(_ powerSaveEnabled: Bool? = nil, emitPowerSave: Bool = false) {
    let path = networkMonitor?.currentPath
    let connected = path?.status == .satisfied
    let networkType: String
    if let path = path {
      if path.usesInterfaceType(.wifi) {
        networkType = "wifi"
      } else if path.usesInterfaceType(.cellular) {
        networkType = "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        networkType = "ethernet"
      } else {
        networkType = "unknown"
      }
    } else {
      networkType = "unknown"
    }

    let connectivityEvent: [String: Any] = [
      "type": "connectivitychange",
      "data": [
        "connected": connected ?? false,
        "networkType": networkType
      ]
    ]
    sendEvent(connectivityEvent)

    if emitPowerSave {
      let event: [String: Any] = [
        "type": "powersavechange",
        "data": powerSaveEnabled ?? ProcessInfo.processInfo.isLowPowerModeEnabled
      ]
      sendEvent(event)
    }
  }

  func sendEvent(_ event: [String: Any]) {
    if let sink = eventSink {
      sink(event)
    } else {
      dispatchHeadlessEvent(event)
    }
  }

  func emitScheduleEvent() {
    guard configManager.scheduleEnabled, let location = lastLocation else {
      return
    }
    let payload = buildLocationPayload(location, eventName: "location")
    let event: [String: Any] = [
      "type": "schedule",
      "data": payload
    ]
    sendEvent(event)
  }

  func buildDiagnosticsMetadata() -> [String: Any] {
    var metadata: [String: Any] = [
      "platform": "ios",
      "systemVersion": UIDevice.current.systemVersion,
      "model": UIDevice.current.model
    ]

    let status = CLLocationManager.authorizationStatus()
    metadata["authorizationStatus"] = authorizationStatusLabel(status)
    metadata["powerSaveMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
    metadata["locationEnabled"] = CLLocationManager.locationServicesEnabled()
    metadata["motionAvailable"] = CMMotionActivityManager.isActivityAvailable()

    return metadata
  }

  func authorizationStatusLabel(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorizedAlways:
      return "always"
    case .authorizedWhenInUse:
      return "whenInUse"
    @unknown default:
      return "unknown"
    }
  }

  func shouldPersist(eventName: String) -> Bool {
    if configManager.batchSync { return true }
    if configManager.persistMode == "none" { return false }
    if configManager.persistMode == "all" { return true }
    if configManager.persistMode == "geofence" { return eventName == "geofence" }
    return configManager.persistMode == "location" && eventName != "geofence"
  }

  // MARK: - Battery & Power

  func buildBatteryStats() -> [String: Any] {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let batteryLevel = UIDevice.current.batteryLevel
    let batteryState = UIDevice.current.batteryState
    return [
      "batteryLevel": batteryLevel >= 0 ? Int(batteryLevel * 100) : -1,
      "isCharging": batteryState == .charging || batteryState == .full,
      "estimatedDrainPerHour": 0.0,
      "locationCount": 0
    ]
  }

  func buildPowerState() -> [String: Any] {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let batteryLevel = UIDevice.current.batteryLevel
    let batteryState = UIDevice.current.batteryState
    return [
      "batteryLevel": batteryLevel >= 0 ? Int(batteryLevel * 100) : 50,
      "isCharging": batteryState == .charging || batteryState == .full,
      "isPowerSaveMode": ProcessInfo.processInfo.isLowPowerModeEnabled
    ]
  }

  func getNetworkTypeString() -> String {
    let path = networkMonitor?.currentPath
    if path?.status != .satisfied {
      return "none"
    }
    if let path = path {
      if path.usesInterfaceType(.wifi) {
        return "wifi"
      } else if path.usesInterfaceType(.cellular) {
        return "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        return "wifi"
      }
    }
    return "unknown"
  }
}

