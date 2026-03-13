import Foundation
import Network

protocol SyncManagerDelegate: AnyObject {
    /// Called when SyncManager needs Dart to build a custom sync body.
    /// Returns nil to use default native body building.
    func buildSyncBody(locations: [[String: Any]], extras: [String: Any], completion: @escaping ([String: Any]?) -> Void)
    
    /// Called before sync to validate context.
    func onPreSyncValidation(locations: [[String: Any]], extras: [String: Any], completion: @escaping (Bool) -> Void)

    /// Called when location sync gets 401 and native wants one background
    /// header refresh attempt before pausing sync.
    func onHeadersRefresh(completion: @escaping ([String: String]?) -> Void)
    
    func onHttpEvent(_ event: [String: Any])
    func onSyncEvent(_ event: [String: Any])
    func onLog(level: String, message: String)
}


class SyncManager {
    
    weak var delegate: SyncManagerDelegate?
    
    /// Whether a Dart-side sync body builder is enabled
    var syncBodyBuilderEnabled = false
    private let storage: StorageManager
    private let config: ConfigManager
    
    // Simple network monitor
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "dev.locus.network")
    private let networkStateQueue = DispatchQueue(label: "dev.locus.networkstate")
    private var _isConnected = true
    private var _isCellular = false
    private var isConnected: Bool {
        get { networkStateQueue.sync { _isConnected } }
        set { networkStateQueue.sync { _isConnected = newValue } }
    }
    private var isCellular: Bool {
        get { networkStateQueue.sync { _isCellular } }
        set { networkStateQueue.sync { _isCellular = newValue } }
    }
    private var isMonitorRunning = false
    
    // Thread-safe sync pause state
    // IMPORTANT: Sync starts PAUSED by default to prevent race conditions where
    // sync fires before the app has established required context (auth tokens,
    // task IDs, etc.) after app restart.
    // The app MUST call resumeSync() after initialization is complete.
    private let syncStateQueue = DispatchQueue(label: "dev.locus.syncstate")
    private let locationDrainStateQueue = DispatchQueue(label: "dev.locus.locationdrain")
    private var _isSyncPaused = true
    private var isSyncPaused: Bool {
        get { syncStateQueue.sync { _isSyncPaused } }
        set { syncStateQueue.sync { _isSyncPaused = newValue } }
    }

    private var _isLocationSyncInFlight = false
    private var _pendingLocationDrainRequested = false
    private var isLocationSyncInFlight: Bool {
        get { locationDrainStateQueue.sync { _isLocationSyncInFlight } }
        set { locationDrainStateQueue.sync { _isLocationSyncInFlight = newValue } }
    }
    
    private var urlSession: URLSession!

    private struct RouteContext: Hashable {
        let ownerId: String
        let driverId: String
        let taskId: String
        let trackingSessionId: String
        let startedAt: String
    }

    private struct LocationBatch {
        let payloads: [[String: Any]]
        let ids: [String]
    }

    private func createURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.httpTimeout
        configuration.timeoutIntervalForResource = config.httpTimeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
    
    init(config: ConfigManager, storage: StorageManager) {
        self.config = config
        self.storage = storage
        self.urlSession = createURLSession()
        startNetworkMonitor()
        NSLog("[Locus] SyncManager initialized - sync PAUSED by default (call resumeSync() when app is ready)")
    }
    
    deinit {
        stopNetworkMonitor()
    }
    
    /// Starts the network monitor if not already running.
    private func startNetworkMonitor() {
        guard !isMonitorRunning else { return }
        
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            self?.isCellular = path.usesInterfaceType(.cellular)
        }
        monitor?.start(queue: queue)
        isMonitorRunning = true
    }
    
    /// Stops the network monitor.
    private func stopNetworkMonitor() {
        guard isMonitorRunning else { return }
        monitor?.cancel()
        monitor = nil
        isMonitorRunning = false
    }
    
    /// Releases resources. Call when plugin detaches.
    /// The monitor can be restarted by calling restart().
    func release() {
        stopNetworkMonitor()
        urlSession.invalidateAndCancel()
    }
    
    /// Restarts the network monitor and URLSession after a release.
    /// Call when plugin re-attaches.
    func restart() {
        urlSession = createURLSession()
        startNetworkMonitor()
    }

    func syncNow(currentPayload: [String: Any]? = nil) {
        guard let url = config.httpUrl, !url.isEmpty else {
            delegate?.onLog(level: "debug", message: "syncNow skipped: No URL configured. Set Config.url to enable sync.")
            return
        }
        guard !isSyncPaused else {
            delegate?.onLog(level: "debug", message: "syncNow skipped: Sync is paused (401 received). Call resumeSync() after token refresh.")
            return
        }

        if config.batchSync {
            requestLocationSync(limit: config.maxBatchSize)
            return
        }
        
        if let payload = currentPayload {
            enqueueHttp(locationPayload: payload, idsToDelete: nil, attempt: 0)
        }
    }

    func pause() {
        isSyncPaused = true
        delegate?.onLog(level: "info", message: "Sync PAUSED by app request")
    }

    func resumeSync() {
        delegate?.onLog(level: "info", message: "Sync RESUMED by app request - processing any pending locations...")
        isSyncPaused = false
        requestLocationSync(limit: config.maxBatchSize)
        _ = syncQueue(limit: 0)
    }

    /// Check if sync is currently paused.
    var isPaused: Bool { isSyncPaused }
    
    func attemptBatchSync() {
        guard let url = config.httpUrl, !url.isEmpty, isAutoSyncAllowed() else { return }
        guard !isSyncPaused else { return }

        let threshold = config.autoSyncThreshold > 0 ? config.autoSyncThreshold : config.maxBatchSize
        let backlog = buildBacklog()
        if backlog.pendingLocationCount < threshold {
            return
        }

        requestLocationSync(limit: config.maxBatchSize)
    }
    
    func syncStoredLocations(limit: Int) {
        requestLocationSync(limit: limit)
    }
    
    func syncQueue(limit: Int) -> Int {
        guard let url = config.httpUrl, !url.isEmpty else { return 0 }
        guard !isSyncPaused else { return 0 }
        
        let fetchLimit = limit > 0 ? limit : config.maxBatchSize
        let stored = storage.readQueue()
        if stored.isEmpty { return 0 }
        
        let now = Date()
        let formatter = ISO8601DateFormatter()
        var scheduled = 0
        
        for item in stored {
            if scheduled >= fetchLimit { break }
            
            if let nextRetryAt = item["nextRetryAt"] as? String,
               let date = formatter.date(from: nextRetryAt),
               date > now {
                continue
            }
            
            guard let id = item["id"] as? String,
                  let payload = item["payload"] as? [String: Any] else {
                continue
            }
            
            let type = item["type"] as? String
            let key = (item["idempotencyKey"] as? String) ?? UUID().uuidString
            let retryCount = item["retryCount"] as? Int ?? 0
            
            enqueueQueueHttp(payload: payload, id: id, type: type, idempotencyKey: key, attempt: retryCount)
            scheduled += 1
        }
        
        return scheduled
    }

    func getLocationSyncBacklog() -> [String: Any] {
        let backlog = buildBacklog()
        return [
            "pendingLocationCount": backlog.pendingLocationCount,
            "pendingBatchCount": backlog.pendingBatchCount,
            "isPaused": isSyncPaused,
            "quarantinedLocationCount": backlog.quarantinedLocationCount,
            "lastSuccessAt": readLastSuccessAt() as Any,
            "lastFailureReason": readLastFailureReason() as Any,
            "groups": backlog.groups
        ]
    }

    private struct BacklogSnapshot {
        let pendingLocationCount: Int
        let pendingBatchCount: Int
        let quarantinedLocationCount: Int
        let groups: [[String: Any]]
    }

    private func requestLocationSync(limit: Int) {
        guard let url = config.httpUrl, !url.isEmpty else { return }
        guard !isSyncPaused else { return }

        let batch: LocationBatch? = locationDrainStateQueue.sync {
            _pendingLocationDrainRequested = true
            guard !_isLocationSyncInFlight else { return nil }
            guard let nextBatch = selectNextLocationBatch(limit: limit) else {
                _pendingLocationDrainRequested = false
                return nil
            }
            _isLocationSyncInFlight = true
            _pendingLocationDrainRequested = false
            return nextBatch
        }

        guard let batch else { return }
        enqueueHttpBatch(payloads: batch.payloads, idsToDelete: batch.ids, attempt: 0)
    }

    private func completeLocationSync(continueDrain: Bool) {
        let shouldContinue = locationDrainStateQueue.sync { () -> Bool in
            _isLocationSyncInFlight = false
            if continueDrain {
                _pendingLocationDrainRequested = true
            }
            let next = _pendingLocationDrainRequested
            _pendingLocationDrainRequested = false
            return next
        }

        if shouldContinue && !isSyncPaused {
            requestLocationSync(limit: config.maxBatchSize)
        }
    }

    private func selectNextLocationBatch(limit: Int) -> LocationBatch? {
        let effectiveLimit = limit > 0 ? limit : config.maxBatchSize
        let stored = Array(storage.readLocations().reversed())
        guard !stored.isEmpty else { return nil }

        var selectedContext: RouteContext?
        var payloads: [[String: Any]] = []
        var ids: [String] = []

        for payload in stored {
            guard let context = extractRouteContext(from: payload) else {
                continue
            }
            if selectedContext == nil {
                selectedContext = context
            }
            guard selectedContext == context else {
                continue
            }
            payloads.append(payload)
            if let uuid = payload["uuid"] as? String {
                ids.append(uuid)
            }
            if payloads.count >= effectiveLimit {
                break
            }
        }

        guard !payloads.isEmpty else { return nil }
        return LocationBatch(payloads: payloads, ids: ids)
    }

    private func buildBacklog() -> BacklogSnapshot {
        let stored = storage.readLocations()
        var groupedCounts: [RouteContext: Int] = [:]
        var pendingLocationCount = 0
        var quarantinedLocationCount = 0

        for payload in stored {
            guard let context = extractRouteContext(from: payload) else {
                quarantinedLocationCount += 1
                continue
            }
            pendingLocationCount += 1
            groupedCounts[context, default: 0] += 1
        }

        let pendingBatchCount = groupedCounts.values.reduce(0) { partial, count in
            partial + max(1, Int(ceil(Double(count) / Double(config.maxBatchSize))))
        }
        let groups = groupedCounts.map { entry in
            [
                "ownerId": entry.key.ownerId,
                "driverId": entry.key.driverId,
                "taskId": entry.key.taskId,
                "trackingSessionId": entry.key.trackingSessionId,
                "startedAt": entry.key.startedAt,
                "pendingLocationCount": entry.value,
            ]
        }

        return BacklogSnapshot(
            pendingLocationCount: pendingLocationCount,
            pendingBatchCount: pendingBatchCount,
            quarantinedLocationCount: quarantinedLocationCount,
            groups: groups
        )
    }

    private func extractRouteContext(from payload: [String: Any]) -> RouteContext? {
        guard let extras = payload["extras"] as? [String: Any] else { return nil }
        let ownerId = (extras["owner_id"] as? String) ?? ""
        let driverId = (extras["driver_id"] as? String) ?? ""
        let taskId = (extras["task_id"] as? String) ?? ""
        let trackingSessionId = (extras["tracking_session_id"] as? String) ?? ""
        let startedAt = (extras["started_at"] as? String) ?? ""
        guard !ownerId.isEmpty,
              !driverId.isEmpty,
              !taskId.isEmpty,
              !trackingSessionId.isEmpty,
              !startedAt.isEmpty else {
            return nil
        }
        return RouteContext(
            ownerId: ownerId,
            driverId: driverId,
            taskId: taskId,
            trackingSessionId: trackingSessionId,
            startedAt: startedAt
        )
    }

    private func recordSyncSuccess() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: "bg_last_location_sync_success_at")
        UserDefaults.standard.removeObject(forKey: "bg_last_location_sync_failure_reason")
    }

    private func recordSyncFailure(_ reason: String) {
        UserDefaults.standard.set(reason, forKey: "bg_last_location_sync_failure_reason")
    }

    private func readLastSuccessAt() -> String? {
        let raw = UserDefaults.standard.double(forKey: "bg_last_location_sync_success_at")
        guard raw > 0 else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: raw / 1000))
    }

    private func readLastFailureReason() -> String? {
        UserDefaults.standard.string(forKey: "bg_last_location_sync_failure_reason")
    }
    
    // MARK: - Private Http
    
    private func isAutoSyncAllowed() -> Bool {
        if !isConnected { return false }
        if config.disableAutoSyncOnCellular && isCellular { return false }
        return true
    }
    
    private func makeRequest(_ urlString: String, body: [String: Any]) -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = config.httpMethod
        request.timeoutInterval = config.httpTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mergedHeaders = config.httpHeaders.merging(config.dynamicHeaders) { _, dynamicValue in
            dynamicValue
        }

        for (k, v) in mergedHeaders {
            let sanitizedKey = sanitizeHeaderKey(k)
            let sanitizedValue = sanitizeHeaderValue(v)
            request.setValue(sanitizedValue, forHTTPHeaderField: sanitizedKey)
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return nil
        }

        return request
    }

    private func sanitizeHeaderKey(_ key: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\r\n")
        return key.components(separatedBy: invalidCharacters).joined(separator: "").trimmingCharacters(in: .whitespaces)
    }

    private func sanitizeHeaderValue(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\r\n")
        return value.components(separatedBy: invalidCharacters).joined(separator: "").trimmingCharacters(in: .whitespaces)
    }
    
    private func enqueueHttp(locationPayload: [String: Any], idsToDelete: [String]?, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        let proceedBlock = { [weak self] (proceed: Bool) in
            guard let self = self else { return }
            guard proceed else {
                self.delegate?.onHttpEvent([
                    "type": "http",
                    "data": [
                        "status": 0,
                        "ok": false,
                        "responseText": "pre_sync_validator_rejected"
                    ]
                ])
                self.delegate?.onLog(
                    level: "error",
                    message: "pre-sync validator rejected locations=1 extras=\(self.config.extras)"
                )
                self.recordSyncFailure("pre_sync_validator_rejected")
                self.completeLocationSync(continueDrain: false)
                return
            }
            
            // If sync body builder is enabled, ask Dart to build the body
            if self.syncBodyBuilderEnabled {
                self.delegate?.buildSyncBody(locations: [locationPayload], extras: self.config.extras) { [weak self] customBody in
                    guard let self = self else { return }
                    self.queue.async {
                        guard let body = customBody else {
                            self.delegate?.onHttpEvent([
                                "type": "http",
                                "data": [
                                    "status": 0,
                                    "ok": false,
                                    "responseText": "sync_body_builder_failed"
                                ]
                            ])
                            self.delegate?.onLog(
                                level: "error",
                                message: "sync body builder failed locations=1 extras=\(self.config.extras)"
                            )
                            self.recordSyncFailure("sync_body_builder_failed")
                            self.scheduleRetry(payload: locationPayload, idsToDelete: idsToDelete, attempt: attempt + 1)
                            self.completeLocationSync(continueDrain: false)
                            return
                        }
                        guard let request = self.makeRequest(urlString, body: body) else { return }
                        
                        let task = self.urlSession.dataTask(with: request) { data, response, error in
                            self.handleResponse(data: data, response: response, error: error,
                                              payload: locationPayload, idsToDelete: idsToDelete,
                                              attempt: attempt, isBatch: false)
                        }
                        task.resume()
                    }
                }
            } else {
                self.queue.async {
                    let body = self.buildHttpBody(locationPayload: locationPayload, locations: nil)
                    guard let request = self.makeRequest(urlString, body: body) else { return }
                    
                    let task = self.urlSession.dataTask(with: request) { data, response, error in
                        self.handleResponse(data: data, response: response, error: error,
                                          payload: locationPayload, idsToDelete: idsToDelete,
                                          attempt: attempt, isBatch: false)
                    }
                    task.resume()
                }
            }
        }
        
        if let delegate = delegate {
            delegate.onPreSyncValidation(locations: [locationPayload], extras: config.extras, completion: proceedBlock)
        } else {
            proceedBlock(true)
        }
    }
    
    private func enqueueHttpBatch(payloads: [[String: Any]], idsToDelete: [String]?, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        let proceedBlock = { [weak self] (proceed: Bool) in
            guard let self = self else { return }
            guard proceed else {
                self.delegate?.onHttpEvent([
                    "type": "http",
                    "data": [
                        "status": 0,
                        "ok": false,
                        "responseText": "pre_sync_validator_rejected"
                    ]
                ])
                self.delegate?.onLog(
                    level: "error",
                    message: "pre-sync validator rejected locations=\(payloads.count) extras=\(self.config.extras)"
                )
                self.recordSyncFailure("pre_sync_validator_rejected")
                self.completeLocationSync(continueDrain: false)
                return
            }
            
            // If sync body builder is enabled, ask Dart to build the body
            if self.syncBodyBuilderEnabled {
                self.delegate?.buildSyncBody(locations: payloads, extras: self.config.extras) { [weak self] customBody in
                    guard let self = self else { return }
                    self.queue.async {
                        guard let body = customBody else {
                            self.delegate?.onHttpEvent([
                                "type": "http",
                                "data": [
                                    "status": 0,
                                    "ok": false,
                                    "responseText": "sync_body_builder_failed"
                                ]
                            ])
                            self.delegate?.onLog(
                                level: "error",
                                message: "sync body builder failed locations=\(payloads.count) extras=\(self.config.extras)"
                            )
                            self.recordSyncFailure("sync_body_builder_failed")
                            self.scheduleBatchRetry(payloads: payloads, idsToDelete: idsToDelete, attempt: attempt + 1)
                            self.completeLocationSync(continueDrain: false)
                            return
                        }
                        guard let request = self.makeRequest(urlString, body: body) else { return }
                        
                        let task = self.urlSession.dataTask(with: request) { data, response, error in
                            self.handleResponse(data: data, response: response, error: error,
                                              payload: nil, idsToDelete: idsToDelete,
                                              attempt: attempt, isBatch: true, batchPayloads: payloads)
                        }
                        task.resume()
                    }
                }
            } else {
                self.queue.async {
                    let body = self.buildHttpBody(locationPayload: nil, locations: payloads)
                    guard let request = self.makeRequest(urlString, body: body) else { return }
                    
                    let task = self.urlSession.dataTask(with: request) { data, response, error in
                        self.handleResponse(data: data, response: response, error: error,
                                          payload: nil, idsToDelete: idsToDelete,
                                          attempt: attempt, isBatch: true, batchPayloads: payloads)
                    }
                    task.resume()
                }
            }
        }
        
        if let delegate = delegate {
            delegate.onPreSyncValidation(locations: payloads, extras: config.extras, completion: proceedBlock)
        } else {
            proceedBlock(true)
        }
    }
    
    private func enqueueQueueHttp(payload: [String: Any], id: String, type: String?, idempotencyKey: String, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        queue.async {
            var body = self.buildQueueBody(payload: payload, id: id, type: type, idempotencyKey: idempotencyKey)
            guard var request = self.makeRequest(urlString, body: body) else { return }
            
            let header = self.sanitizeHeaderKey(self.config.idempotencyHeader)
            if !header.isEmpty {
                request.setValue(idempotencyKey, forHTTPHeaderField: header)
            }
            
            let task = self.urlSession.dataTask(with: request) { data, response, error in
                self.handleQueueResponse(data: data, response: response, error: error,
                                         payload: payload, id: id, type: type,
                                         idempotencyKey: idempotencyKey, attempt: attempt)
            }
            task.resume()
        }
    }
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?,
                                payload: [String: Any]?, idsToDelete: [String]?,
                                attempt: Int, isBatch: Bool, batchPayloads: [[String: Any]]? = nil) {
        
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        let ok = status >= 200 && status < 300
        let responseText: String
        if let data = data {
            responseText = String(data: data, encoding: .utf8) ?? ""
        } else {
            responseText = error?.localizedDescription ?? ""
        }
        
        if status == 401 {
            attemptLocationHeadersRecovery { [weak self] recovered in
                guard let self else { return }
                if recovered {
                    if isBatch, let batch = batchPayloads {
                        self.enqueueHttpBatch(payloads: batch, idsToDelete: idsToDelete, attempt: attempt)
                    } else if let payload {
                        self.enqueueHttp(locationPayload: payload, idsToDelete: idsToDelete, attempt: attempt)
                    }
                    return
                }

                self.recordSyncFailure("http_401")
                self.isSyncPaused = true
                self.delegate?.onHttpEvent([
                    "type": "http",
                    "data": [
                        "status": 401,
                        "ok": false,
                        "responseText": responseText
                    ]
                ])
                self.delegate?.onLog(level: "error", message: "http 401 - sync paused")
                self.completeLocationSync(continueDrain: false)
            }
            return
        }

        if ok, let ids = idsToDelete {
            storage.removeLocations(ids)
            recordSyncSuccess()
        }
        
        let event: [String: Any] = [
            "type": "http",
            "data": [
                "status": status,
                "ok": ok,
                "responseText": responseText
            ]
        ]
        delegate?.onHttpEvent(event)
        delegate?.onLog(level: ok ? "info" : "error", message: "http \(status) \(ok ? "" : responseText)")

        if !ok {
            recordSyncFailure("http_\(status)")
            if isBatch, let batch = batchPayloads {
                scheduleBatchRetry(payloads: batch, idsToDelete: idsToDelete, attempt: attempt + 1)
            } else if let p = payload {
                scheduleRetry(payload: p, idsToDelete: idsToDelete, attempt: attempt + 1)
            }
            completeLocationSync(continueDrain: false)
        } else {
            completeLocationSync(continueDrain: true)
        }
    }
    
    private func handleQueueResponse(data: Data?, response: URLResponse?, error: Error?,
                                     payload: [String: Any], id: String, type: String?,
                                     idempotencyKey: String, attempt: Int) {
        
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        let ok = status >= 200 && status < 300
        let responseText: String
        if let data = data {
            responseText = String(data: data, encoding: .utf8) ?? ""
        } else {
            responseText = error?.localizedDescription ?? ""
        }
        
        if ok {
            storage.removeQueueItems([id])
        }
        
        let event: [String: Any] = [
            "type": "http",
            "data": [
                "status": status,
                "ok": ok,
                "responseText": responseText
            ]
        ]
        delegate?.onHttpEvent(event)
        delegate?.onLog(level: ok ? "info" : "error", message: "http \(status) \(ok ? "" : responseText)")

        if !ok {
            scheduleQueueRetry(payload: payload, id: id, type: type, idempotencyKey: idempotencyKey, attempt: attempt + 1)
        }
    }

    private func attemptLocationHeadersRecovery(completion: @escaping (Bool) -> Void) {
        delegate?.onHeadersRefresh { [weak self] headers in
            guard let self else {
                completion(false)
                return
            }
            guard let headers,
                  let authHeader = headers["Authorization"],
                  !authHeader.isEmpty else {
                completion(false)
                return
            }
            self.config.dynamicHeaders = headers
            completion(true)
        } ?? completion(false)
    }
    
    private func scheduleRetry(payload: [String: Any], idsToDelete: [String]?, attempt: Int) {
        if attempt > config.maxRetry {
            // Max retries exhausted - emit abandoned event
            emitDeadLetterEvent(payload: payload, reason: "max_retries_exhausted", attempts: attempt)
            return
        }
        
        let delay = calculateDelay(attempt)
        queue.asyncAfter(deadline: .now() + delay) {
            self.enqueueHttp(locationPayload: payload, idsToDelete: idsToDelete, attempt: attempt)
        }
    }
    
    private func scheduleBatchRetry(payloads: [[String: Any]], idsToDelete: [String]?, attempt: Int) {
        if attempt > config.maxRetry {
            // Max retries exhausted - emit abandoned event for batch
            for payload in payloads {
                emitDeadLetterEvent(payload: payload, reason: "max_retries_exhausted", attempts: attempt)
            }
            return
        }
        
        let delay = calculateDelay(attempt)
        queue.asyncAfter(deadline: .now() + delay) {
            self.enqueueHttpBatch(payloads: payloads, idsToDelete: idsToDelete, attempt: attempt)
        }
    }
    
    private func scheduleQueueRetry(payload: [String: Any], id: String, type: String?, idempotencyKey: String, attempt: Int) {
        if attempt > config.maxRetry {
            // Max retries exhausted - move to dead letter and emit event
            storage.moveToDeadLetter(id)
            emitDeadLetterEvent(payload: payload, reason: "max_retries_exhausted", attempts: attempt)
            return
        }
        
        let delay = calculateDelay(attempt)
        let nextRetryAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(delay))
        storage.updateQueueItem(id, attempt: attempt, nextRetry: nextRetryAt)
        
        queue.asyncAfter(deadline: .now() + delay) {
            self.enqueueQueueHttp(payload: payload, id: id, type: type, idempotencyKey: idempotencyKey, attempt: attempt)
        }
    }
    
    private func emitDeadLetterEvent(payload: [String: Any], reason: String, attempts: Int) {
        delegate?.onSyncEvent([
            "type": "deadletter",
            "data": [
                "reason": reason,
                "attempts": attempts,
                "payload": payload,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ])
    }
    
    private func calculateDelay(_ attempt: Int) -> TimeInterval {
        var delay = config.retryDelay * pow(config.retryDelayMultiplier, Double(max(0, attempt - 1)))
        if delay > config.maxRetryDelay {
            delay = config.maxRetryDelay
        }
        return max(delay, config.retryDelay)
    }
    
    private func buildHttpBody(locationPayload: [String: Any]?, locations: [[String: Any]]?) -> [String: Any] {
        var body: [String: Any] = [:]
        
        // Merge extras at top level first (user-defined envelope fields)
        for (k, v) in config.extras {
            body[k] = v
        }
        
        // Add locations under the specified root property
        if let locations = locations {
            let key = (config.httpRootProperty?.isEmpty == false) ? config.httpRootProperty! : "locations"
            body[key] = locations
        } else if let locationPayload = locationPayload {
            let key = (config.httpRootProperty?.isEmpty == false) ? config.httpRootProperty! : "location"
            body[key] = locationPayload
        }
        
        // Merge params (for URL params that also go in body)
        for (k, v) in config.httpParams {
            body[k] = v
        }
        return body
    }
    
    private func buildQueueBody(payload: [String: Any], id: String, type: String?, idempotencyKey: String) -> [String: Any] {
        var body: [String: Any] = [:]
        
        let key = (config.httpRootProperty?.isEmpty == false) ? config.httpRootProperty! : "payload"
        body[key] = payload
        
        body["queueId"] = id
        if let t = type { body["type"] = t }
        body["idempotencyKey"] = idempotencyKey
        
        for (k, v) in config.httpParams {
            body[k] = v
        }
        
        return body
    }
}
