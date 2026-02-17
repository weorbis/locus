import Foundation
import Security

/// Secure storage utility using iOS Keychain.
/// Provides encrypted storage for sensitive data like headless callback handles.
/// Falls back to UserDefaults if Keychain operations fail.
class SecureStorage {
    private let serviceName: String
    private let accessGroup: String?
    
    /// Keys for secure storage
    static let headlessDispatcherKey = "bg_headless_dispatcher"
    static let headlessCallbackKey = "bg_headless_callback"
    static let headlessSyncBodyDispatcherKey = "bg_headless_sync_body_dispatcher"
    static let headlessSyncBodyCallbackKey = "bg_headless_sync_body_callback"
    static let validationDispatcherKey = "bg_validation_dispatcher"
    static let validationCallbackKey = "bg_validation_callback"
    
    static let shared = SecureStorage()
    
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
        guard let data = getData(forKey: key), data.count == MemoryLayout<Int64>.size else {
            // Try fallback to UserDefaults for migration
            if let value = UserDefaults.standard.object(forKey: key) as? Int64 {
                // Migrate to Keychain
                _ = setInt64(value, forKey: key)
                UserDefaults.standard.removeObject(forKey: key)
                return value
            }
            return nil
        }
        return data.withUnsafeBytes { $0.load(as: Int64.self) }
    }
    
    func removeValue(forKey key: String) -> Bool {
        return deleteData(forKey: key)
    }
    
    // MARK: - Data Operations
    
    private func setData(_ data: Data, forKey key: String) -> Bool {
        // Delete existing item first
        _ = deleteData(forKey: key)
        
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else {
            // Fallback to UserDefaults if Keychain fails.
            // WARNING: Data stored in UserDefaults is not encrypted.
            logError("Failed to store in Keychain (status: \(status)), using UserDefaults fallback. Data will NOT be encrypted.")
            UserDefaults.standard.set(data, forKey: "secure_\(key)")
            return false
        }
    }
    
    private func getData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return data
        } else {
            // Try fallback from UserDefaults
            if let data = UserDefaults.standard.data(forKey: "secure_\(key)") {
                return data
            }
            return nil
        }
    }
    
    private func deleteData(forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        
        // Also clean up any UserDefaults fallback
        UserDefaults.standard.removeObject(forKey: "secure_\(key)")
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Query Building
    
    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
        let keysToMigrate = [
            SecureStorage.headlessDispatcherKey,
            SecureStorage.headlessCallbackKey,
            SecureStorage.headlessSyncBodyDispatcherKey,
            SecureStorage.headlessSyncBodyCallbackKey
        ]
        
        for key in keysToMigrate {
            if let value = UserDefaults.standard.object(forKey: key) as? Int64 {
                if setInt64(value, forKey: key) {
                    UserDefaults.standard.removeObject(forKey: key)
                    logDebug("Migrated \(key) to Keychain")
                }
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
