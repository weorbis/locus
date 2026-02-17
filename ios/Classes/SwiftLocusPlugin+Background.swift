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
    if configManager.heartbeatInterval <= 0 {
      stopHeartbeatTimer()
      return
    }
    if heartbeatTimer != nil {
      return
    }
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: configManager.heartbeatInterval, repeats: true) { [weak self] timer in
      guard let self = self, self.isEnabled, let location = self.lastLocation else {
        timer.invalidate()
        return
      }
      self.emitLocationEvent(location, eventName: "heartbeat")
    }
  }

  func stopHeartbeatTimer() {
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
  }

  func stopBackgroundRefresh() {
    let taskId = configManager.bgTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
    if taskId.isEmpty {
      return
    }
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
      BGTaskScheduler.shared.cancelAllTaskRequests()
    } else {
      UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
    }
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
    
    var isExpired = false
    task.expirationHandler = { [weak self] in
      isExpired = true
      self?.appendLog("Background refresh expired", level: "warning")
    }
    
    if configManager.batchSync || configManager.autoSync {
      let group = DispatchGroup()
      
      group.enter()
      DispatchQueue.global(qos: .utility).async { [weak self] in
        defer { group.leave() }
        guard !isExpired else { return }
        self?.syncManager.attemptBatchSync()
        _ = self?.syncManager.syncQueue(limit: self?.configManager.maxBatchSize ?? 100)
      }
      
      // Wait with timeout
      let result = group.wait(timeout: .now() + 25) // iOS gives ~30 seconds
      task.setTaskCompleted(success: result == .success && !isExpired)
    } else {
      task.setTaskCompleted(success: true)
    }
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
    guard configManager.enableHeadless else { return }

    let dispatcher = SecureStorage.shared.getInt64(forKey: SecureStorage.headlessDispatcherKey) ?? 0
    let callback = SecureStorage.shared.getInt64(forKey: SecureStorage.headlessCallbackKey) ?? 0
    guard dispatcher != 0, callback != 0 else { return }

    if headlessEngine == nil {
      guard let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcher) else {
        return
      }
      let engine = FlutterEngine(name: "locus_headless_engine", project: nil, allowHeadlessExecution: true)
      guard engine.run(withEntrypoint: callbackInfo.callbackName, libraryURI: callbackInfo.callbackLibraryPath) else {
        return
      }
      headlessEngine = engine
    }

    // Track last activity time for idle cleanup
    headlessLastActivityTime = Date()

    guard let engine = headlessEngine else { return }
    let channel = FlutterMethodChannel(name: SwiftLocusPlugin.headlessChannelName, binaryMessenger: engine.binaryMessenger)
    channel.invokeMethod("headlessEvent", arguments: [
      "callbackHandle": callback,
      "event": event
    ])

    // Schedule idle cleanup check (restarts on each dispatch)
    scheduleHeadlessCleanup()
  }

  private func scheduleHeadlessCleanup() {
    headlessCleanupTimer?.invalidate()
    headlessCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
      self?.cleanupHeadlessEngineIfIdle()
    }
  }

  private func cleanupHeadlessEngineIfIdle() {
    headlessCleanupTimer?.invalidate()
    headlessCleanupTimer = nil
    guard let engine = headlessEngine else { return }
    // Only clean up if idle for at least 60 seconds since last dispatch
    if let lastActivity = headlessLastActivityTime,
       Date().timeIntervalSince(lastActivity) < 55 {
      // Still active, reschedule
      scheduleHeadlessCleanup()
      return
    }
    engine.destroyContext()
    headlessEngine = nil
    headlessLastActivityTime = nil
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
