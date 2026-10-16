import Foundation
import Security

/// Minimal wrapper for storing secrets (SmartThings credentials and tokens) in the Keychain.
enum Keychain {
    private static let service = "com.robhouseblues.controlinho"

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        data(for: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    static func setValue<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}
