import Flutter
import Foundation

/// Dispatcher for headless pre-sync validation on iOS.
///
/// When the Flutter app is terminated but location sync is needed,
/// this dispatcher invokes a registered Dart callback to validate
/// locations before syncing. This allows business logic validation
/// even when the app UI is not running.
class HeadlessValidationDispatcher {
    private let config: ConfigManager
    private var validationEngine: FlutterEngine?
    private let engineName = "locus_validation_engine"
    private let channelName = "locus/headless_validation"
    
    private var pendingValidation: ((Bool) -> Void)?
    private var validationTimeout: DispatchWorkItem?
    
    init(config: ConfigManager) {
        self.config = config
    }
    
    deinit {
        cleanup()
    }
    
    /// Checks if headless validation is available.
    var isAvailable: Bool {
        guard config.enableHeadless else { return false }
        let dispatcher = SecureStorage.shared.getInt64(forKey: SecureStorage.validationDispatcherKey) ?? 0
        let callback = SecureStorage.shared.getInt64(forKey: SecureStorage.validationCallbackKey) ?? 0
        return dispatcher != 0 && callback != 0
    }
    
    /// Validates locations and extras via headless callback.
    ///
    /// - Parameters:
    ///   - locations: List of location data to validate
    ///   - extras: Additional metadata for validation
    ///   - timeoutSeconds: Maximum time to wait for validation response
    ///   - completion: Callback with validation result (true = proceed, false = abort)
    func validate(
        locations: [[String: Any]],
        extras: [String: Any],
        timeoutSeconds: TimeInterval = 10,
        completion: @escaping (Bool) -> Void
    ) {
        guard config.enableHeadless else {
            log("Headless disabled, allowing sync")
            completion(true)
            return
        }
        
        guard let dispatcher = SecureStorage.shared.getInt64(forKey: SecureStorage.validationDispatcherKey),
              let callback = SecureStorage.shared.getInt64(forKey: SecureStorage.validationCallbackKey),
              dispatcher != 0, callback != 0 else {
            log("No validation callback registered, allowing sync")
            completion(true)
            return
        }
        
        // Only one validation at a time
        if pendingValidation != nil {
            log("Validation already in progress, allowing sync")
            completion(true)
            return
        }
        
        pendingValidation = completion
        
        // Set up timeout
        let timeout = DispatchWorkItem { [weak self] in
            self?.log("Validation timed out, allowing sync")
            self?.completeValidation(result: true)
        }
        validationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        
        // Start headless engine if needed
        DispatchQueue.main.async { [weak self] in
            self?.executeValidation(dispatcher: dispatcher, callback: callback, locations: locations, extras: extras)
        }
    }
    
    // MARK: - Private Methods
    
    private func executeValidation(
        dispatcher: Int64,
        callback: Int64,
        locations: [[String: Any]],
        extras: [String: Any]
    ) {
        // Create engine if needed
        if validationEngine == nil {
            guard let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcher) else {
                log("Could not lookup callback info for dispatcher")
                completeValidation(result: true)
                return
            }
            
            let engine = FlutterEngine(name: engineName, project: nil, allowHeadlessExecution: true)
            guard engine.run(withEntrypoint: callbackInfo.callbackName, libraryURI: callbackInfo.callbackLibraryPath) else {
                log("Failed to start headless engine")
                completeValidation(result: true)
                return
            }
            validationEngine = engine
        }
        
        guard let engine = validationEngine else {
            log("No engine available")
            completeValidation(result: true)
            return
        }
        
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: engine.binaryMessenger)
        
        let payload: [String: Any] = [
            "type": "validatePreSync",
            "locations": locations,
            "extras": extras
        ]
        
        let args: [String: Any] = [
            "callbackHandle": callback,
            "payload": payload
        ]
        
        channel.invokeMethod("validatePreSync", arguments: args) { [weak self] result in
            let validated = result as? Bool ?? true
            self?.log("Validation result: \(validated)")
            self?.completeValidation(result: validated)
        }
        
        // Schedule engine cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.cleanupIfIdle()
        }
    }
    
    private func completeValidation(result: Bool) {
        validationTimeout?.cancel()
        validationTimeout = nil
        
        let completion = pendingValidation
        pendingValidation = nil
        completion?(result)
    }
    
    private func cleanupIfIdle() {
        guard pendingValidation == nil else { return }
        cleanup()
    }
    
    private func cleanup() {
        validationTimeout?.cancel()
        validationTimeout = nil
        pendingValidation = nil
        validationEngine?.destroyContext()
        validationEngine = nil
    }
    
    private func log(_ message: String) {
        #if DEBUG
        print("[HeadlessValidation] \(message)")
        #endif
    }
    
    // MARK: - Static Registration Methods
    
    /// Registers the headless validation callback handles.
    /// - Parameters:
    ///   - dispatcher: The dispatcher callback handle
    ///   - callback: The validation callback handle
    static func registerCallback(dispatcher: Int64, callback: Int64) {
        _ = SecureStorage.shared.setInt64(dispatcher, forKey: SecureStorage.validationDispatcherKey)
        _ = SecureStorage.shared.setInt64(callback, forKey: SecureStorage.validationCallbackKey)
    }
}
