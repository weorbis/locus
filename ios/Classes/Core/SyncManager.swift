import Foundation
import Network

protocol SyncManagerDelegate: AnyObject {
    /// Called when SyncManager needs Dart to build a custom sync body.
    /// Returns nil to use default native body building.
    func buildSyncBody(locations: [[String: Any]], extras: [String: Any], completion: @escaping ([String: Any]?) -> Void)
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
    private var isConnected = true
    private var isCellular = false
    private var isMonitorRunning = false
    
    // Thread-safe sync pause state
    private let syncStateQueue = DispatchQueue(label: "dev.locus.syncstate")
    private var _isSyncPaused = false
    private var isSyncPaused: Bool {
        get { syncStateQueue.sync { _isSyncPaused } }
        set { syncStateQueue.sync { _isSyncPaused = newValue } }
    }
    
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.httpTimeout
        configuration.timeoutIntervalForResource = config.httpTimeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()
    
    init(config: ConfigManager, storage: StorageManager) {
        self.config = config
        self.storage = storage
        startNetworkMonitor()
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
    
    /// Restarts the network monitor after a release.
    /// Call when plugin re-attaches.
    func restart() {
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
            attemptBatchSync()
            return
        }
        
        if let payload = currentPayload {
            enqueueHttp(locationPayload: payload, idsToDelete: nil, attempt: 0)
        }
    }

    func resumeSync() {
        isSyncPaused = false
        syncStoredLocations(limit: config.maxBatchSize)
        _ = syncQueue(limit: 0)
    }
    
    func attemptBatchSync() {
        guard let url = config.httpUrl, !url.isEmpty, isAutoSyncAllowed() else { return }
        guard !isSyncPaused else { return }
        
        let threshold = config.autoSyncThreshold > 0 ? config.autoSyncThreshold : config.maxBatchSize
        let stored = storage.readLocations()
        
        if stored.count < threshold {
            return
        }
        
        let sendCount = min(config.maxBatchSize, stored.count)
        let batch = Array(stored.prefix(sendCount))
        let ids = batch.compactMap { $0["uuid"] as? String }
        
        enqueueHttpBatch(payloads: batch, idsToDelete: ids, attempt: 0)
    }
    
    func syncStoredLocations(limit: Int) {
        guard let url = config.httpUrl, !url.isEmpty else { return }
        guard !isSyncPaused else { return }
        
        let stored = storage.readLocations()
        if stored.isEmpty { return }
        
        let sendCount = min(limit, stored.count)
        let batch = Array(stored.prefix(sendCount))
        let ids = batch.compactMap { $0["uuid"] as? String }
        
        enqueueHttpBatch(payloads: batch, idsToDelete: ids, attempt: 0)
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
        
        for (k, v) in config.httpHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return nil
        }
        
        return request
    }
    
    private func enqueueHttp(locationPayload: [String: Any], idsToDelete: [String]?, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        // If sync body builder is enabled, ask Dart to build the body
        if syncBodyBuilderEnabled {
            delegate?.buildSyncBody(locations: [locationPayload], extras: config.extras) { [weak self] customBody in
                guard let self = self else { return }
                self.queue.async {
                    let body = customBody ?? self.buildHttpBody(locationPayload: locationPayload, locations: nil)
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
            queue.async {
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
    
    private func enqueueHttpBatch(payloads: [[String: Any]], idsToDelete: [String]?, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        // If sync body builder is enabled, ask Dart to build the body
        if syncBodyBuilderEnabled {
            delegate?.buildSyncBody(locations: payloads, extras: config.extras) { [weak self] customBody in
                guard let self = self else { return }
                self.queue.async {
                    let body = customBody ?? self.buildHttpBody(locationPayload: nil, locations: payloads)
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
            queue.async {
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
    
    private func enqueueQueueHttp(payload: [String: Any], id: String, type: String?, idempotencyKey: String, attempt: Int) {
        guard let urlString = config.httpUrl else { return }
        guard !isSyncPaused else { return }
        
        queue.async {
            var body = self.buildQueueBody(payload: payload, id: id, type: type, idempotencyKey: idempotencyKey)
            guard var request = self.makeRequest(urlString, body: body) else { return }
            
            let header = self.config.idempotencyHeader.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        if ok, let ids = idsToDelete {
            storage.removeLocations(ids)
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

        if status == 401 {
            isSyncPaused = true
            delegate?.onLog(level: "error", message: "http 401 - sync paused")
            return
        }

        if !ok {
            if isBatch, let batch = batchPayloads {
                scheduleBatchRetry(payloads: batch, idsToDelete: idsToDelete, attempt: attempt + 1)
            } else if let p = payload {
                scheduleRetry(payload: p, idsToDelete: idsToDelete, attempt: attempt + 1)
            }
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

        if status == 401 {
            isSyncPaused = true
            delegate?.onLog(level: "error", message: "http 401 - sync paused")
            return
        }

        if !ok {
            scheduleQueueRetry(payload: payload, id: id, type: type, idempotencyKey: idempotencyKey, attempt: attempt + 1)
        }
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
