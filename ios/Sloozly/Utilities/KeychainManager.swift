import Foundation
import Security

// MARK: - Keychain Manager

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Save
    
    func save(_ data: Data, forKey key: String) -> Bool {
        // Delete existing item first
        delete(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func save(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, forKey: key)
    }
    
    // MARK: - Load
    
    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    func loadString(forKey key: String) -> String? {
        guard let data = load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Delete
    
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Clear All
    
    func clearAll() {
        let secClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        
        for secClass in secClasses {
            let query: [String: Any] = [kSecClass as String: secClass]
            SecItemDelete(query as CFDictionary)
        }
    }
}

// MARK: - Convenience Extensions

extension KeychainManager {
    var authToken: String? {
        get { loadString(forKey: Constants.KeychainKeys.authToken) }
        set {
            if let value = newValue {
                save(value, forKey: Constants.KeychainKeys.authToken)
            } else {
                delete(forKey: Constants.KeychainKeys.authToken)
            }
        }
    }
    
    var userId: String? {
        get { loadString(forKey: Constants.KeychainKeys.userId) }
        set {
            if let value = newValue {
                save(value, forKey: Constants.KeychainKeys.userId)
            } else {
                delete(forKey: Constants.KeychainKeys.userId)
            }
        }
    }
}
