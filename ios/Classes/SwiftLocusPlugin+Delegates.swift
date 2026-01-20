import Flutter
import CoreLocation

extension SwiftLocusPlugin {
  // MARK: - MotionManagerDelegate
  public func onActivityChange(type: String, confidence: Int) {
    guard let location = lastLocation else {
      return
    }
    emitLocationEvent(location, eventName: "activitychange")
  }

  public func onMotionStateChange(isMoving: Bool) {
    locationClient.setDistanceFilter(isMoving ? configManager.distanceFilter : configManager.stationaryRadius)
    trackingStats.onMotionChange(isMoving: isMoving)

    // Only emit event if we have a location to attach to it
    guard let location = lastLocation else {
      return
    }
    emitLocationEvent(location, eventName: "motionchange")
  }

  // MARK: - SyncManagerDelegate
  public func onHttpEvent(_ event: [String: Any]) {
    trackingStats.onSyncRequest()
    sendEvent(event)
  }

  public func onSyncEvent(_ event: [String: Any]) {
    sendEvent(event)
  }

  public func onLog(level: String, message: String) {
    appendLog(message, level: level)
  }

  public func buildSyncBody(locations: [[String: Any]], extras: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
    // Invoke Dart to build the sync body
    guard let channel = methodChannel else {
      completion(nil)
      return
    }
    
    let args: [String: Any] = [
      "locations": locations,
      "extras": extras
    ]
    
    DispatchQueue.main.async {
      channel.invokeMethod("buildSyncBody", arguments: args) { result in
        if let body = result as? [String: Any] {
          completion(body)
        } else {
          // Dart returned null or error, use default body
          completion(nil)
        }
      }
    }
  }

  public func onPreSyncValidation(locations: [[String: Any]], extras: [String: Any], completion: @escaping (Bool) -> Void) {
    guard let channel = methodChannel else {
      // No method channel available (app terminated).
      // Use headless validation if a callback is registered, otherwise proceed with sync.
      if headlessValidationDispatcher.isAvailable {
        headlessValidationDispatcher.validate(locations: locations, extras: extras, completion: completion)
      } else {
        // No headless validation available, proceed with sync
        completion(true)
      }
      return
    }
    
    let args: [String: Any] = [
      "locations": locations,
      "extras": extras
    ]
    
    DispatchQueue.main.async {
      channel.invokeMethod("validatePreSync", arguments: args) { result in
        if let proceed = result as? Bool {
          completion(proceed)
        } else {
          // Default to true on error/null
          completion(true)
        }
      }
    }
  }

  // MARK: - SchedulerDelegate
  public func onScheduleCheck(shouldBeEnabled: Bool) {
    if shouldBeEnabled {
      if !isEnabled {
        startTracking()
        emitScheduleEvent()
      }
    } else {
      if isEnabled {
        stopTracking()
      }
    }
  }

  // MARK: - GeofenceManagerDelegate
  public func onGeofencesChange(added: [String], removed: [String]) {
    guard !added.isEmpty || !removed.isEmpty else { return }
    
    let event: [String: Any] = [
      "type": "geofenceschange",
      "data": [
        "on": added,
        "off": removed
      ]
    ]
    sendEvent(event)
  }

  public func onGeofenceEvent(identifier: String, action: String) {
    guard let geofence = geofenceManager.getGeofence(identifier) else {
      appendLog("Geofence event for unknown geofence: \(identifier)", level: "warning")
      return
    }

    var payload: [String: Any] = [
      "geofence": geofence,
      "action": action
    ]

    if let location = lastLocation {
      let locationPayload = buildLocationPayload(location, eventName: "geofence")
      payload["location"] = locationPayload
      if !configManager.privacyModeEnabled {
        if shouldPersist(eventName: "geofence") {
          storage.saveLocation(locationPayload, maxDays: configManager.maxDaysToPersist, maxRecords: configManager.maxRecordsToPersist)
        }
        syncManager.syncNow(currentPayload: locationPayload)
      }
    }

    let event: [String: Any] = [
      "type": "geofence",
      "data": payload
    ]
    sendEvent(event)
  }

  public func onGeofenceError(identifier: String, error: String) {
    let event: [String: Any] = [
      "type": "geofenceerror",
      "data": [
        "identifier": identifier,
        "error": error
      ]
    ]
    sendEvent(event)
    appendLog("Geofence error for '\(identifier)': \(error)", level: "error")
  }

  // MARK: - LocationClientDelegate
  public func onLocationUpdate(_ location: CLLocation) {
    guard isEnabled || pendingLocationResult != nil || configManager.startOnBoot else {
      lastLocation = location
      return
    }
    
    if isEnabled {
      trackingStats.onLocationUpdate(accuracy: location.horizontalAccuracy)
    }

    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      let payload = buildLocationPayload(location, eventName: "location")
      pending(payload)
    }
    if isEnabled {
      emitLocationEvent(location, eventName: "location")
    } else {
      lastLocation = location
    }

    if configManager.startOnBoot && !isEnabled {
      startTracking()
    }
  }

  public func onLocationError(_ error: Error) {
    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      pending(FlutterError(code: "LOCATION_ERROR", message: error.localizedDescription, details: nil))
    }
    appendLog("Location error: \(error.localizedDescription)", level: "error")
  }

  public func onAuthorizationChange() {
    emitProviderChange()
  }
}
