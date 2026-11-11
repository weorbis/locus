import Foundation
import Security

/// Secure storage utility using iOS Keychain.
/// Provides encrypted storage for sensitive data like headless callback handles.
/// Legacy plaintext values are read only long enough to migrate them.
class SecureStorage {
    struct CallbackHandles: Codable, Equatable {
        let version: Int
        let dispatcher: Int64
        let callback: Int64

        init(dispatcher: Int64, callback: Int64) {
            version = 1
            self.dispatcher = dispatcher
            self.callback = callback
        }
    }

    private let serviceName: String
    private let accessGroup: String?

    /// Keys for secure storage
    static let headlessDispatcherKey = "bg_headless_dispatcher"
    static let headlessCallbackKey = "bg_headless_callback"
    static let headlessSyncBodyDispatcherKey = "bg_headless_sync_body_dispatcher"
    static let headlessSyncBodyCallbackKey = "bg_headless_sync_body_callback"
    static let validationDispatcherKey = "bg_validation_dispatcher"
    static let validationCallbackKey = "bg_validation_callback"
    static let headersDispatcherKey = "bg_headers_dispatcher"
    static let headersCallbackKey = "bg_headers_callback"
    static let headlessHandlesKey = "bg_headless_handles_v1"
    static let headlessSyncBodyHandlesKey = "bg_headless_sync_body_handles_v1"
    static let validationHandlesKey = "bg_validation_handles_v1"
    static let headersHandlesKey = "bg_headers_handles_v1"

    static let shared = SecureStorage()
    static let databaseKeyByteCount = 32
    private static let databaseKeyAccount = "locus_database_key_v1"

    init(serviceName: String = "dev.locus.secureStorage", accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    // MARK: - Int64 Operations (for callback handles)

    func setInt64(_ value: Int64, forKey key: String) -> Bool {
        let data = withUnsafeBytes(of: value) { Data($0) }
        return setData(data, forKey: key)
    }

    func getInt64(forKey key: String) -> Int64? {
        let read = readKeychainData(forKey: key)
        if read.status == errSecSuccess,
           let data = read.data,
           data.count == MemoryLayout<Int64>.size {
            return data.withUnsafeBytes { $0.load(as: Int64.self) }
        }
        guard read.status == errSecItemNotFound else {
            return nil
        }

        // Backwards-compatible migration for the oldest raw UserDefaults form.
        // Never return plaintext unless the Keychain write succeeds.
        guard let value = UserDefaults.standard.object(forKey: key) as? Int64,
              setInt64(value, forKey: key) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return value
    }

    func setCallbackHandles(
        dispatcher: Int64,
        callback: Int64,
        forKey key: String
    ) -> Bool {
        let handles = CallbackHandles(dispatcher: dispatcher, callback: callback)
        guard let data = try? JSONEncoder().encode(handles) else { return false }
        return setData(data, forKey: key)
    }

    func getCallbackHandles(
        forKey key: String,
        legacyDispatcherKey: String,
        legacyCallbackKey: String
    ) -> CallbackHandles? {
        let read = readKeychainData(forKey: key)
        if read.status == errSecSuccess,
           let data = read.data,
           let handles = try? JSONDecoder().decode(CallbackHandles.self, from: data),
           handles.version == 1 {
            return handles
        }
        guard read.status == errSecItemNotFound else { return nil }

        guard let dispatcher = getInt64(forKey: legacyDispatcherKey),
              let callback = getInt64(forKey: legacyCallbackKey) else {
            return nil
        }
        let handles = CallbackHandles(dispatcher: dispatcher, callback: callback)
        if setCallbackHandles(dispatcher: dispatcher, callback: callback, forKey: key) {
            _ = removeValue(forKey: legacyDispatcherKey)
            _ = removeValue(forKey: legacyCallbackKey)
        }
        return handles
    }

    func removeValue(forKey key: String) -> Bool {
        return deleteData(forKey: key)
    }

    // MARK: - Data Operations

    /// Returns the database key. A new key is created only when `mayCreate` is
    /// true; callers pass false while an encrypted database exists, because a
    /// replacement key could never open it and would make the loss permanent.
    func databaseKey(mayCreate: Bool) throws -> Data {
        let read = readKeychainData(forKey: Self.databaseKeyAccount)
        if read.status == errSecSuccess {
            guard let data = read.data, data.count == Self.databaseKeyByteCount else {
                throw NSError(domain: "dev.locus.storage", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Database Keychain key has an invalid length"
                ])
            }
            return data
        }
        guard read.status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(read.status))
        }
        guard mayCreate else {
            logError("Encrypted database exists but its Keychain key is missing; no new key was created and no file was changed")
            throw NSError(domain: "dev.locus.storage", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The Keychain key for the existing encrypted database is missing"
            ])
        }

        var bytes = [UInt8](repeating: 0, count: Self.databaseKeyByteCount)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(randomStatus))
        }
        let key = Data(bytes)
        var query = lookupQuery(forKey: Self.databaseKeyAccount)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        query[kSecValueData as String] = key
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return key }
        if status == errSecDuplicateItem {
            let existing = readKeychainData(forKey: Self.databaseKeyAccount)
            if existing.status == errSecSuccess,
               let data = existing.data, data.count == Self.databaseKeyByteCount {
                return data
            }
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    func setData(_ data: Data, forKey key: String) -> Bool {
        let lookup = lookupQuery(forKey: key)
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: "secure_\(key)")
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            logError("Failed to update Keychain item (status: \(updateStatus))")
            return false
        }

        var addQuery = lookup
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: "secure_\(key)")
            return true
        }
        logError("Failed to add Keychain item (status: \(addStatus)); refusing plaintext fallback")
        return false
    }

    func getData(forKey key: String) -> Data? {
        let read = readKeychainData(forKey: key)
        if read.status == errSecSuccess, let data = read.data {
            return data
        }
        guard read.status == errSecItemNotFound else {
            logError("Failed to read Keychain item (status: \(read.status))")
            return nil
        }

        // Backwards-compatible one-way migration for releases that wrote the
        // old plaintext fallback. Never return it unless migration succeeds.
        guard let data = UserDefaults.standard.data(forKey: "secure_\(key)"),
              setData(data, forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: "secure_\(key)")
        return data
    }

    private func readKeychainData(forKey key: String) -> (status: OSStatus, data: Data?) {
        var query = lookupQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    private func deleteData(forKey key: String) -> Bool {
        let query = lookupQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        // Also clean up any UserDefaults fallback
        UserDefaults.standard.removeObject(forKey: "secure_\(key)")

        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Query Building

    private func lookupQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    // MARK: - Migration

    /// Migrates existing UserDefaults values to Keychain.
    /// Call this once during initialization.
    func migrateFromUserDefaults() {
        let pairs = [
            (Self.headlessHandlesKey, Self.headlessDispatcherKey, Self.headlessCallbackKey),
            (Self.headlessSyncBodyHandlesKey, Self.headlessSyncBodyDispatcherKey, Self.headlessSyncBodyCallbackKey),
            (Self.validationHandlesKey, Self.validationDispatcherKey, Self.validationCallbackKey),
            (Self.headersHandlesKey, Self.headersDispatcherKey, Self.headersCallbackKey),
        ]
        for (pairKey, dispatcherKey, callbackKey) in pairs {
            if getCallbackHandles(
                forKey: pairKey,
                legacyDispatcherKey: dispatcherKey,
                legacyCallbackKey: callbackKey
            ) != nil {
                logDebug("Validated or migrated \(pairKey) in Keychain")
            }
        }
    }

    // MARK: - Logging

    private func logDebug(_ message: String) {
        #if DEBUG
        print("[SecureStorage] \(message)")
        #endif
    }

    private func logError(_ message: String) {
        print("[SecureStorage] ERROR: \(message)")
    }
}
