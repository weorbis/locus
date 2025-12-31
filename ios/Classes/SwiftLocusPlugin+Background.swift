import BackgroundTasks
import Flutter
import Network
import UIKit

extension SwiftLocusPlugin {
  @objc func powerSaveModeChanged() {
    emitConnectivityChange(ProcessInfo.processInfo.isLowPowerModeEnabled, emitPowerSave: true)
  }

  func startConnectivityMonitor() {
    if networkMonitor != nil {
      return
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] _ in
      self?.emitConnectivityChange()
    }
    monitor.start(queue: networkQueue)
    networkMonitor = monitor
  }

  func stopConnectivityMonitor() {
    networkMonitor?.cancel()
    networkMonitor = nil
  }

  func startHeartbeatTimer() {
    if configManager.heartbeatInterval <= 0 || heartbeatTimer != nil {
      return
    }
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: configManager.heartbeatInterval, repeats: true) { [weak self] _ in
      guard let self = self, self.isEnabled, let location = self.lastLocation else {
        return
      }
      self.emitLocationEvent(location, eventName: "heartbeat")
    }
  }

  func stopHeartbeatTimer() {
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
  }

  func registerBackgroundTasks() {
    let taskId = configManager.bgTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
    if taskId.isEmpty {
      return
    }
    if #available(iOS 13.0, *) {
      if registeredBgTaskId == taskId {
        return
      }
      registeredBgTaskId = taskId
      BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { [weak self] task in
        guard let refreshTask = task as? BGAppRefreshTask else {
          task.setTaskCompleted(success: false)
          return
        }
        self?.handleBackgroundRefresh(refreshTask)
      }
    } else {
      UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
  }

  @available(iOS 13.0, *)
  func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    scheduleBackgroundRefresh()
    task.expirationHandler = { [weak self] in
      self?.appendLog("Background refresh expired", level: "warning")
    }
    if configManager.batchSync || configManager.autoSync {
      syncManager.attemptBatchSync()
      _ = syncManager.syncQueue(limit: configManager.maxBatchSize)
    }
    task.setTaskCompleted(success: true)
  }

  func scheduleBackgroundRefresh() {
    let taskId = configManager.bgTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
    if taskId.isEmpty {
      return
    }
    if #available(iOS 13.0, *) {
      let request = BGAppRefreshTaskRequest(identifier: taskId)
      let interval = max(900, configManager.heartbeatInterval > 0 ? configManager.heartbeatInterval : 900)
      request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        appendLog("Failed to schedule background refresh: \(error.localizedDescription)", level: "warning")
      }
    } else {
      UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
  }

  func dispatchHeadlessEvent(_ event: [String: Any]) {
    if !configManager.enableHeadless {
      return
    }
    let dispatcher = UserDefaults.standard.object(forKey: SwiftLocusPlugin.headlessDispatcherKey) as? Int64 ?? 0
    let callback = UserDefaults.standard.object(forKey: SwiftLocusPlugin.headlessCallbackKey) as? Int64 ?? 0
    if dispatcher == 0 || callback == 0 {
      return
    }
    if headlessEngine == nil {
      guard let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcher) else {
        return
      }
      let engine = FlutterEngine(name: "locus_headless_engine", project: nil, allowHeadlessExecution: true)
      engine.run(withEntrypoint: callbackInfo.callbackName, libraryURI: callbackInfo.callbackLibraryPath)
      headlessEngine = engine
    }
    guard let engine = headlessEngine else {
      return
    }
    let channel = FlutterMethodChannel(name: SwiftLocusPlugin.headlessChannelName, binaryMessenger: engine.binaryMessenger)
    channel.invokeMethod("headlessEvent", arguments: [
      "callbackHandle": callback,
      "event": event
    ])
  }

  func startBackgroundTask() -> Int {
    let taskId = backgroundTaskCounter
    backgroundTaskCounter += 1
    let identifier = UIApplication.shared.beginBackgroundTask(withName: "locus-bg-task-\(taskId)") { [weak self] in
      self?.endBackgroundTask(taskId)
    }
    backgroundTasks[taskId] = identifier
    return taskId
  }

  func endBackgroundTask(_ taskId: Int) {
    if let identifier = backgroundTasks.removeValue(forKey: taskId),
       identifier != UIBackgroundTaskIdentifier.invalid {
      UIApplication.shared.endBackgroundTask(identifier)
    }
  }

  func releaseBackgroundTasks() {
    for taskId in backgroundTasks.keys {
      endBackgroundTask(taskId)
    }
  }

  func maybeStartOnBoot() {
    let status = locationClient.getAuthorizationStatus()
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      startTracking()
    }
  }
}
