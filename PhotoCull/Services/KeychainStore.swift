import Foundation
import Security

/// Generic-password Keychain items. The Claude API key lives here and nowhere else (spec §5.5).
enum KeychainStore {
    static let claudeAPIKey = "claude-api-key"

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "PhotoCull"
    }

    struct KeychainError: Error {
        let status: OSStatus
    }

    static func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            let add = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError(status: add) }
        } else if update != errSecSuccess {
            throw KeychainError(status: update)
        }
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
