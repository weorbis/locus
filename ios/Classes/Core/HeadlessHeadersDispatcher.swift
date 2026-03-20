import Flutter
import Foundation

class HeadlessHeadersDispatcher {
    private let config: ConfigManager
    private var headersEngine: FlutterEngine?
    private let engineName = "locus_headers_engine"
    private let channelName = "locus/headless_headers"

    private var pendingCompletion: (([String: String]?) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    init(config: ConfigManager) {
        self.config = config
    }

    deinit {
        cleanup()
    }

    var isAvailable: Bool {
        guard config.enableHeadless else { return false }
        let dispatcher = SecureStorage.shared.getInt64(forKey: SecureStorage.headersDispatcherKey) ?? 0
        let callback = SecureStorage.shared.getInt64(forKey: SecureStorage.headersCallbackKey) ?? 0
        return dispatcher != 0 && callback != 0
    }

    func refreshHeaders(
        timeoutSeconds: TimeInterval = 10,
        completion: @escaping ([String: String]?) -> Void
    ) {
        guard config.enableHeadless else {
            completion(nil)
            return
        }
        guard let dispatcher = SecureStorage.shared.getInt64(forKey: SecureStorage.headersDispatcherKey),
              let callback = SecureStorage.shared.getInt64(forKey: SecureStorage.headersCallbackKey),
              dispatcher != 0,
              callback != 0 else {
            completion(nil)
            return
        }

        if pendingCompletion != nil {
            completion(nil)
            return
        }

        pendingCompletion = completion
        let timeout = DispatchWorkItem { [weak self] in
            self?.complete(headers: nil)
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)

        DispatchQueue.main.async { [weak self] in
            self?.execute(dispatcher: dispatcher, callback: callback)
        }
    }

    private func execute(dispatcher: Int64, callback: Int64) {
        if headersEngine == nil {
            guard let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcher) else {
                complete(headers: nil)
                return
            }

            let engine = FlutterEngine(name: engineName, project: nil, allowHeadlessExecution: true)
            guard engine.run(withEntrypoint: callbackInfo.callbackName, libraryURI: callbackInfo.callbackLibraryPath) else {
                complete(headers: nil)
                return
            }
            headersEngine = engine
        }

        guard let engine = headersEngine else {
            complete(headers: nil)
            return
        }

        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: engine.binaryMessenger)
        let args: [String: Any] = ["callbackHandle": callback]
        channel.invokeMethod("getHeaders", arguments: args) { [weak self] result in
            let headers = (result as? [String: Any])?.reduce(into: [String: String]()) { partial, entry in
                partial[entry.key] = "\(entry.value)"
            }
            self?.complete(headers: headers)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.pendingCompletion == nil else { return }
            self.cleanup()
        }
    }

    private func complete(headers: [String: String]?) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(headers)
    }

    private func cleanup() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        pendingCompletion = nil
        headersEngine?.destroyContext()
        headersEngine = nil
    }

    static func registerCallback(dispatcher: Int64, callback: Int64) {
        _ = SecureStorage.shared.setInt64(dispatcher, forKey: SecureStorage.headersDispatcherKey)
        _ = SecureStorage.shared.setInt64(callback, forKey: SecureStorage.headersCallbackKey)
    }
}
