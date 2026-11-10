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
    let args: [String: Any] = [
      "locations": locations,
      "extras": extras
    ]

    callbackBroker.request(
      invoke: { owner, reply in
        guard let engine = owner as? LocusEngineBinding else {
          reply(nil)
          return
        }
        DispatchQueue.main.async {
          engine.methodChannel.invokeMethod("buildSyncBody", arguments: args) { result in
            reply(result as? [String: Any])
          }
        }
      },
      fallback: { reply in reply(nil) },
      terminalDefault: { nil },
      completion: completion
    )
  }

  public func onPreSyncValidation(locations: [[String: Any]], extras: [String: Any], completion: @escaping (Bool) -> Void) {
    let args: [String: Any] = [
      "locations": locations,
      "extras": extras
    ]

    callbackBroker.request(
      invoke: { owner, reply in
        guard let engine = owner as? LocusEngineBinding else {
          reply(true)
          return
        }
        DispatchQueue.main.async {
          engine.methodChannel.invokeMethod("validatePreSync", arguments: args) { result in
            reply(result as? Bool ?? true)
          }
        }
      },
      fallback: { [headlessValidationDispatcher] reply in
        // No live UI engine. Use headless validation when registered;
        // otherwise preserve the existing fail-open sync behavior.
        if headlessValidationDispatcher.isAvailable {
          headlessValidationDispatcher.validate(
            locations: locations,
            extras: extras,
            completion: reply
          )
        } else {
          reply(true)
        }
      },
      terminalDefault: { true },
      completion: completion
    )
  }

  public func onHeadersRefresh(completion: @escaping ([String: String]?) -> Void) {
    callbackBroker.request(
      invoke: { owner, reply in
        guard let engine = owner as? LocusEngineBinding else {
          reply(nil)
          return
        }
        DispatchQueue.main.async {
          engine.methodChannel.invokeMethod("refreshDynamicHeaders", arguments: nil) { result in
            let headers = (result as? [String: Any])?.reduce(into: [String: String]()) { partial, entry in
              partial[entry.key] = "\(entry.value)"
            }
            reply(headers)
          }
        }
      },
      fallback: { [headlessHeadersDispatcher] reply in
        if headlessHeadersDispatcher.isAvailable {
          headlessHeadersDispatcher.refreshHeaders(completion: reply)
        } else {
          reply(nil)
        }
      },
      terminalDefault: { nil },
      completion: completion
    )
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
    let event = DeferredGeofenceEvent(identifier: identifier, action: action, location: lastLocation)
    // The geofence row cannot be read while storage is unavailable, so the
    // crossing waits instead of being mistaken for an unknown fence.
    guard storage.isAvailable else {
      deferGeofenceEvent(event)
      return
    }
    // Earlier deferred crossings go first so events keep their order.
    processDeferredGeofenceEvents()
    deliver(event)
  }

  private func deferGeofenceEvent(_ event: DeferredGeofenceEvent) {
    deferredGeofenceEvents.append(event)
    let excess = deferredGeofenceEvents.count - Self.maximumDeferredGeofenceEvents
    if excess > 0 {
      deferredGeofenceEvents.removeFirst(excess)
      NSLog("[locus] Deferred geofence event limit of %d exceeded; dropped the oldest event", Self.maximumDeferredGeofenceEvents)
    }
    NSLog("[locus] Storage unavailable; deferred geofence %@ for '%@' (%d waiting)", event.action, event.identifier, deferredGeofenceEvents.count)
  }

  /// Delivers region events deferred while storage was unavailable, oldest first.
  func processDeferredGeofenceEvents() {
    guard !deferredGeofenceEvents.isEmpty else { return }
    let events = deferredGeofenceEvents
    deferredGeofenceEvents = []
    NSLog("[locus] Storage available; delivering %d deferred geofence event(s)", events.count)
    events.forEach(deliver)
  }

  private func deliver(_ event: DeferredGeofenceEvent) {
    let identifier = event.identifier
    let action = event.action
    guard let geofence = geofenceManager.getGeofence(identifier) else {
      appendLog("Geofence event for unknown geofence: \(identifier)", level: "warning")
      return
    }

    var payload: [String: Any] = [
      "geofence": geofence,
      "action": action
    ]

    let privacyGuardEnabled = configManager.privacyModeEnabled
    var containsRawLocation = false
    if let location = event.location {
      containsRawLocation = true
      let locationPayload = buildLocationPayload(location, eventName: "geofence")
      payload["location"] = locationPayload
      if !privacyGuardEnabled {
        if shouldPersist(eventName: "geofence") {
          storage.saveLocation(
            locationPayload,
            maxDays: configManager.maxDaysToPersist,
            maxRecords: configManager.maxRecordsToPersist
          ) { [weak self] in
            self?.syncManager.syncNow(currentPayload: locationPayload)
          }
        } else {
          syncManager.syncNow(currentPayload: locationPayload)
        }
      }
    }

    let event: [String: Any] = [
      "type": "geofence",
      "data": payload
    ]
    sendEvent(
      event,
      containsRawLocation: containsRawLocation,
      privacyGuardEnabled: privacyGuardEnabled
    )
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
    guard isEnabled || pendingLocationResult != nil else {
      lastLocation = location
      return
    }
    
    if isEnabled {
      trackingStats.onLocationUpdate(accuracy: location.horizontalAccuracy)
    }

    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      locationRequestGate.complete()
      let payload = buildLocationPayload(location, eventName: "location")
      pending(payload)
    }
    if isEnabled {
      emitLocationEvent(location, eventName: "location")
    } else {
      lastLocation = location
    }

  }

  public func onLocationError(_ error: Error) {
    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      locationRequestGate.complete()
      pending(FlutterError(code: "LOCATION_ERROR", message: error.localizedDescription, details: nil))
    }

    // Emit structured error event through the stream for permission denial
    let nsError = error as NSError
    if nsError.domain == kCLErrorDomain && nsError.code == CLError.denied.rawValue {
      stopTracking()
      let errorEvent: [String: Any] = [
        "type": "error",
        "data": [
          "code": "ERR_PERMISSION_DENIED",
          "message": "Location permission denied by user"
        ]
      ]
      sendEvent(errorEvent)
    }

    appendLog("Location error: \(error.localizedDescription)", level: "error")
  }

  public func onAuthorizationChange() {
    let status = locationClient.getAuthorizationStatus()
    let hasTerminalLoss = status == .denied
      || status == .restricted
      || (isEnabled && status != .authorizedAlways)
      || !locationClient.isLocationServicesEnabled()
    if hasTerminalLoss {
      stopTracking()
      let errorEvent: [String: Any] = [
        "type": "error",
        "data": [
          "code": "ERR_PERMISSION_DENIED",
          "message": "Background location authorization or location services became unavailable"
        ]
      ]
      sendEvent(errorEvent)
    }
    emitProviderChange()
  }
}
